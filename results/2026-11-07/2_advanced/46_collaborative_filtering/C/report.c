#include "recommender.h"
const char *real(double value) {
    static char buffers[64][96];
    static unsigned next;
    char *out = buffers[next++ % 64];
    if (fabs(value) < 0.00005)
        value = 0;
    snprintf(out, 96, "%.4f", value);
    return out;
}
static void append_format(Text *out, const char *format, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    const int needed = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    const size_t size = out->size + (size_t)needed + 1;
    if (size > out->capacity) {
        out->capacity = size * 2;
        out->data = realloc(out->data, out->capacity);
    }
    vsnprintf(out->data + out->size, out->capacity - out->size, format, arguments);
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
