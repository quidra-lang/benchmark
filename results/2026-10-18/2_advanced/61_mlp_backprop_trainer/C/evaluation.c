#include "trainer.h"
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
static void release(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->pointer);
        free(allocations);
        allocations = next;
    }
}
void *allocate(size_t count, size_t size) {
    void *pointer = calloc(count ? count : 1, size);
    Allocation *item = malloc(sizeof(*item));
    if (!pointer || !item)
        exit(EXIT_FAILURE);
    if (!allocations)
        atexit(release);
    item->pointer = pointer;
    item->next = allocations;
    allocations = item;
    return pointer;
}
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)length + 1, 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
char *joined(const char *first, const char *second) { return format("%s%s", first, second); }
void line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        int next = lines->capacity ? 2 * lines->capacity : 16;
        char **data = allocate((size_t)next, sizeof(char *));
        if (lines->count)
            memcpy(data, lines->data, (size_t)lines->count * sizeof(char *));
        lines->data = data;
        lines->capacity = next;
    }
    va_list args;
    va_start(args, pattern);
    lines->data[lines->count++] = formatted(pattern, args);
    va_end(args);
}
Lines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    rewind(input);
    char *text = allocate((size_t)size + 1, 1);
    fread(text, 1, (size_t)size, input);
    fclose(input);
    Lines out = {0};
    char *start = text;
    for (long i = 0; i < size; ++i)
        if (text[i] == '\n') {
            text[i] = '\0';
            line(&out, "%s", start);
            start = text + i + 1;
        }
    return out;
}
char *real(double value, int digits) {
    char *out = format("%.*f", digits, value);
    if (out[0] == '-') {
        bool zero = true;
        for (int i = 1; out[i]; ++i)
            if (out[i] != '0' && out[i] != '.')
                zero = false;
        if (zero)
            memmove(out, out + 1, strlen(out));
    }
    return out;
}
char *ratio(int64_t numerator, int64_t denominator) {
    if (!denominator)
        return "-";
    int64_t q = (20000 * numerator + denominator) / (2 * denominator);
    return format("%lld.%04lld", (long long)(q / 10000), (long long)(q % 10000));
}
int prediction(const double *scores, int count) {
    int out = 0;
    for (int k = 1; k < count; ++k)
        if (scores[k] > scores[out])
            out = k;
    return out;
}
int second_class(const double *scores, int count, int first) {
    int out = first == 0 ? 1 : 0;
    for (int k = 0; k < count; ++k)
        if (k != first && scores[k] > scores[out])
            out = k;
    return out;
}
void confusion(const Image *images, const int *predictions, int count, int classes,
               int out[10][10]) {
    memset(out, 0, 100 * sizeof(int));
    for (int i = 0; i < count; ++i)
        ++out[images[i].label][predictions[i]];
    (void)classes;
}
ClassStats class_stats(const int matrix[10][10], int label, int classes) {
    ClassStats out = {0, 0, matrix[label][label]};
    for (int k = 0; k < classes; ++k) {
        out.support += matrix[label][k];
        out.predicted += matrix[k][label];
    }
    return out;
}
void level_maps(Lines *lines, int levels[10][64], int classes, int width, int height) {
    for (int r = 0; r < height; ++r) {
        char *row = "";
        for (int k = 0; k < classes; ++k) {
            if (k)
                row = joined(row, " ");
            for (int c = 0; c < width; ++c)
                row = joined(row, format("%d", levels[k][r * width + c]));
        }
        line(lines, "%s", row);
    }
}
void image_lines(Lines *lines, const Image *image, int width, int height) {
    for (int r = 0; r < height; ++r) {
        char row[65];
        for (int c = 0; c < width; ++c)
            row[c] = image->pixels[r * width + c] == '1' ? '#' : '.';
        row[width] = '\0';
        line(lines, "%s", row);
    }
}
void save(const char *name, Lines lines) {
    mkdir("output", 0777);
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
