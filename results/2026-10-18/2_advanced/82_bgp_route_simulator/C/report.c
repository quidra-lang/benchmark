#include "bgp.h"
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
void lines_free(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
}
Words words(char *line) {
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
void words_free(Words *words) { free(words->items); }
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
char *path_text(const int *path, size_t count) {
    Text text = {0};
    for (size_t i = 0; i < count; ++i)
        text_format(&text, "%s%d", i ? "," : "", path[i]);
    return text_take(&text);
}
char *attribute_text(const Attribute *a) {
    char *path = path_text(a->path, a->path_count), *comm = communities_text(&a->communities),
         *result = format_text("path %s origin %s med %d comm %s", path, origin_name(a->origin),
                               a->med, comm);
    free(path);
    free(comm);
    return result;
}
char *route_text(Route route) {
    if (!route.attribute)
        return copy_text("NONE");
    const Attribute *a = route.attribute;
    char *comm = communities_text(&a->communities), *result;
    if (route.local)
        result = format_text("LOCAL origin %s comm %s", origin_name(a->origin), comm);
    else {
        char *path = path_text(a->path, a->path_count);
        result =
            format_text("next %d path %s link %s lp %d med %d origin %s comm %s", a->path[0], path,
                        route.link->name, route.preference, a->med, origin_name(a->origin), comm);
        free(path);
    }
    free(comm);
    return result;
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format_text("output/%s", name);
    FILE *file = open_file(path, "w");
    free(path);
    for (size_t i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->items[i]);
    fclose(file);
}
