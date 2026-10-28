#include "ecg.h"
#include <stdarg.h>
void *resize(void *memory, size_t size) {
    void *out = realloc(memory, size ? size : 1);
    if (!out)
        exit(1);
    return out;
}
char *text(const char *value) {
    char *out = resize(NULL, strlen(value) + 1);
    strcpy(out, value);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = resize(NULL, (size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    va_end(args);
    return out;
}
void value_push(Values *values, Integer value) {
    if (values->count == values->capacity) {
        values->capacity = values->capacity ? 2 * values->capacity : 16;
        values->data = resize(values->data, (size_t)values->capacity * sizeof(Integer));
    }
    values->data[values->count++] = value;
}
void line_push(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof(char *));
    }
    lines->data[lines->count++] = line;
}
void lines_extend(Lines *target, const Lines *source) {
    for (int i = 0; i < source->count; ++i)
        line_push(target, text(source->data[i]));
}
void lines_free(Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (Lines){0};
}
Input *read_input(void) {
    Input *out = calloc(1, sizeof(Input));
    char buffer[128];
    FILE *file = fopen("input/ecg.csv", "rb");
    fgets(buffer, sizeof buffer, file);
    while (fgets(buffer, sizeof buffer, file))
        out->ecg[out->count++] = strtoll(strchr(buffer, ',') + 1, NULL, 10);
    fclose(file);
    file = fopen("input/annotations.csv", "rb");
    fgets(buffer, sizeof buffer, file);
    while (fgets(buffer, sizeof buffer, file)) {
        char *comma = strchr(buffer, ',');
        out->annotations[out->annotation_count++] = (Annotation){atoi(buffer), comma[1], -1};
    }
    fclose(file);
    file = fopen("input/params.txt", "rb");
    Integer *fields[] = {
        &out->params.refractory_ms,     &out->params.twave_ms,     &out->params.searchback_percent,
        &out->params.premature_percent, &out->params.qrs_width_ms, &out->params.match_ms,
        &out->params.pause_ms,          &out->params.brady_ms,     &out->params.tachy_ms,
        &out->params.excerpt_ms,        &out->params.segment_ms,   &out->params.strip_start_ms,
        &out->params.strip_ms,          &out->params.strip_rows,   &out->params.chart_rows,
        &out->params.poincare_size};
    for (int i = 0; i < 16; ++i) {
        fgets(buffer, sizeof buffer, file);
        *fields[i] = strtoll(strchr(buffer, ' ') + 1, NULL, 10);
    }
    fclose(file);
    return out;
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    free(path);
    if (!file)
        return;
    for (int i = 0; i < lines->count; ++i) {
        fputs(lines->data[i], file);
        fputc('\n', file);
    }
    fclose(file);
}
