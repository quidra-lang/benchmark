#include "heat.h"
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
char *time_text(int milliseconds) {
    return format("%d.%03d", milliseconds / 1000, milliseconds % 1000);
}
int hottest(const double *field, int count) {
    int out = 0;
    for (int p = 1; p < count; ++p)
        if (field[p] > field[out])
            out = p;
    return out;
}
char *summary(const char *prefix, const Mesh *mesh, const double *field) {
    int point = hottest(field, mesh->count);
    double minimum = field[0], total = 0;
    for (int p = 0; p < mesh->count; ++p) {
        if (field[p] < minimum)
            minimum = field[p];
        total += field[p];
    }
    return format("%s max %s at %s min %s mean %s", prefix, real(field[point], 2),
                  coordinates(mesh, point), real(minimum, 2), real(total / mesh->count, 2));
}
void field_lines(Lines *lines, const Mesh *mesh, const double *field) {
    for (int r = 0; r < mesh->height; ++r) {
        char *row = "";
        for (int c = 0; c < mesh->width; ++c)
            row = joined(row, format("%s%s", c ? " " : "", real(field[cell(mesh, r, c)], 2)));
        line(lines, "%s", row);
    }
}
void isotherms(Lines *lines, const char *prefix, const Mesh *mesh, const double *field,
               const Params *params) {
    int counts[10] = {0}, digits[1000] = {0};
    for (int p = 0; p < mesh->count; ++p) {
        for (int i = 0; i < params->band_count; ++i)
            digits[p] += params->bands[i] <= field[p];
        ++counts[digits[p]];
    }
    char *heading = format("%s counts", prefix);
    for (int i = 0; i <= params->band_count; ++i)
        heading = joined(heading, format(" %d", counts[i]));
    line(lines, "%s", heading);
    int peak = hottest(field, mesh->count);
    for (int r = 0; r < mesh->height; ++r) {
        char row[41];
        for (int c = 0; c < mesh->width; ++c) {
            int p = cell(mesh, r, c);
            row[c] = p == peak ? '*' : (char)('0' + digits[p]);
        }
        row[mesh->width] = '\0';
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
