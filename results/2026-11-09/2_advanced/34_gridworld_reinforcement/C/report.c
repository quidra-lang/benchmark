#include "reinforcement.h"
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
char *number(Integer value) {
    return format("%" PRId64, value);
}
char *fixed(Integer value) {
    Integer magnitude = absolute(value);
    return format("%s%" PRId64 ".%04" PRId64, value < 0 ? "-" : "", magnitude / 10000, magnitude % 10000);
}
char *average(Integer total, Integer count) {
    return fixed(floor_div(10000 * total, count));
}
char *cell_text(const World *w, int cell) {
    return format("%d,%d", cell / w->cols, cell % w->cols);
}
char *cells_text(const World *w, const int *cells, int count) {
    Text text = {0};
    for (int i = 0; i < count; ++i)
        text_add(&text, "%s%s", i ? " " : "", cell_text(w, cells[i]));
    return text.data;
}
Lines grid(const World *w, char **fields, const char *separator) {
    Lines out = {0};
    for (int r = 0; r < w->rows; ++r) {
        Text row = {0};
        for (int c = 0; c < w->cols; ++c) {
            int cell = r * w->cols + c, s = w->index[cell];
            text_add(&row, "%s%s", c ? separator : "", s < 0 ? format("%c", w->cells[cell]) : fields[s]);
        }
        line_add(&out, "%s", row.data);
    }
    return out;
}
Lines value_grid(const World *w, const Integer *values) {
    char **fields = allocate(w->n, sizeof *fields);
    for (int s = 0; s < w->n; ++s)
        fields[s] = fixed(values[s]);
    return grid(w, fields, " ");
}
Lines policy_grid(const World *w, const int *policy) {
    char **fields = allocate(w->n, sizeof *fields);
    for (int s = 0; s < w->n; ++s)
        fields[s] = format("%c", "^>v<"[policy[s]]);
    return grid(w, fields, "");
}
Lines q_rows(const World *w, const char *name, Table q, Table visits) {
    Lines out = {0};
    for (int s = 0; s < w->n; ++s)
        for (int a = 0; a < 4; ++a)
            line_add(&out, "%s,%s,%c,%s,%s", name, cell_text(w, w->states[s]), "NESW"[a], fixed(q[s][a]),
                     visits ? number(visits[s][a]) : "-");
    return out;
}
Lines parts(Lines *parts_, int count) {
    Lines out = {0};
    for (int i = 0; i < count; ++i) {
        if (i)
            line_add(&out, "");
        extend(&out, parts_[i]);
    }
    return out;
}
void write_lines(const char *name, Lines lines) {
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file)
        exit(EXIT_FAILURE);
    for (size_t i = 0; i < lines.len; ++i)
        fprintf(file, "%s\n", lines.data[i]);
    fclose(file);
}
