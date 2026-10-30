#include "geometry.h"
#include <stdlib.h>
Rendered render(const Result *target, int x0, int y0, int cw, int ch, int cols, int rows) {
    Rendered result = {0};
    Rings rings = flatten(&target->polygons);
    for (int j = 0; j < rows; ++j) {
        char *row = allocate((size_t)cols + 1);
        for (int i = 0; i < cols; ++i) {
            Point p = point(2 * x0 + (2 * i + 1) * cw, 2 * y0 + (2 * (rows - 1 - j) + 1) * ch, 2);
            char character = '.';
            if (interior(p, &rings)) {
                character = '#';
                ++result.result;
            } else if (target->a && target->b) {
                bool a = interior(p, &target->a->rings), b = interior(p, &target->b->rings);
                if (a && b) {
                    character = '+';
                    ++result.both;
                } else if (a) {
                    character = 'a';
                    ++result.a;
                } else if (b) {
                    character = 'b';
                    ++result.b;
                }
            }
            row[i] = character;
        }
        row[cols] = 0;
        lines_add(&result.rows, row);
    }
    rings_free(&rings);
    return result;
}
