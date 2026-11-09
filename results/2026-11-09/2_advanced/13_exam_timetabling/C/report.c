#include "timetable.h"

typedef struct ArenaBlock {
    struct ArenaBlock *next;
    size_t used, capacity;
    max_align_t data[];
} ArenaBlock;
static ArenaBlock *arena;
static void release_arena(void) {
    while (arena) {
        ArenaBlock *next = arena->next;
        free(arena);
        arena = next;
    }
}
void *allocate(size_t bytes) {
    size_t alignment = _Alignof(max_align_t);
    size_t size = ((bytes ? bytes : 1) + alignment - 1) / alignment * alignment;
    if (!arena || size > arena->capacity - arena->used) {
        size_t capacity = size > 65536 ? size : 65536;
        ArenaBlock *block = malloc(sizeof(*block) + capacity);
        if (!block) exit(EXIT_FAILURE);
        if (!arena && atexit(release_arena)) {
            free(block);
            exit(EXIT_FAILURE);
        }
        *block = (ArenaBlock){arena, 0, capacity};
        arena = block;
    }
    void *result = (unsigned char *)arena->data + arena->used;
    arena->used += size;
    return result;
}
static char *vformat(const char *pattern, va_list arguments) {
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
    char *result = vformat(pattern, arguments);
    va_end(arguments);
    return result;
}
static void push_line(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 16;
        char **items = allocate((size_t)lines->capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
    }
    lines->items[lines->count++] = line;
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    push_line(lines, vformat(pattern, arguments));
    va_end(arguments);
}
void append_lines(Lines *target, const Lines *source) {
    for (int i = 0; i < source->count; ++i) add_line(target, "%s", source->items[i]);
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    char buffer[512];
    while (fgets(buffer, sizeof buffer, file)) {
        buffer[strcspn(buffer, "\n")] = '\0';
        add_line(&lines, "%s", buffer);
    }
    if (ferror(file) || fclose(file)) exit(EXIT_FAILURE);
    return lines;
}
void write_lines(const char *name, const Lines *lines) {
    if (mkdir("output", 0777) && errno != EEXIST) exit(EXIT_FAILURE);
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    if (!file) exit(EXIT_FAILURE);
    for (int i = 0; i < lines->count; ++i)
        if (fprintf(file, "%s\n", lines->items[i]) < 0) exit(EXIT_FAILURE);
    if (fclose(file)) exit(EXIT_FAILURE);
}
char *fixed_width(const char *label, char *const *cells, int count, int label_width, int cell_width) {
    size_t capacity = strlen(label) + (size_t)label_width + 1;
    for (int i = 0; i < count; ++i) capacity += strlen(cells[i]) + (size_t)cell_width;
    char *result = allocate(capacity);
    int offset = sprintf(result, "%-*s", label_width, label);
    for (int i = 0; i < count; ++i) offset += sprintf(result + offset, "%*s", cell_width, cells[i]);
    return result;
}
int rounded_percent(int part, int whole) { return (200 * part + whole) / (2 * whole); }
