#include "mesh.h"
void face_push(Faces *faces, Face face) {
    if (faces->count == faces->capacity) {
        faces->capacity = faces->capacity ? 2 * faces->capacity : 16;
        faces->data = resize(faces->data, (size_t)faces->capacity * sizeof(Face));
    }
    faces->data[faces->count++] = face;
}
Faces triangulate(const Object *object) {
    Faces out = {0};
    for (int p = 0; p < object->polygon_count; ++p) {
        const Polygon *polygon = &object->polygons[p];
        for (int i = 1; i + 1 < polygon->vertices.count; ++i) {
            Face face = {
                {polygon->vertices.data[0], polygon->vertices.data[i], polygon->vertices.data[i + 1]},
                p + 1,
                polygon->line,
                polygon->group,
                out.count + 1};
            face_push(&out, face);
        }
    }
    return out;
}
static Integer floor_div(Integer a, Integer b) {
    Integer quotient = a / b;
    if (a % b < 0)
        --quotient;
    return quotient;
}
Cleanup *cleanup(const Object *object, const Options *options) {
    Cleanup *out = calloc(1, sizeof(Cleanup));
    for (int v = 1; v <= object->vertex_count; ++v) {
        out->snapped[v] = object->vertices[v];
        bool changed = false;
        for (int axis = 0; axis < 3; ++axis) {
            Integer old = out->snapped[v].v[axis],
                    value = options->snap * floor_div(2 * old + options->snap, 2 * options->snap);
            out->snapped[v].v[axis] = value;
            if (value != old)
                changed = true;
        }
        out->snapped_count += changed;
        out->representative[v] = v;
        if (options->merge)
            for (int earlier = 1; earlier < v; ++earlier)
                if (!memcmp(&out->snapped[earlier], &out->snapped[v], sizeof(Point))) {
                    out->representative[v] = earlier;
                    break;
                }
        out->merged_count += out->representative[v] != v;
    }
    Faces triangles = triangulate(object);
    out->triangles = triangles.count;
    bool used[1001] = {0};
    for (int i = 0; i < triangles.count; ++i) {
        Face face = triangles.data[i];
        for (int j = 0; j < 3; ++j)
            face.v[j] = out->representative[face.v[j]];
        const char *reason = NULL;
        if (face.v[0] == face.v[1] || face.v[1] == face.v[2] || face.v[2] == face.v[0])
            reason = "repeated";
        else {
            Point n = normal(&face, out->snapped);
            if (options->degenerate && n.v[0] == 0 && n.v[1] == 0 && n.v[2] == 0)
                reason = "zero_area";
            else if (options->duplicates)
                for (int earlier = 0; earlier < out->faces.count; ++earlier) {
                    const Face *previous = &out->faces.data[earlier];
                    bool equal = true;
                    for (int j = 0; j < 3; ++j)
                        if (face.v[j] != previous->v[0] && face.v[j] != previous->v[1] &&
                            face.v[j] != previous->v[2])
                            equal = false;
                    if (equal) {
                        reason = "duplicate";
                        break;
                    }
                }
        }
        if (reason)
            out->removed[out->removed_count++] = (Removed){face.triangle, face.polygon, face.line, reason};
        else {
            for (int j = 0; j < 3; ++j)
                used[face.v[j]] = true;
            face_push(&out->faces, face);
        }
    }
    free(triangles.data);
    for (int v = 1; v <= object->vertex_count; ++v)
        if ((options->keep_unused && out->representative[v] == v) || (!options->keep_unused && used[v])) {
            out->new_number[v] = ++out->point_count;
            out->points[out->point_count] = out->snapped[v];
        }
    for (int f = 0; f < out->faces.count; ++f)
        for (int i = 0; i < 3; ++i)
            out->faces.data[f].v[i] = out->new_number[out->faces.data[f].v[i]];
    return out;
}
void fill_faces(Faces *faces, const Loop *loop, int group) {
    for (int i = 1; i + 1 < loop->vertices.count; ++i) {
        Face face = {
            {loop->vertices.data[0], loop->vertices.data[i + 1], loop->vertices.data[i]}, 0, 0, group, 0};
        face_push(faces, face);
    }
}
