#include "clustering.h"
void push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 16;
        list->values = realloc(list->values, (size_t)list->capacity * sizeof *list->values);
    }
    list->values[list->count++] = value;
}
static char *vformat(const char *pattern, va_list args) {
    va_list measure;
    va_copy(measure, args);
    int length = vsnprintf(NULL, 0, pattern, measure);
    va_end(measure);
    char *text = malloc((size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    return text;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *text = vformat(pattern, args);
    va_end(args);
    return text;
}
void append_text(char **text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *part = vformat(pattern, args);
    va_end(args);
    size_t old = *text ? strlen(*text) : 0, length = strlen(part);
    *text = realloc(*text, old + length + 1);
    memcpy(*text + old, part, length + 1);
    free(part);
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *text = vformat(pattern, args);
    va_end(args);
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 16;
        lines->values = realloc(lines->values, (size_t)lines->capacity * sizeof *lines->values);
    }
    lines->values[lines->count++] = text;
}
char *read_line(FILE *file) {
    size_t count = 0, capacity = 128;
    char *text = malloc(capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            text = realloc(text, capacity);
        }
        text[count++] = (char)c;
    }
    if (c == EOF && !count) {
        free(text);
        return NULL;
    }
    text[count] = 0;
    return text;
}
void write_lines(FILE *file, const Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->values[i]);
}
void framed(FILE *out, char **rows, int width, int height) {
    fputc('+', out);
    for (int c = 0; c < width; ++c)
        fputc('-', out);
    fputs("+\n", out);
    for (int r = 0; r < height; ++r)
        fprintf(out, "|%.*s|\n", width, rows[r]);
    fputc('+', out);
    for (int c = 0; c < width; ++c)
        fputc('-', out);
    fputs("+\n", out);
}
static Integer gcd(Integer a, Integer b) {
    while (b) {
        Integer next = a % b;
        a = b;
        b = next;
    }
    return a;
}
char *fraction(Integer numerator, Integer denominator) {
    Integer divisor = gcd(numerator < 0 ? -numerator : numerator, denominator);
    return format("%" PRId64 "/%" PRId64, numerator / divisor, denominator / divisor);
}
char *root(Integer value) {
    return value == DISTANCE_INF ? "-" : format("%.3f", sqrt((double)value));
}
char *ari_value(Integer numerator, Integer denominator) {
    char *text = format("%.4f", (double)numerator / (double)denominator);
    if (!strcmp(text, "-0.0000"))
        memmove(text, text + 1, strlen(text));
    return text;
}
