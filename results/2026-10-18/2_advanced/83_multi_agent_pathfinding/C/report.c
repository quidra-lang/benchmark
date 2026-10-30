#include "mapf.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
void *resize(void *pointer, size_t size) {
    void *result = realloc(pointer, size ? size : 1);
    if (!result) {
        fputs("allocation failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    return result;
}
void *allocate(size_t size) { return resize(NULL, size); }
char *copy_text(const char *text) {
    char *result = allocate(strlen(text) + 1);
    strcpy(result, text);
    return result;
}
char *format_text(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, format, args);
    va_end(args);
    return result;
}
void text_add(Text *text, const char *part) {
    size_t length = strlen(part), needed = text->count + length + 1;
    if (needed > text->capacity) {
        size_t capacity = text->capacity ? text->capacity : 128;
        while (capacity < needed)
            capacity *= 2;
        text->data = resize(text->data, capacity);
        text->capacity = capacity;
    }
    memcpy(text->data + text->count, part, length + 1);
    text->count += length;
}
void text_format(Text *text, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *part = allocate((size_t)length + 1);
    vsnprintf(part, (size_t)length + 1, format, args);
    va_end(args);
    text_add(text, part);
    free(part);
}
char *text_take(Text *text) {
    char *result = text->data ? text->data : copy_text("");
    *text = (Text){0};
    return result;
}
void lines_add(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 64;
        lines->items = resize(lines->items, lines->capacity * sizeof(char *));
    }
    lines->items[lines->count++] = line;
}
void lines_copy(Lines *out, const Lines *in) {
    for (size_t i = 0; i < in->count; ++i)
        lines_add(out, copy_text(in->items[i]));
}
void lines_free(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
}
Words split_words(char *line) {
    Words result = {0};
    char *part = line;
    for (;;) {
        result.items = resize(result.items, (result.count + 1) * sizeof(char *));
        result.items[result.count++] = part;
        char *space = strchr(part, ' ');
        if (!space)
            break;
        *space = 0;
        part = space + 1;
    }
    return result;
}
FILE *open_file(const char *path, const char *mode) {
    FILE *file = fopen(path, mode);
    if (!file) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    return file;
}
char *read_line(FILE *file) {
    size_t count = 0, capacity = 128;
    char *line = allocate(capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            line = resize(line, capacity);
        }
        line[count++] = (char)c;
    }
    if (!count && c == EOF) {
        free(line);
        return NULL;
    }
    line[count] = 0;
    return line;
}
char *cell_text(const Grid *g, int cell) {
    return format_text("%d,%d", cell % g->width, cell / g->width);
}
char *conflict_text(const Grid *g, Conflict c) {
    char *u = cell_text(g, c.u), *v = cell_text(g, c.v),
         *result = c.edge ? format_text("edge t %d %c %c from %s to %s", c.time, 'A' + c.a,
                                        'A' + c.b, u, v)
                          : format_text("vertex t %d %c %c at %s", c.time, 'A' + c.a, 'A' + c.b, v);
    free(u);
    free(v);
    return result;
}
char action(const Grid *g, int u, int v) {
    if (u == v)
        return '.';
    if (v == u - g->width)
        return 'N';
    if (v == u + 1)
        return 'E';
    if (v == u + g->width)
        return 'S';
    return 'W';
}
char *actions(const Grid *g, const Path *path) {
    char *result = allocate((size_t)path->count);
    for (int i = 1; i < path->count; ++i)
        result[i - 1] = action(g, path->cells[i - 1], path->cells[i]);
    result[path->count - 1] = 0;
    return result;
}
char *fraction(int a, int b) {
    int x = a, y = b;
    while (y) {
        int remainder = x % y;
        x = y;
        y = remainder;
    }
    return format_text("%d/%d", a / x, b / x);
}
char *integers(const int *values, int count) {
    Text text = {0};
    for (int i = 0; i < count; ++i)
        text_format(&text, "%s%d", i ? " " : "", values[i]);
    return text_take(&text);
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format_text("output/%s", name);
    FILE *file = open_file(path, "w");
    free(path);
    for (size_t i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->items[i]);
    fclose(file);
}
const char *solver_name(Solver solver) {
    static const char *names[] = {"PP", "CBS", "ICBS", "WHCA"};
    return names[solver];
}
const char *cost_function(bool makespan) { return makespan ? "MAKESPAN" : "SOC"; }
