#include "spatial.h"
const char *fraction(Integer numerator, Integer denominator) {
    static char buffers[32][96];
    static unsigned next;
    char *out = buffers[next++ % 32];
    Integer a = numerator, b = denominator;
    while (b) {
        const Integer remainder = a % b;
        a = b;
        b = remainder;
    }
    snprintf(out, 96, "%lld/%lld", (long long)(numerator / a), (long long)(denominator / a));
    return out;
}
const char *ids(const int *values, int n) {
    static char *buffers[16];
    static unsigned next;
    if (!n)
        return "-";
    char **out = &buffers[next++ % 16];
    *out = realloc(*out, (size_t)n * 7 + 1);
    size_t length = 0;
    for (int i = 0; i < n; ++i)
        length += (size_t)sprintf(*out + length, "%s%d", i ? " " : "", values[i]);
    return *out;
}
static void append_format(Text *out, const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    const int needed = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    const size_t size = out->size + (size_t)needed + 1;
    if (size > out->capacity) {
        out->capacity = size * 2;
        out->data = realloc(out->data, out->capacity);
    }
    vsnprintf(out->data + out->size, out->capacity - out->size, format, args);
    out->size += (size_t)needed;
}
void add(Text *out, const char *format, ...) {
    va_list args;
    va_start(args, format);
    append_format(out, format, args);
    va_end(args);
}
void line(Text *out, const char *format, ...) {
    va_list args;
    va_start(args, format);
    append_format(out, format, args);
    va_end(args);
    add(out, "\n");
}
void write_report(const char *name, Text text) {
    Text path = {0};
    add(&path, "output/%s", name);
    FILE *out = fopen(path.data, "wb");
    size_t start = 0;
    for (size_t i = 0; i < text.size; ++i)
        if (text.data[i] == '\n') {
            fwrite(text.data + start, 1, i - start + 1, out);
            start = i + 1;
        }
    fclose(out);
    free(path.data);
}
