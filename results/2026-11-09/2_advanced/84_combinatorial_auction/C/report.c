#include "auction.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
static Money gcd(Money a, Money b) {
    if (a < 0)
        a = -a;
    while (b) {
        Money remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}
Fraction fraction(Money n, Money d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    Money divisor = gcd(n, d);
    return (Fraction){n / divisor, d / divisor};
}
Fraction whole(Money n) { return (Fraction){n, 1}; }
Fraction fraction_add(Fraction a, Fraction b) {
    Money common = gcd(a.d, b.d);
    return fraction(a.n * (b.d / common) + b.n * (a.d / common), a.d * (b.d / common));
}
Fraction fraction_sub(Fraction a, Fraction b) {
    b.n = -b.n;
    return fraction_add(a, b);
}
Fraction fraction_mul(Fraction a, Fraction b) {
    Money x = gcd(a.n, b.d), y = gcd(b.n, a.d);
    return fraction((a.n / x) * (b.n / y), (a.d / y) * (b.d / x));
}
Fraction fraction_div(Fraction a, Fraction b) { return fraction_mul(a, fraction(b.d, b.n)); }
int fraction_compare(Fraction a, Fraction b) {
    Money left = a.n * b.d, right = b.n * a.d;
    return (left > right) - (left < right);
}
char *fraction_text(Fraction value, char out[64]) {
    if (value.d == 1)
        snprintf(out, 64, "%lld", value.n);
    else
        snprintf(out, 64, "%lld/%lld", value.n, value.d);
    return out;
}
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
static char *format_arguments(const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, format, args);
    return result;
}
char *format_text(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *result = format_arguments(format, args);
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
    va_list args;
    va_start(args, format);
    char *part = format_arguments(format, args);
    va_end(args);
    text_add(text, part);
    free(part);
}
char *text_take(Text *text) {
    char *result = text->data ? text->data : copy_text("");
    *text = (Text){0};
    return result;
}
void lines_add(Lines *lines, char *value) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 64;
        lines->items = resize(lines->items, lines->capacity * sizeof(char *));
    }
    lines->items[lines->count++] = value;
}
void line(Lines *lines, const char *format, ...) {
    va_list args;
    va_start(args, format);
    lines_add(lines, format_arguments(format, args));
    va_end(args);
}
void lines_take(Lines *out, Lines in) {
    for (size_t i = 0; i < in.count; ++i)
        lines_add(out, in.items[i]);
    free(in.items);
}
void lines_free(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
}
Words words(char *text) {
    Words result = {0};
    char *part = text;
    for (;;) {
        result.items = resize(result.items, (size_t)(result.count + 1) * sizeof(char *));
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
char *bundle(const Input *input, int mask, const char *separator) {
    Text text = {0};
    for (int i = 0; i < input->item_count; ++i)
        if (mask & (1 << i)) {
            if (text.count)
                text_add(&text, separator);
            text_add(&text, input->items[i].name);
        }
    if (!text.count)
        text_add(&text, "-");
    return text_take(&text);
}
char *number_list(Bids bids) {
    Text text = {0};
    for (int i = 0; i < bids.count; ++i)
        text_format(&text, "%s%d", i ? "+" : "", bids.items[i]->number);
    if (!bids.count)
        text_add(&text, "-");
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
