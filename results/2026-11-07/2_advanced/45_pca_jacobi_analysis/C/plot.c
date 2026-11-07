#include "analysis.h"
Grid grid(int height, int width) {
    Grid out = {.height = height, .width = width};
    for (int r = 0; r < height; ++r)
        memset(out.cells[r], ' ', (size_t)width);
    return out;
}
void framed(FILE *out, const Grid *grid) {
    fputc('+', out);
    for (int c = 0; c < grid->width; ++c)
        fputc('-', out);
    fputs("+\n", out);
    for (int r = 0; r < grid->height; ++r) {
        fputc('|', out);
        fwrite(grid->cells[r], 1, (size_t)grid->width, out);
        fputs("|\n", out);
    }
    fputc('+', out);
    for (int c = 0; c < grid->width; ++c)
        fputc('-', out);
    fputs("+\n", out);
}
static int index_at(double fraction, int size) {
    const int index = (int)floor(fraction * size);
    return index < size ? index : size - 1;
}
Cell biplot_cell(double x, double y, double xlimit, double ylimit, int width, int height) {
    return (Cell){index_at((ylimit - y) / (2 * ylimit), height),
                  index_at((x + xlimit) / (2 * xlimit), width)};
}
Cell circle_cell(double x, double y, int radius) {
    return (Cell){radius / 2 + 1 - (int)floor(y * (radius / 2) + 0.5),
                  radius + 1 + (int)floor(x * radius + 0.5)};
}
Cell diagnostic_cell(double t2, double spe, double xlimit, double ylimit, int width, int height) {
    return (Cell){height - 1 - index_at(spe / ylimit, height), index_at(t2 / xlimit, width)};
}
static int sign(int value) {
    return (value > 0) - (value < 0);
}
char shaft_character(Cell origin, Cell tip) {
    const int dr = tip.row - origin.row, dc = tip.column - origin.column;
    return 2 * abs(dr) <= abs(dc) ? '-' : 2 * abs(dc) <= abs(dr) ? '|' : dc * dr < 0 ? '/' : '\\';
}
void shaft_cells(Grid *grid, Cell origin, Cell tip) {
    const int dr = tip.row - origin.row, dc = tip.column - origin.column,
              steps = abs(dr) > abs(dc) ? abs(dr) : abs(dc);
    for (int s = 1; s < steps; ++s) {
        const int r = origin.row + sign(dr) * ((2 * s * abs(dr) + steps) / (2 * steps)),
                  c = origin.column + sign(dc) * ((2 * s * abs(dc) + steps) / (2 * steps));
        grid->cells[r][c] = shaft_character(origin, tip);
    }
}
void scree_line(FILE *out, int length, int kaiser, int broken, int width) {
    fputc('|', out);
    for (int p = 1; p <= width; ++p)
        fputc(p == broken ? 'o' : p == kaiser ? ':' : p <= length ? '#' : ' ', out);
    fputc('|', out);
}
