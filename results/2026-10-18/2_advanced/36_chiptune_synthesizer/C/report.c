#include "synthesizer.h"
void *allocate(size_t count, size_t size) {
    void *value = calloc(count ? count : 1, size);
    if (!value)
        exit(EXIT_FAILURE);
    return value;
}
void grow(void **data, size_t *cap, size_t need, size_t size) {
    if (need <= *cap)
        return;
    size_t next = *cap ? *cap : 8;
    while (next < need)
        next *= 2;
    void *value = realloc(*data, next * size);
    if (!value)
        exit(EXIT_FAILURE);
    *data = value;
    *cap = next;
}
static char *vformat(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)count + 1, 1);
    vsnprintf(out, (size_t)count + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = vformat(pattern, args);
    va_end(args);
    return out;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    size_t length = strlen(value);
    grow((void **)&text->data, &text->cap, text->len + length + 1, 1);
    memcpy(text->data + text->len, value, length + 1);
    text->len += length;
    free(value);
}
void line_add(Lines *lines, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    grow((void **)&lines->data, &lines->cap, lines->len + 1, sizeof *lines->data);
    lines->data[lines->len++] = value;
}
void extend(Lines *out, Lines lines) {
    for (size_t i = 0; i < lines.len; ++i)
        line_add(out, "%s", lines.data[i]);
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(EXIT_FAILURE);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *data = allocate((size_t)length + 1, 1);
    size_t size = fread(data, 1, (size_t)length, file);
    fclose(file);
    Lines lines = {0};
    size_t first = 0;
    for (size_t i = 0; i < size; ++i)
        if (data[i] == '\n') {
            data[i] = 0;
            line_add(&lines, "%s", data + first);
            first = i + 1;
        }
    return lines;
}

Lines words(const char *text) {
    Lines out = {0};
    const char *cursor = text;
    while (*cursor) {
        while (*cursor == ' ')
            ++cursor;
        if (!*cursor)
            break;
        const char *end = cursor;
        while (*end && *end != ' ')
            ++end;
        line_add(&out, "%.*s", (int)(end - cursor), cursor);
        cursor = end;
    }
    return out;
}
void write_lines(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "wb");
    if (!out)
        exit(EXIT_FAILURE);
    for (size_t i = 0; i < lines.len; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
char *decimal(Integer value) {
    return format("%" PRId64, value);
}
char *hexadecimal(Integer value, int width) {
    return format("%0*" PRIX64, width, (uint64_t)value);
}
char *aligned(Integer value, int width) {
    return format("%*" PRId64, width, value);
}
Integer adler32(const int *samples, size_t count) {
    Integer a = 1, b = 0;
    for (size_t i = 0; i < count; ++i) {
        a = (a + samples[i]) % 65521;
        b = (b + a) % 65521;
    }
    return b * 65536 + a;
}
Integer integer_sqrt(Integer value) {
    Integer lo = 0, hi = value + 1;
    while (lo + 1 < hi) {
        Integer middle = (lo + hi) / 2;
        if (middle <= value / middle)
            lo = middle;
        else
            hi = middle;
    }
    return lo;
}
SampleStats sample_stats(const int *samples, size_t count) {
    SampleStats out = {0};
    out.minimum = out.maximum = samples[0];
    Integer squares = 0;
    for (size_t i = 0; i < count; ++i) {
        Integer centered = samples[i] - 128, absolute = centered < 0 ? -centered : centered;
        if (absolute > out.peak)
            out.peak = absolute;
        if (samples[i] < out.minimum)
            out.minimum = samples[i];
        if (samples[i] > out.maximum)
            out.maximum = samples[i];
        squares += centered * centered;
        if (i && ((samples[i - 1] < 128) != (samples[i] < 128)))
            ++out.crossings;
    }
    out.rms = integer_sqrt(squares / (Integer)count);
    return out;
}
Lines sample_dump(const int *samples, size_t count) {
    Lines out = {0};
    for (size_t start = 0; start < count; start += 32) {
        Text line = {0};
        size_t end = start + 32 < count ? start + 32 : count;
        for (size_t i = start; i < end; ++i)
            text_add(&line, "%02X", samples[i]);
        line_add(&out, "%s", line.data);
    }
    return out;
}
