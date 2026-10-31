#include "heat.h"
int cell(const Mesh *mesh, int row, int column) { return row * mesh->width + column; }
Mesh read_mesh(void) {
    Mesh out = {0};
    FILE *input = fopen("input/plate.txt", "r");
    fscanf(input, "%d %d %lf %lf", &out.width, &out.height, &out.dx, &out.thickness);
    out.count = out.width * out.height;
    char row[41];
    for (int r = 0; r < out.height; ++r) {
        fscanf(input, "%40s", row);
        memcpy(out.codes + r * out.width, row, (size_t)out.width);
        for (int c = 0; c < out.width; ++c) {
            int p = cell(&out, r, c);
            out.neighbors[p][0] = c > 0 ? p - 1 : -1;
            out.neighbors[p][1] = c + 1 < out.width ? p + 1 : -1;
            out.neighbors[p][2] = r > 0 ? p - out.width : -1;
            out.neighbors[p][3] = r + 1 < out.height ? p + out.width : -1;
        }
    }
    fclose(input);
    return out;
}
char *coordinates(const Mesh *mesh, int point) {
    return format("%d %d", point / mesh->width, point % mesh->width);
}
void segment_faces(const Mesh *mesh, Segment *segment, int start, int end) {
    int direction = strcmp(segment->edge, "left") == 0    ? 0
                    : strcmp(segment->edge, "right") == 0 ? 1
                    : strcmp(segment->edge, "top") == 0   ? 2
                                                          : 3;
    for (int i = start; i <= end; ++i) {
        int point = direction == 0   ? cell(mesh, i, 0)
                    : direction == 1 ? cell(mesh, i, mesh->width - 1)
                    : direction == 2 ? cell(mesh, 0, i)
                                     : cell(mesh, mesh->height - 1, i);
        segment->faces[segment->count++] = (CellFace){point, direction};
    }
}
void source_cells(const Mesh *mesh, Source *source, int r1, int c1, int r2, int c2) {
    for (int r = r1; r <= r2; ++r)
        for (int c = c1; c <= c2; ++c)
            source->cells[source->count++] = cell(mesh, r, c);
}
