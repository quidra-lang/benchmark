#include "airspace.h"
const char *decimal(double value, int digits) {
    static char buffers[64][128];
    static unsigned index;
    char *out = buffers[index++ % 64];
    double factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    double rounded = floor(fabs(value) * factor + 0.5),
           result = (value < 0 ? -rounded : rounded) / factor;
    if (rounded == 0)
        result = 0;
    snprintf(out, 128, "%.*f", digits, result);
    return out;
}
const char *signed_integer(Integer value) {
    static char buffers[16][32];
    static unsigned index;
    char *out = buffers[index++ % 16];
    snprintf(out, 32, value > 0 ? "+%lld" : "%lld", (long long)value);
    return out;
}
char *joined(const Names *names) {
    size_t length = 1;
    for (size_t i = 0; i < names->count; ++i)
        length += strlen(names->items[i].text) + (i != 0);
    char *out = malloc(length);
    size_t p = 0;
    for (size_t i = 0; i < names->count; ++i) {
        if (i)
            out[p++] = ',';
        size_t n = strlen(names->items[i].text);
        memcpy(out + p, names->items[i].text, n);
        p += n;
    }
    out[p] = 0;
    return out;
}
FILE *open_output(const char *name) {
    char path[128];
    snprintf(path, sizeof path, "output/%s", name);
    return fopen(path, "w");
}
void frame(FILE *file, char *const *grid, size_t width, size_t height) {
    for (int pass = 0; pass < 2; ++pass) {
        fputc('+', file);
        for (size_t i = 0; i < width; ++i)
            fputc('-', file);
        fputs("+\n", file);
        if (pass == 0)
            for (size_t row = 0; row < height; ++row) {
                fputc('|', file);
                fwrite(grid[row], 1, width, file);
                fputs("|\n", file);
            }
    }
}
