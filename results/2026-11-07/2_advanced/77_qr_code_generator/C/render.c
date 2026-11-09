#include "qr.h"
Names symbol_lines(const Matrix *symbol) {
    Names out = {0};
    for (int y = 0; y < symbol->size; ++y) {
        char *row = allocate((size_t)symbol->size + 1);
        for (int x = 0; x < symbol->size; ++x)
            row[x] = symbol->cells[y][x] ? '#' : '.';
        Names_add(&out, row);
    }
    return out;
}
char *pbm_text(const Matrix *symbol, int quiet, int scale) {
    int width = (symbol->size + 2 * quiet) * scale;
    Names lines = {0};
    Names_add(&lines, "P1");
    Names_add(&lines, format("%d %d", width, width));
    for (int py = 0; py < width; ++py) {
        char *row = allocate((size_t)width + 1);
        for (int px = 0; px < width; ++px) {
            int x = px / scale - quiet, y = py / scale - quiet;
            row[px] = (char)('0' + (x >= 0 && x < symbol->size && y >= 0 && y < symbol->size
                                        ? symbol->cells[y][x]
                                        : 0));
        }
        Names_add(&lines, row);
    }
    return format("%s\n", join(lines, "\n"));
}
