#include "mesh.h"
#include <math.h>
#include <sys/stat.h>
static const char *yes(bool value) {
    return value ? "yes" : "no";
}
static void add_number(Lines *lines, const char *name, Integer value) {
    line_push(lines, format("%s %lld", name, (long long)value));
}
static void add_text(Lines *lines, const char *name, const char *value) {
    line_push(lines, format("%s %s", name, value));
}
static Options read_options(void) {
    Options out = {.snap = 1,
                   .merge = true,
                   .degenerate = true,
                   .duplicates = true,
                   .orient = true,
                   .outward = true,
                   .keep_unused = true};
    line_push(&out.sections, text("summary"));
    line_push(&out.sections, text("components"));
    Lines lines = read_lines("input/params.txt");
    for (int i = 0; i < lines.count; ++i) {
        if (!*lines.data[i] || *lines.data[i] == '#')
            continue;
        Lines tokens = words(lines.data[i]);
        const char *name = tokens.data[0];
        if (!strcmp(name, "snap"))
            out.snap = atoi(tokens.data[1]);
        else if (!strcmp(name, "fill_holes"))
            out.fill_holes = atoi(tokens.data[1]);
        else if (!strcmp(name, "sections")) {
            free_lines(&out.sections);
            for (int j = 1; j < tokens.count; ++j)
                line_push(&out.sections, text(tokens.data[j]));
        } else if (!strcmp(name, "query")) {
            Lines query = {0};
            for (int j = 1; j < tokens.count; ++j)
                line_push(&query, text(tokens.data[j]));
            out.queries[out.query_count++] = query;
        } else {
            bool enabled = !strcmp(tokens.data[1], "on");
            if (!strcmp(name, "merge"))
                out.merge = enabled;
            else if (!strcmp(name, "degenerate"))
                out.degenerate = enabled;
            else if (!strcmp(name, "duplicates"))
                out.duplicates = enabled;
            else if (!strcmp(name, "orient"))
                out.orient = enabled;
            else if (!strcmp(name, "outward"))
                out.outward = enabled;
            else if (!strcmp(name, "keep_unused"))
                out.keep_unused = enabled;
        }
        free_lines(&tokens);
    }
    free_lines(&lines);
    return out;
}
typedef struct {
    int boundary, nonmanifold, loops, inconsistent;
    bool closed, manifold, consistent, solid, orientable;
    int euler, genus, crosscaps;
    Integer volume6;
    Point normal_sum, minimum, maximum;
    IntList inside;
} Properties;
static Properties *properties(const Faces *faces, const Point *points, const Topology *topology) {
    Properties *out = calloc((size_t)topology->component_count, sizeof(Properties));
    IntList inconsistent = inconsistent_edges(faces, topology);
    for (int i = 0; i < inconsistent.count; ++i)
        ++out[topology->face_component[topology->edges[inconsistent.data[i]].faces.data[0]]].inconsistent;
    int_free(&inconsistent);
    Loops loops = trace_loops(topology);
    for (int i = 0; i < loops.count; ++i)
        ++out[loops.data[i].component].loops;
    loops_free(&loops);
    for (int c = 0; c < topology->component_count; ++c) {
        Properties *prop = &out[c];
        for (int i = 0; i < topology->component_edges[c].count; ++i) {
            const Edge *edge = &topology->edges[topology->component_edges[c].data[i]];
            if (edge->faces.count == 1)
                ++prop->boundary;
            else if (edge->faces.count >= 3)
                ++prop->nonmanifold;
        }
        prop->closed = prop->boundary == 0;
        prop->manifold = prop->nonmanifold == 0 && topology->component_nonmanifold_vertices[c].count == 0;
        prop->consistent = prop->inconsistent == 0;
        prop->solid = prop->closed && prop->manifold && prop->consistent;
        prop->euler = topology->component_vertices[c].count - topology->component_edges[c].count +
                      topology->component_faces[c].count;
        prop->minimum = prop->maximum = points[topology->component_vertices[c].data[0]];
        for (int i = 0; i < topology->component_vertices[c].count; ++i) {
            int vertex = topology->component_vertices[c].data[i];
            for (int axis = 0; axis < 3; ++axis) {
                if (points[vertex].v[axis] < prop->minimum.v[axis])
                    prop->minimum.v[axis] = points[vertex].v[axis];
                if (points[vertex].v[axis] > prop->maximum.v[axis])
                    prop->maximum.v[axis] = points[vertex].v[axis];
            }
        }
        for (int i = 0; i < topology->component_faces[c].count; ++i) {
            const Face *face = &faces->data[topology->component_faces[c].data[i]];
            prop->volume6 += determinant(face, points);
            Point n = normal(face, points);
            for (int axis = 0; axis < 3; ++axis)
                prop->normal_sum.v[axis] += n.v[axis];
        }
    }
    return out;
}
static const char *edge_shape(const Edge *edge, const Faces *faces, const Point *points) {
    if (edge->faces.count != 2)
        return "-";
    const Face *f = &faces->data[edge->faces.data[0]], *g = &faces->data[edge->faces.data[1]];
    if (directed(f, edge->a, edge->b) == directed(g, edge->a, edge->b))
        return "inconsistent";
    int d = 0;
    for (int i = 0; i < 3; ++i)
        if (g->v[i] != edge->a && g->v[i] != edge->b)
            d = g->v[i];
    Integer side = dot(difference(points[d], points[f->v[0]]), normal(f, points));
    return side < 0 ? "convex" : side > 0 ? "concave" : "flat";
}
static Integer length2(const Edge *edge, const Point *points) {
    Point d = difference(points[edge->a], points[edge->b]);
    return dot(d, d);
}
static Lines boundaries(Loops *loops, const Topology *topology, const Faces *faces, const Options *options) {
    IntList inconsistent = inconsistent_edges(faces, topology);
    bool *bad = calloc((size_t)topology->component_count, sizeof(bool));
    for (int e = 0; e < topology->edge_count; ++e)
        if (topology->edges[e].faces.count >= 3)
            bad[topology->face_component[topology->edges[e].faces.data[0]]] = true;
    for (int i = 0; i < inconsistent.count; ++i)
        bad[topology->face_component[topology->edges[inconsistent.data[i]].faces.data[0]]] = true;
    for (int i = 0; i < loops->count; ++i) {
        Loop *loop = &loops->data[i];
        if (loop->closed) {
            int forwards = 0;
            for (int j = 0; j < loop->vertices.count; ++j) {
                int a = loop->vertices.data[j], b = loop->vertices.data[(j + 1) % loop->vertices.count];
                const Edge *edge = &topology->edges[edge_index(topology, a, b)];
                forwards += directed(&faces->data[edge->faces.data[0]], a, b);
            }
            if (forwards == 0 || forwards == loop->vertices.count) {
                loop->kind = "coherent";
                if (forwards == 0)
                    for (int a = 1, b = loop->vertices.count - 1; a < b; ++a, --b) {
                        int temporary = loop->vertices.data[a];
                        loop->vertices.data[a] = loop->vertices.data[b];
                        loop->vertices.data[b] = temporary;
                    }
            } else
                loop->kind = "mixed";
        }
        bool distinct = true;
        for (int a = 0; a < loop->vertices.count; ++a)
            for (int b = a + 1; b < loop->vertices.count; ++b)
                if (loop->vertices.data[a] == loop->vertices.data[b])
                    distinct = false;
        loop->filled = !strcmp(loop->kind, "coherent") && loop_length(loop) >= 3 &&
                       loop_length(loop) <= options->fill_holes && distinct && !bad[loop->component];
    }
    Lines lines = {0};
    add_number(&lines, "loops", loops->count);
    for (int i = 0; i < loops->count; ++i) {
        const Loop *loop = &loops->data[i];
        line_push(&lines, format("loop %d component %d length %d %s %s vertices %s", i + 1,
                                 loop->component + 1, loop_length(loop), loop->kind,
                                 loop->filled ? "filled" : "kept", list(&loop->vertices, 0)));
    }
    int nonmanifold = 0;
    for (int e = 0; e < topology->edge_count; ++e)
        if (topology->edges[e].faces.count >= 3)
            ++nonmanifold;
    add_number(&lines, "nonmanifold_edges", nonmanifold);
    for (int e = 0; e < topology->edge_count; ++e) {
        const Edge *edge = &topology->edges[e];
        if (edge->faces.count >= 3)
            line_push(&lines, format("edge %d %d faces %s", edge->a, edge->b, list(&edge->faces, 1)));
    }
    int vertices = 0;
    for (int v = 1; v <= topology->vertices; ++v)
        if (topology->fans[v] >= 2)
            ++vertices;
    add_number(&lines, "nonmanifold_vertices", vertices);
    for (int v = 1; v <= topology->vertices; ++v)
        if (topology->fans[v] >= 2)
            line_push(&lines, format("vertex %d fans %d components %s", v, topology->fans[v],
                                     list(&topology->fan_components[v], 1)));
    add_number(&lines, "inconsistent_edges", inconsistent.count);
    for (int i = 0; i < inconsistent.count; ++i) {
        const Edge *edge = &topology->edges[inconsistent.data[i]];
        line_push(&lines, format("edge %d %d faces %s", edge->a, edge->b, list(&edge->faces, 1)));
    }
    free(bad);
    int_free(&inconsistent);
    return lines;
}
static bool *nonplanar(const Object *object, const Cleanup *clean) {
    bool *out = calloc((size_t)object->polygon_count, sizeof(bool));
    for (int p = 0; p < object->polygon_count; ++p) {
        const Polygon *polygon = &object->polygons[p];
        Point sum = {{0}}, first = clean->snapped[polygon->vertices.data[0]];
        for (int i = 1; i + 1 < polygon->vertices.count; ++i) {
            Point term = cross(difference(clean->snapped[polygon->vertices.data[i]], first),
                               difference(clean->snapped[polygon->vertices.data[i + 1]], first));
            for (int axis = 0; axis < 3; ++axis)
                sum.v[axis] += term.v[axis];
        }
        for (int i = 0; i < polygon->vertices.count; ++i)
            if (dot(difference(clean->snapped[polygon->vertices.data[i]], first), sum) != 0)
                out[p] = true;
    }
    return out;
}
static char *group_names(const IntList *face_ids, const Faces *faces, const Lines *groups) {
    bool *used = calloc((size_t)groups->count, sizeof(bool));
    for (int i = 0; i < face_ids->count; ++i)
        used[faces->data[face_ids->data[i]].group] = true;
    char *out = text("");
    for (int g = 0; g < groups->count; ++g)
        if (used[g]) {
            char *next = format("%s%s%s", out, *out ? " " : "", groups->data[g]);
            free(out);
            out = next;
        }
    free(used);
    if (!*out) {
        free(out);
        return text("-");
    }
    return out;
}
static char *query_answer(const Lines *query, const Faces *faces, const Point *points, int point_count,
                          const Topology *topology, const Properties *props, const Lines *groups) {
    const char *kind = query->data[0];
    int args[3] = {0};
    for (int i = 1; i < query->count; ++i)
        args[i - 1] = atoi(query->data[i]);
    if (!strcmp(kind, "vertex")) {
        int v = args[0];
        if (v < 1 || v > point_count)
            return format("vertex %d invalid", v);
        bool boundary = false;
        for (int i = 0; i < topology->vertex_edges[v].count; ++i)
            if (topology->edges[topology->vertex_edges[v].data[i]].faces.count == 1)
                boundary = true;
        return format("vertex %d at %s faces %d valence %d fans %d boundary %s components %s", v,
                      point_text(points[v]), topology->vertex_faces[v].count, topology->vertex_edges[v].count,
                      topology->fans[v], yes(boundary), list(&topology->fan_components[v], 1));
    }
    if (!strcmp(kind, "face")) {
        int f = args[0];
        if (f < 1 || f > faces->count)
            return format("face %d invalid", f);
        const Face *face = &faces->data[f - 1];
        char *neighbors = text("");
        for (int i = 0; i < 3; ++i) {
            const Edge *edge = &topology->edges[edge_index(topology, face->v[i], face->v[(i + 1) % 3])];
            char *value =
                edge->faces.count == 1 ? text("-")
                : edge->faces.count >= 3
                    ? text("*")
                    : format("%d",
                             (edge->faces.data[0] == f - 1 ? edge->faces.data[1] : edge->faces.data[0]) + 1);
            char *next = format("%s%s%s", neighbors, i ? " " : "", value);
            free(neighbors);
            free(value);
            neighbors = next;
        }
        Point n = normal(face, points);
        char *out = format(
            "face %d vertices %d %d %d group %s polygon %s line %s component %d normal %s area %s neighbors %s",
            f, face->v[0], face->v[1], face->v[2], groups->data[face->group],
            face->polygon ? format("%d", face->polygon) : "-", face->line ? format("%d", face->line) : "-",
            topology->face_component[f - 1] + 1, point_text(n), real(sqrt((double)dot(n, n)) / 2), neighbors);
        free(neighbors);
        return out;
    }
    if (!strcmp(kind, "edge")) {
        int a = args[0] < args[1] ? args[0] : args[1], b = args[0] < args[1] ? args[1] : args[0];
        int index = edge_index(topology, a, b);
        if (index < 0)
            return format("edge %d %d none", a, b);
        const Edge *edge = &topology->edges[index];
        return format("edge %d %d faces %s kind %s shape %s len2 %lld", a, b, list(&edge->faces, 1),
                      edge->faces.count == 1   ? "boundary"
                      : edge->faces.count == 2 ? "manifold"
                                               : "nonmanifold",
                      edge_shape(edge, faces, points), (long long)length2(edge, points));
    }
    if (!strcmp(kind, "point")) {
        Point point = {{args[0], args[1], args[2]}};
        IntList inside = {0};
        int sum = 0;
        for (int c = 0; c < topology->component_count; ++c)
            if (props[c].solid) {
                int w = winding(point, &topology->component_faces[c], faces, points);
                if (w) {
                    int_push(&inside, c + 1);
                    sum += w;
                }
            }
        char *out = format("point %s inside %s winding %d", point_text(point), list(&inside, 0), sum);
        int_free(&inside);
        return out;
    }
    if (!strcmp(kind, "path")) {
        int u = args[0], v = args[1];
        if (u < 1 || u > point_count || v < 1 || v > point_count)
            return format("path %d %d invalid", u, v);
        int *parents = resize(NULL, ((size_t)point_count + 1) * sizeof(int));
        for (int i = 0; i <= point_count; ++i)
            parents[i] = -1;
        IntList queue = {0};
        int_push(&queue, u);
        parents[u] = u;
        for (int position = 0; position < queue.count; ++position) {
            int at = queue.data[position];
            for (int i = 0; i < topology->neighbors[at].count; ++i) {
                int next = topology->neighbors[at].data[i];
                if (parents[next] < 0) {
                    parents[next] = at;
                    int_push(&queue, next);
                }
            }
        }
        char *out;
        if (parents[v] < 0)
            out = format("path %d %d none", u, v);
        else {
            IntList path = {0};
            int at = v;
            while (at != u) {
                int_push(&path, at);
                at = parents[at];
            }
            int_push(&path, u);
            for (int a = 0, b = path.count - 1; a < b; ++a, --b) {
                int temporary = path.data[a];
                path.data[a] = path.data[b];
                path.data[b] = temporary;
            }
            out = format("path %d %d hops %d vertices %s", u, v, path.count - 1, list(&path, 0));
            int_free(&path);
        }
        free(parents);
        int_free(&queue);
        return out;
    }
    Point direction = {{args[0], args[1], args[2]}};
    Integer *signs = resize(NULL, (size_t)faces->count * sizeof(Integer));
    int front = 0, back = 0, side = 0, silhouette = 0;
    for (int f = 0; f < faces->count; ++f) {
        signs[f] = dot(normal(&faces->data[f], points), direction);
        front += signs[f] > 0;
        back += signs[f] < 0;
        side += signs[f] == 0;
    }
    for (int e = 0; e < topology->edge_count; ++e) {
        const Edge *edge = &topology->edges[e];
        if (edge->faces.count == 2) {
            Integer a = signs[edge->faces.data[0]], b = signs[edge->faces.data[1]];
            if ((a > 0 && b < 0) || (a < 0 && b > 0))
                ++silhouette;
        }
    }
    free(signs);
    return format("view %s front %d back %d side %d silhouette %d", point_text(direction), front, back, side,
                  silhouette);
}
int main(void) {
    mkdir("output", 0777);
    Options options = read_options();
    Object *object = read_object();
    Cleanup *clean = cleanup(object, &options);
    Faces initial = {0};
    for (int f = 0; f < clean->faces.count; ++f)
        face_push(&initial, clean->faces.data[f]);
    Topology before = analyze(&clean->faces, clean->point_count);
    IntList inconsistent = inconsistent_edges(&clean->faces, &before);
    int inconsistent_before = inconsistent.count;
    int_free(&inconsistent);
    if (options.orient)
        orient_faces(&clean->faces, &before);
    Loops loops = trace_loops(&before);
    Lines boundary = boundaries(&loops, &before, &clean->faces, &options);
    write_lines("boundaries.txt", &boundary);
    free_lines(&boundary);
    Lines groups = {0};
    for (int g = 0; g < object->groups.count; ++g)
        line_push(&groups, text(object->groups.data[g]));
    int holes = 0;
    for (int i = 0; i < loops.count; ++i)
        if (loops.data[i].filled) {
            ++holes;
            fill_faces(&clean->faces, &loops.data[i], object->groups.count);
        }
    if (holes)
        line_push(&groups, text("fill"));
    int fill_count = clean->faces.count - initial.count;
    Topology topology = analyze(&clean->faces, clean->point_count);
    Properties *props = properties(&clean->faces, clean->points, &topology);
    for (int c = 0; c < topology.component_count; ++c)
        if (props[c].solid)
            for (int d = 0; d < topology.component_count; ++d)
                if (c != d && props[d].solid) {
                    int vertex = 0;
                    for (int i = 0; i < topology.component_vertices[c].count; ++i) {
                        int v = topology.component_vertices[c].data[i];
                        if (!int_contains(&topology.component_vertices[d], v)) {
                            vertex = v;
                            break;
                        }
                    }
                    if (vertex && winding(clean->points[vertex], &topology.component_faces[d], &clean->faces,
                                          clean->points) != 0)
                        int_push(&props[c].inside, d + 1);
                }
    int outward = 0;
    for (int c = 0; c < topology.component_count; ++c)
        if (options.outward && props[c].solid && props[c].volume6 != 0 &&
            ((props[c].inside.count % 2 == 0 && props[c].volume6 < 0) ||
             (props[c].inside.count % 2 == 1 && props[c].volume6 > 0))) {
            ++outward;
            for (int i = 0; i < topology.component_faces[c].count; ++i)
                flip(&clean->faces.data[topology.component_faces[c].data[i]]);
            props[c].volume6 = -props[c].volume6;
            for (int axis = 0; axis < 3; ++axis)
                props[c].normal_sum.v[axis] = -props[c].normal_sum.v[axis];
        }
    Faces copy = {0};
    for (int f = 0; f < clean->faces.count; ++f)
        face_push(&copy, clean->faces.data[f]);
    orient_faces(&copy, &topology);
    for (int c = 0; c < topology.component_count; ++c)
        props[c].orientable = true;
    inconsistent = inconsistent_edges(&copy, &topology);
    for (int i = 0; i < inconsistent.count; ++i)
        props[topology.face_component[topology.edges[inconsistent.data[i]].faces.data[0]]].orientable = false;
    int_free(&inconsistent);
    free(copy.data);
    for (int c = 0; c < topology.component_count; ++c) {
        props[c].crosscaps = 2 - props[c].euler - props[c].loops;
        props[c].genus = props[c].crosscaps / 2;
    }
    int flipped = 0;
    for (int f = 0; f < initial.count; ++f)
        if (memcmp(initial.data[f].v, clean->faces.data[f].v, sizeof initial.data[f].v))
            ++flipped;
    bool *nonplanar_polygons = nonplanar(object, clean);
    int nonplanar_count = 0;
    for (int p = 0; p < object->polygon_count; ++p)
        nonplanar_count += nonplanar_polygons[p];
    IntList all_faces = {0};
    for (int f = 0; f < clean->faces.count; ++f)
        int_push(&all_faces, f);
    Integer total_volume = 0;
    int solids = 0;
    for (int c = 0; c < topology.component_count; ++c)
        if (props[c].solid) {
            ++solids;
            total_volume += props[c].volume6;
        }
    Lines report = {0};
    for (int section_index = 0; section_index < options.sections.count; ++section_index) {
        const char *section = options.sections.data[section_index];
        if (!strcmp(section, "summary")) {
            line_push(&report, text("[summary]"));
            add_number(&report, "lines", object->lines);
            add_number(&report, "vertices", object->vertex_count);
            add_number(&report, "polygons", object->polygon_count);
            add_number(&report, "errors", object->error_count);
            add_number(&report, "ignored", object->ignored);
            add_number(&report, "nonplanar_polygons", nonplanar_count);
            int sizes[201] = {0};
            for (int p = 0; p < object->polygon_count; ++p)
                ++sizes[object->polygons[p].vertices.count];
            for (int size = 0; size <= 200; ++size)
                if (sizes[size])
                    line_push(&report, format("polygon_size %d %d", size, sizes[size]));
            int removed[3] = {0};
            for (int r = 0; r < clean->removed_count; ++r) {
                const char *reason = clean->removed[r].reason;
                ++removed[!strcmp(reason, "repeated") ? 0 : !strcmp(reason, "zero_area") ? 1 : 2];
            }
            add_number(&report, "triangles", clean->triangles);
            add_number(&report, "snapped", clean->snapped_count);
            add_number(&report, "merged", clean->merged_count);
            add_number(&report, "removed_repeated", removed[0]);
            add_number(&report, "removed_zero_area", removed[1]);
            add_number(&report, "removed_duplicate", removed[2]);
            add_number(&report, "faces", initial.count);
            add_number(&report, "inconsistent_before", inconsistent_before);
            add_number(&report, "flipped_faces", flipped);
            add_number(&report, "outward_components", outward);
            add_number(&report, "boundary_loops", loops.count);
            add_number(&report, "holes_filled", holes);
            add_number(&report, "fill_faces", fill_count);
            add_number(&report, "final_vertices", clean->point_count);
            add_number(&report, "final_faces", clean->faces.count);
            add_number(&report, "components", topology.component_count);
            add_number(&report, "solids", solids);
            add_text(&report, "total_area", real(area(&all_faces, &clean->faces, clean->points)));
            add_text(&report, "total_volume", fraction(total_volume, 6));
        } else if (!strcmp(section, "warnings")) {
            line_push(&report, text("[warnings]"));
            for (int i = 0; i < object->error_count; ++i)
                line_push(&report, format("line %d %s", object->errors[i].line, object->errors[i].kind));
        } else if (!strcmp(section, "cleanup")) {
            line_push(&report, text("[cleanup]"));
            add_number(&report, "snapped", clean->snapped_count);
            for (int v = 1; v <= object->vertex_count; ++v)
                if (memcmp(&object->vertices[v], &clean->snapped[v], sizeof(Point)))
                    line_push(&report, format("snap %d %s to %s", v, point_text(object->vertices[v]),
                                              point_text(clean->snapped[v])));
            add_number(&report, "merged", clean->merged_count);
            for (int representative = 1; representative <= object->vertex_count; ++representative)
                if (clean->representative[representative] == representative) {
                    IntList members = {0};
                    for (int v = 1; v <= object->vertex_count; ++v)
                        if (clean->representative[v] == representative)
                            int_push(&members, v);
                    if (members.count > 1)
                        line_push(&report, format("merge %s %s",
                                                  clean->new_number[representative]
                                                      ? format("%d", clean->new_number[representative])
                                                      : "-",
                                                  list(&members, 0)));
                    int_free(&members);
                }
            add_number(&report, "removed", clean->removed_count);
            for (int r = 0; r < clean->removed_count; ++r) {
                const Removed *removed = &clean->removed[r];
                line_push(&report, format("remove %d polygon %d line %d %s", removed->triangle,
                                          removed->polygon, removed->line, removed->reason));
            }
        } else if (!strcmp(section, "components"))
            for (int c = 0; c < topology.component_count; ++c) {
                const Properties *prop = &props[c];
                line_push(&report, format("[component %d]", c + 1));
                add_text(&report, "groups",
                         group_names(&topology.component_faces[c], &clean->faces, &groups));
                add_number(&report, "faces", topology.component_faces[c].count);
                add_number(&report, "vertices", topology.component_vertices[c].count);
                add_number(&report, "edges", topology.component_edges[c].count);
                add_number(&report, "boundary_edges", prop->boundary);
                add_number(&report, "nonmanifold_edges", prop->nonmanifold);
                add_number(&report, "nonmanifold_vertices", topology.component_nonmanifold_vertices[c].count);
                add_number(&report, "boundary_loops", prop->loops);
                add_text(&report, "closed", yes(prop->closed));
                add_text(&report, "manifold", yes(prop->manifold));
                add_text(&report, "orientable", yes(prop->orientable));
                add_text(&report, "consistent", yes(prop->consistent));
                add_text(&report, "solid", yes(prop->solid));
                add_number(&report, "euler", prop->euler);
                if (!prop->manifold)
                    add_text(&report, "genus", "-");
                else if (prop->orientable)
                    add_number(&report, "genus", prop->genus);
                else
                    add_number(&report, "crosscaps", prop->crosscaps);
                add_text(&report, "volume", prop->solid ? fraction(prop->volume6, 6) : "-");
                add_text(&report, "area",
                         real(area(&topology.component_faces[c], &clean->faces, clean->points)));
                add_text(&report, "normal_sum", point_text(prop->normal_sum));
                line_push(&report,
                          format("bbox %s %s", point_text(prop->minimum), point_text(prop->maximum)));
                add_text(&report, "inside", prop->solid ? list(&prop->inside, 0) : "-");
                add_text(&report, "centroid",
                         prop->solid && prop->volume6 ? centroid(&topology.component_faces[c], &clean->faces,
                                                                 clean->points, prop->volume6)
                                                      : "-");
                int shapes[3] = {0}, angles[3] = {0};
                Integer shortest = -1, longest = 0;
                int *degrees = calloc((size_t)clean->point_count + 1, sizeof(int));
                for (int i = 0; i < topology.component_edges[c].count; ++i) {
                    const Edge *edge = &topology.edges[topology.component_edges[c].data[i]];
                    const char *shape = edge_shape(edge, &clean->faces, clean->points);
                    if (!strcmp(shape, "convex"))
                        ++shapes[0];
                    else if (!strcmp(shape, "concave"))
                        ++shapes[1];
                    else if (!strcmp(shape, "flat"))
                        ++shapes[2];
                    Integer length = length2(edge, clean->points);
                    if (shortest < 0 || length < shortest)
                        shortest = length;
                    if (length > longest)
                        longest = length;
                    ++degrees[edge->a];
                    ++degrees[edge->b];
                }
                for (int i = 0; i < topology.component_faces[c].count; ++i) {
                    const char *angle = triangle_angle(
                        &clean->faces.data[topology.component_faces[c].data[i]], clean->points);
                    ++angles[!strcmp(angle, "acute") ? 0 : !strcmp(angle, "right") ? 1 : 2];
                }
                add_number(&report, "convex", shapes[0]);
                add_number(&report, "concave", shapes[1]);
                add_number(&report, "flat", shapes[2]);
                add_number(&report, "acute", angles[0]);
                add_number(&report, "right", angles[1]);
                add_number(&report, "obtuse", angles[2]);
                line_push(&report, format("edge_len2 %lld %lld", (long long)shortest, (long long)longest));
                int low = topology.edge_count, high = 0;
                for (int i = 0; i < topology.component_vertices[c].count; ++i) {
                    int v = topology.component_vertices[c].data[i];
                    if (degrees[v] < low)
                        low = degrees[v];
                    if (degrees[v] > high)
                        high = degrees[v];
                }
                line_push(&report, format("valence %d %d", low, high));
                free(degrees);
            }
        else if (!strcmp(section, "groups"))
            for (int g = 0; g < groups.count; ++g) {
                IntList group_faces = {0}, components = {0};
                int polygons = 0, triangles = 0, nonplanar_group = 0;
                for (int p = 0; p < object->polygon_count; ++p)
                    if (object->polygons[p].group == g) {
                        ++polygons;
                        triangles += object->polygons[p].vertices.count - 2;
                        nonplanar_group += nonplanar_polygons[p];
                    }
                for (int f = 0; f < clean->faces.count; ++f)
                    if (clean->faces.data[f].group == g) {
                        int_push(&group_faces, f);
                        int component = topology.face_component[f] + 1;
                        if (!int_contains(&components, component))
                            int_push(&components, component);
                    }
                int_sort(&components);
                line_push(&report, format("[group %s]", groups.data[g]));
                add_number(&report, "polygons", polygons);
                add_number(&report, "triangles", triangles);
                add_number(&report, "nonplanar", nonplanar_group);
                add_number(&report, "faces", group_faces.count);
                add_text(&report, "area", real(area(&group_faces, &clean->faces, clean->points)));
                add_text(&report, "components", list(&components, 0));
                int_free(&group_faces);
                int_free(&components);
            }
        else if (!strcmp(section, "contacts")) {
            line_push(&report, text("[contacts]"));
            for (int c = 0; c < topology.component_count; ++c)
                for (int d = c + 1; d < topology.component_count; ++d) {
                    bool intersects = true;
                    for (int axis = 0; axis < 3; ++axis)
                        if (props[c].minimum.v[axis] > props[d].maximum.v[axis] ||
                            props[d].minimum.v[axis] > props[c].maximum.v[axis])
                            intersects = false;
                    if (!intersects)
                        continue;
                    int shared = 0;
                    Integer gap = -1;
                    for (int i = 0; i < topology.component_vertices[c].count; ++i) {
                        int u = topology.component_vertices[c].data[i];
                        if (int_contains(&topology.component_vertices[d], u))
                            ++shared;
                        for (int j = 0; j < topology.component_vertices[d].count; ++j) {
                            int v = topology.component_vertices[d].data[j];
                            if (u == v)
                                continue;
                            Point delta = difference(clean->points[u], clean->points[v]);
                            Integer distance = dot(delta, delta);
                            if (gap < 0 || distance < gap)
                                gap = distance;
                        }
                    }
                    line_push(&report, format("contact %d %d shared %d gap2 %lld", c + 1, d + 1, shared,
                                              (long long)gap));
                }
        } else if (!strcmp(section, "edges")) {
            line_push(&report, text("[edges]"));
            int kinds[3] = {0}, shapes[4] = {0}, max_faces = 0, shortest = 0, longest = 0;
            for (int e = 0; e < topology.edge_count; ++e) {
                const Edge *edge = &topology.edges[e];
                ++kinds[edge->faces.count == 1 ? 0 : edge->faces.count == 2 ? 1 : 2];
                const char *shape = edge_shape(edge, &clean->faces, clean->points);
                const char *names[] = {"convex", "concave", "flat", "inconsistent"};
                for (int i = 0; i < 4; ++i)
                    if (!strcmp(shape, names[i]))
                        ++shapes[i];
                if (edge->faces.count > max_faces)
                    max_faces = edge->faces.count;
                if (length2(edge, clean->points) < length2(&topology.edges[shortest], clean->points))
                    shortest = e;
                if (length2(edge, clean->points) > length2(&topology.edges[longest], clean->points))
                    longest = e;
            }
            add_number(&report, "edges", topology.edge_count);
            add_number(&report, "boundary", kinds[0]);
            add_number(&report, "manifold", kinds[1]);
            add_number(&report, "nonmanifold", kinds[2]);
            add_number(&report, "max_faces", max_faces);
            add_number(&report, "convex", shapes[0]);
            add_number(&report, "concave", shapes[1]);
            add_number(&report, "flat", shapes[2]);
            add_number(&report, "inconsistent", shapes[3]);
            const Edge *small = &topology.edges[shortest], *large = &topology.edges[longest];
            line_push(&report, format("shortest %d %d len2 %lld", small->a, small->b,
                                      (long long)length2(small, clean->points)));
            line_push(&report, format("longest %d %d len2 %lld", large->a, large->b,
                                      (long long)length2(large, clean->points)));
        } else if (!strcmp(section, "valence")) {
            line_push(&report, text("[valence]"));
            int used = 0, low = topology.edge_count, high = 0;
            Integer sum = 0;
            int *degrees = calloc((size_t)topology.edge_count + 1, sizeof(int));
            for (int v = 1; v <= clean->point_count; ++v) {
                int degree = topology.vertex_edges[v].count;
                if (!degree)
                    continue;
                ++used;
                sum += degree;
                ++degrees[degree];
                if (degree < low)
                    low = degree;
                if (degree > high)
                    high = degree;
            }
            add_number(&report, "used", used);
            add_number(&report, "isolated", clean->point_count - used);
            add_number(&report, "min", low);
            add_number(&report, "max", high);
            add_text(&report, "mean", fraction(sum, used));
            for (int degree = 0; degree <= topology.edge_count; ++degree)
                if (degrees[degree])
                    line_push(&report, format("degree %d %d", degree, degrees[degree]));
            free(degrees);
        } else if (!strcmp(section, "queries")) {
            line_push(&report, text("[queries]"));
            for (int q = 0; q < options.query_count; ++q)
                line_push(&report, query_answer(&options.queries[q], &clean->faces, clean->points,
                                                clean->point_count, &topology, props, &groups));
        }
    }
    write_lines("report.txt", &report);
    Lines csv = {0};
    line_push(&csv, text("component,faces,vertices,closed,euler,genus,volume6,area"));
    for (int c = 0; c < topology.component_count; ++c) {
        const Properties *prop = &props[c];
        line_push(&csv, format("%d,%d,%d,%s,%d,%s,%s,%s", c + 1, topology.component_faces[c].count,
                               topology.component_vertices[c].count, yes(prop->closed), prop->euler,
                               prop->manifold && prop->orientable ? format("%d", prop->genus) : "-",
                               prop->solid ? format("%lld", (long long)prop->volume6) : "-",
                               real(area(&topology.component_faces[c], &clean->faces, clean->points))));
    }
    write_lines("components.csv", &csv);
    write_object(clean, &groups);
    for (int c = 0; c < topology.component_count; ++c)
        int_free(&props[c].inside);
    free(props);
    topology_free(&topology);
    topology_free(&before);
    loops_free(&loops);
    int_free(&all_faces);
    free(nonplanar_polygons);
    free(initial.data);
    free(clean->faces.data);
    free(clean);
    for (int p = 0; p < object->polygon_count; ++p)
        int_free(&object->polygons[p].vertices);
    for (int e = 0; e < object->error_count; ++e)
        free(object->errors[e].kind);
    free_lines(&object->groups);
    free(object);
    free_lines(&groups);
    free_lines(&options.sections);
    for (int q = 0; q < options.query_count; ++q)
        free_lines(&options.queries[q]);
    free_lines(&report);
    free_lines(&csv);
    return 0;
}
