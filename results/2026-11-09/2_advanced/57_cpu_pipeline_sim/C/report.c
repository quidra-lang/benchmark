#include "simulator.h"
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
    void *out = calloc(count ? count : 1, size);
    if (!out)
        exit(EXIT_FAILURE);
    return out;
}
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)length + 1, 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    Allocation *item = allocate(1, sizeof(*item));
    if (!allocations)
        atexit(release);
    item->pointer = out;
    item->next = allocations;
    allocations = item;
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
void line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        char **data = realloc(lines->data, (size_t)lines->capacity * sizeof(char *));
        if (!data)
            exit(EXIT_FAILURE);
        lines->data = data;
    }
    va_list args;
    va_start(args, pattern);
    lines->data[lines->count++] = formatted(pattern, args);
    va_end(args);
}
char *joined(const char *a, const char *b) { return format("%s%s", a, b); }
char *decimal(I p, I q) {
    I n = (2 * p * 10000 + q) / (2 * q);
    return format("%lld.%04lld", n / 10000, n % 10000);
}
char *percentage(I p, I q) {
    if (q == 0)
        return "-";
    I n = (2 * p * 10000 + q) / (2 * q);
    return format("%lld.%02lld", n / 100, n % 100);
}
char *fraction(I p, I q) {
    I a = p, b = q;
    while (b) {
        I r = a % b;
        a = b;
        b = r;
    }
    return format("%lld/%lld", p / a, q / a);
}
char *hexadecimal(I value) { return format("%08llx", (unsigned long long)value); }
char *register_name(int value) { return value < 0 ? "-" : format("r%d", value); }
char *cycle_heading(int start, int end) {
    char *out = allocate((size_t)(end - start + 25), 1);
    strcpy(out, "cycle                  ");
    for (int i = start; i <= end; ++i)
        out[23 + i - start] = (char)('0' + i % 10);
    return out;
}
char *diagram_row(int number, I pc, const char *kind, const char *characters,
                  const char *annotation) {
    return format("%6s %s %-6s %s%s", number < 0 ? "-" : format("%d", number), hexadecimal(pc),
                  kind, characters, annotation);
}
void save(const char *name, Lines lines) {
    mkdir("output", 0777);
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
