#include "mixture.h"
I rounded(double value, int digits) {
    I factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    I amount = (I)floor(fabs(value) * (double)factor + 0.5);
    return value < 0 ? -amount : amount;
}
char *real(double value, int digits) {
    I amount = rounded(value, digits), absolute = amount < 0 ? -amount : amount, factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    return format("%s%" PRId64 ".%0*" PRId64, amount < 0 ? "-" : "", absolute / factor, digits,
                  absolute % factor);
}
void line(Lines *lines, const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *text = allocate((size_t)length + 1, 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    va_end(args);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? lines->capacity * 2 : 32;
        char **values = allocate(capacity, sizeof(char *));
        if (lines->count)
            memcpy(values, lines->data, lines->count * sizeof(char *));
        lines->data = values;
        lines->capacity = capacity;
    }
    lines->data[lines->count++] = text;
}
void frame(Lines *lines, char **grid, int height, int width) {
    char *border = allocate(width + 1, 1);
    memset(border, '-', width);
    line(lines, "+%s+", border);
    for (int y = 0; y < height; ++y)
        line(lines, "|%s|", grid[y]);
    line(lines, "+%s+", border);
}
void save(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "w");
    for (int i = 0; i < lines.count; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
