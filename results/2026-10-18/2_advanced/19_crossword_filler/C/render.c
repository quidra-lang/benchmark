#include "crossword.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;

static void release_all(void) {
    while (allocations) { Allocation *next = allocations->next; free(allocations); allocations = next; }
}

void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}

static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    return result;
}

char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = formatted(pattern, arguments);
    va_end(arguments);
    return result;
}

void text_add(Text *text, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *part = formatted(pattern, arguments);
    va_end(arguments);
    size_t length = strlen(part);
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}

void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}

void paragraph(Lines *target, Lines source) {
    if (target->count) add_line(target, "");
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}

char *decimal(int numerator, int denominator, int places) {
    int scale = 1;
    for (int i = 0; i < places; ++i) scale *= 10;
    int rounded = (2 * numerator * scale + denominator) / (2 * denominator);
    return format("%d.%0*d", rounded / scale, places, rounded % scale);
}

void render_grid(const Grid *grid, const State *state, Lines *lines) {
    for (int row = 0; row < grid->height; ++row) add_line(lines, "%.*s", grid->width, state->letters + row * grid->width);
}

void render_numbers(const Layout *layout, Lines *lines) {
    const Grid *grid = &layout->grid;
    for (int row = 0; row < grid->height; ++row) {
        Text text = {0};
        for (int column = 0; column < grid->width; ++column) {
            int cell = row * grid->width + column;
            if (column) text_add(&text, " ");
            if (grid->cells[cell] == '#') text_add(&text, "##");
            else if (layout->numbers[cell]) text_add(&text, "%2d", layout->numbers[cell]);
            else text_add(&text, " .");
        }
        add_line(lines, "%s", text.data);
    }
}

char *list_line(const Slot *slot, const char *clue, const char *entry, const char *score, bool theme) {
    return format("%d. %s (%d) %s %s%s", slot->number, clue, slot->length, entry, score, theme ? " theme" : "");
}

void write_lines(const char *name, Lines lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines.count; ++i) if (fprintf(file, "%s\n", lines.items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
