#include "sat.h"
#include <stdarg.h>
void *resize(void *memory, size_t size) {
    void *result = realloc(memory, size ? size : 1);
    if (!result)
        exit(1);
    return result;
}
char *text(const char *value) {
    char *result = resize(NULL, strlen(value) + 1);
    strcpy(result, value);
    return result;
}
char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = resize(NULL, (size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof(int));
    }
    list->data[list->count++] = value;
}
bool int_contains(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->data[i] == value)
            return true;
    return false;
}
Clause int_copy(const IntList *list) {
    Clause out = {0};
    for (int i = 0; i < list->count; ++i)
        int_push(&out, list->data[i]);
    return out;
}
void int_free(IntList *list) {
    free(list->data);
    *list = (IntList){0};
}
void line_push(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 8;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof(char *));
    }
    lines->data[lines->count++] = line;
}
void append_lines(Lines *target, const Lines *source) {
    for (int i = 0; i < source->count; ++i)
        line_push(target, text(source->data[i]));
}
void free_lines(Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (Lines){0};
}
void formula_push(Formula *formula, Clause clause) {
    if (formula->count == formula->capacity) {
        formula->capacity = formula->capacity ? formula->capacity * 2 : 16;
        formula->clauses = resize(formula->clauses, (size_t)formula->capacity * sizeof(Clause));
    }
    formula->clauses[formula->count++] = clause;
}
Formula formula_copy(const Formula *formula) {
    Formula out = {.variables = formula->variables};
    for (int i = 0; i < formula->count; ++i)
        formula_push(&out, int_copy(&formula->clauses[i]));
    return out;
}
void formula_free(Formula *formula) {
    for (int i = 0; i < formula->count; ++i)
        int_free(&formula->clauses[i]);
    free(formula->clauses);
    *formula = (Formula){0};
}
static void concatenate(char **target, const char *value) {
    size_t old = strlen(*target), added = strlen(value);
    *target = resize(*target, old + added + 1);
    memcpy(*target + old, value, added + 1);
}
char *number_list(const IntList *values) {
    if (!values->count)
        return text("-");
    char *out = text("");
    for (int i = 0; i < values->count; ++i) {
        char *part = format("%s%d", i ? "," : "", values->data[i]);
        concatenate(&out, part);
        free(part);
    }
    return out;
}
char *frequency_list(const int *counts, int length) {
    char *out = text("");
    for (int i = 0; i < length; ++i)
        if (counts[i]) {
            char *part = format("%s%d:%d", *out ? "," : "", i, counts[i]);
            concatenate(&out, part);
            free(part);
        }
    if (!*out) {
        free(out);
        return text("-");
    }
    return out;
}
char *items(const char *prefix, int count, ...) {
    char *out = text(prefix);
    va_list args;
    va_start(args, count);
    for (int i = 0; i < count; ++i) {
        const char *name = va_arg(args, const char *), *value = va_arg(args, const char *);
        if (*out)
            concatenate(&out, " ");
        concatenate(&out, name);
        concatenate(&out, "=");
        concatenate(&out, value);
    }
    va_end(args);
    return out;
}
Lines board_lines(const IntList *columns) {
    Lines lines = {0};
    for (int i = 0; i < columns->count; ++i) {
        char *row = resize(NULL, (size_t)columns->count + 1);
        memset(row, '.', (size_t)columns->count);
        row[columns->count] = 0;
        row[columns->data[i] - 1] = 'Q';
        line_push(&lines, row);
    }
    return lines;
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
void paragraph(Lines *file, const Lines *lines) {
    if (file->count)
        line_push(file, text(""));
    append_lines(file, lines);
}
