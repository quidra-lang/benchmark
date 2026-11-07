#include "analyzer.h"
char *real(double value) {
    Int amount = (Int)floor(fabs(value) * 10000 + 0.5);
    return format("%s%" PRId64 ".%04" PRId64, value < 0 && amount ? "-" : "", amount / 10000, amount % 10000);
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
char *shade_line(double frequency, Frames magnitudes, int bin, double maximum, int band) {
    const char *characters = " .:-=+*#%@";
    char *prefix = format("%9s |", real(frequency));
    size_t offset = strlen(prefix);
    char *out = allocate(offset + (size_t)magnitudes.count + 2, 1);
    memcpy(out, prefix, offset);
    for (int t = 0; t < magnitudes.count; ++t) {
        double db = 20 * log10(magnitudes.magnitudes[t].data[bin] / maximum);
        int level = 9 - (int)floor(-db / band);
        if (level < 0)
            level = 0;
        out[offset++] = characters[level];
    }
    out[offset] = '|';
    return out;
}
void save(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "w");
    for (int i = 0; i < lines.count; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
