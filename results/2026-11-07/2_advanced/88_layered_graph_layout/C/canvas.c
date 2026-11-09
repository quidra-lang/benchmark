#include "layout.h"
Canvas canvas_create(int main_length, int secondary_length, Direction direction) {
    Canvas out = {main_length,
                  secondary_length,
                  vertical(direction) ? main_length : secondary_length,
                  vertical(direction) ? secondary_length : main_length,
                  direction,
                  NULL};
    out.cells = allocate((size_t)out.rows * (size_t)out.columns * sizeof *out.cells);
    return out;
}
Cell canvas_map(const Canvas *canvas, int main, int secondary) {
    if (canvas->direction == DIR_BT || canvas->direction == DIR_RL)
        main = canvas->main_length - 1 - main;
    return vertical(canvas->direction) ? (Cell){main, secondary} : (Cell){secondary, main};
}
Pixel *canvas_at(Canvas *canvas, Cell cell) {
    return &canvas->cells[(size_t)cell.row * (size_t)canvas->columns + (size_t)cell.column];
}
static const Pixel *canvas_get(const Canvas *canvas, Cell cell) {
    return &canvas->cells[(size_t)cell.row * (size_t)canvas->columns + (size_t)cell.column];
}
void canvas_line(Canvas *canvas, int main, int secondary, unsigned char kind) {
    canvas_at(canvas, canvas_map(canvas, main, secondary))->lines |= kind;
}
void canvas_main_line(Canvas *canvas, int main, int secondary) {
    canvas_line(canvas, main, secondary, vertical(canvas->direction) ? 1 : 2);
}
static void secondary_line(Canvas *canvas, int main, int secondary) {
    canvas_line(canvas, main, secondary, vertical(canvas->direction) ? 2 : 1);
}
void canvas_segment(Canvas *canvas, int start, int gap, int upper, int lower, int offset) {
    if (upper == lower) {
        for (int i = 0; i < gap; ++i)
            canvas_main_line(canvas, start + i, upper);
        return;
    }
    for (int i = 0; i < offset; ++i)
        canvas_main_line(canvas, start + i, upper);
    canvas_line(canvas, start + offset, upper, 4);
    canvas_line(canvas, start + offset, lower, 4);
    int low = upper < lower ? upper : lower, high = upper > lower ? upper : lower;
    for (int x = low + 1; x < high; ++x)
        secondary_line(canvas, start + offset, x);
    for (int i = offset + 1; i < gap; ++i)
        canvas_main_line(canvas, start + i, lower);
}
void canvas_highlight(Canvas *canvas, Cell from, Cell to) {
    int dr = (from.row < to.row) - (from.row > to.row),
        dc = (from.column < to.column) - (from.column > to.column);
    for (;;) {
        canvas_at(canvas, from)->highlighted = true;
        if (from.row == to.row && from.column == to.column)
            return;
        from.row += dr;
        from.column += dc;
    }
}
int canvas_crossing_cells(const Canvas *canvas) {
    int out = 0;
    for (int i = 0; i < canvas->rows * canvas->columns; ++i)
        if ((canvas->cells[i].lines & 3) == 3)
            ++out;
    return out;
}
static char character(const Canvas *canvas, Cell cell) {
    const Pixel *pixel = canvas_get(canvas, cell);
    if (pixel->box)
        return pixel->box;
    if (pixel->arrow)
        return pixel->arrow;
    if (pixel->highlighted)
        return '#';
    if (!pixel->lines)
        return ' ';
    if (pixel->lines == 1)
        return '|';
    if (pixel->lines == 2)
        return '-';
    return '+';
}
TextLines canvas_drawing(const Canvas *canvas, const char *name) {
    TextLines out = {0};
    lines_push(&out, format_text("graph %s %dx%d", name, canvas->columns, canvas->rows));
    char *ruler = allocate((size_t)canvas->columns + 5);
    memcpy(ruler, "    ", 4);
    for (int c = 0; c < canvas->columns; ++c)
        ruler[c + 4] = (char)('0' + c % 10);
    ruler[canvas->columns + 4] = 0;
    lines_push(&out, ruler);
    for (int r = 0; r < canvas->rows; ++r) {
        char *line = allocate((size_t)canvas->columns + 5);
        snprintf(line, 5, "%3d ", r);
        for (int c = 0; c < canvas->columns; ++c)
            line[c + 4] = character(canvas, (Cell){r, c});
        int length = canvas->columns + 4;
        while (length && line[length - 1] == ' ')
            --length;
        line[length] = 0;
        lines_push(&out, line);
    }
    return out;
}
