#include "cart.h"

typedef struct Block {
    struct Block *next;
    size_t used, capacity;
    max_align_t data[];
} Block;
static Block *arena;
static void release_arena(void) {
    while (arena) {
        Block *next = arena->next;
        free(arena);
        arena = next;
    }
}
void *allocate(size_t bytes) {
    size_t alignment = _Alignof(max_align_t);
    size_t size = (bytes + alignment - 1) / alignment * alignment;
    if (!arena || size > arena->capacity - arena->used) {
        size_t capacity = size > 65536 ? size : 65536;
        Block *block = malloc(sizeof(*block) + capacity);
        if (!block) exit(EXIT_FAILURE);
        if (!arena && atexit(release_arena)) exit(EXIT_FAILURE);
        *block = (Block){arena, 0, capacity};
        arena = block;
    }
    void *result = (unsigned char *)arena->data + arena->used;
    arena->used += size;
    memset(result, 0, bytes);
    return result;
}
static char *vformat(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (count < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)count + 1);
    vsnprintf(result, (size_t)count + 1, pattern, arguments);
    return result;
}
char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = vformat(pattern, arguments);
    va_end(arguments);
    return result;
}
void add_line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        char **items = allocate((size_t)lines->capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
    }
    va_list arguments;
    va_start(arguments, pattern);
    lines->items[lines->count++] = vformat(pattern, arguments);
    va_end(arguments);
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines result = {0};
    char buffer[4096];
    while (fgets(buffer, sizeof buffer, file)) {
        buffer[strcspn(buffer, "\n")] = '\0';
        add_line(&result, "%s", buffer);
    }
    if (ferror(file) || fclose(file)) exit(EXIT_FAILURE);
    return result;
}
char *counts_text(const Integer *counts, int count) {
    char *result = allocate((size_t)count * 24 + 1);
    int length = 0;
    for (int i = 0; i < count; ++i) length += sprintf(result + length, "%s%lld", i ? " " : "", counts[i]);
    return result;
}
static int fields(char *line, const char *separator, char **parts) {
    int count = 0;
    for (char *word = strtok(line, separator); word; word = strtok(NULL, separator)) parts[count++] = word;
    return count;
}
static int position(char names[][21], int count, const char *name) {
    for (int i = 0; i < count; ++i) if (!strcmp(names[i], name)) return i;
    exit(EXIT_FAILURE);
}
static int read_rows(const char *name, Dataset *data, Row *rows) {
    Lines lines = read_lines(format("input/%s.csv", name));
    for (int i = 1; i < lines.count; ++i) {
        char *parts[14];
        fields(lines.items[i], ",", parts);
        Row *row = &rows[i - 1];
        strcpy(row->id, parts[0]);
        for (int a = 0; a < data->attribute_count; ++a) {
            Attribute *attribute = &data->attributes[a];
            const char *value = parts[a + 1];
            row->values[a] = !strcmp(value, "?") ? -1 : attribute->integer ? atoll(value) : position(attribute->values, attribute->value_count, value);
        }
        row->label = position(data->classes, data->class_count, parts[data->attribute_count + 1]);
    }
    return lines.count - 1;
}
void load_dataset(Dataset *data) {
    Lines schema = read_lines("input/schema.txt");
    for (int i = 0; i < schema.count; ++i) {
        char *parts[12];
        int count = fields(schema.items[i], " ", parts);
        if (!strcmp(parts[0], "ATTRIBUTE")) {
            Attribute *attribute = &data->attributes[data->attribute_count++];
            strcpy(attribute->name, parts[1]);
            attribute->integer = !strcmp(parts[2], "INT");
            attribute->value_count = count - 3;
            for (int j = 3; j < count; ++j) strcpy(attribute->values[j - 3], parts[j]);
        } else {
            strcpy(data->target, parts[1]);
            data->class_count = count - 2;
            for (int j = 2; j < count; ++j) strcpy(data->classes[j - 2], parts[j]);
        }
    }
    Lines settings = read_lines("input/params.txt");
    Integer values[10][500] = {{0}};
    int counts[10] = {0};
    for (int i = 0; i < 10; ++i) {
        char *parts[501];
        int count = fields(settings.items[i], " ", parts);
        for (int j = 1; j < count; ++j) values[i][counts[i]++] = atoll(parts[j]);
    }
    data->settings = (Settings){(int)values[0][0], (int)values[1][0], (int)values[2][0], (int)values[3][0], (int)values[4][0], (int)values[6][0], (int)values[8][0], values[7][0], values[9][0], {0}, counts[5]};
    for (int i = 0; i < counts[5]; ++i) data->settings.curve[i] = (int)values[5][i];
    data->train_count = read_rows("train", data, data->train);
    data->validation_count = read_rows("validation", data, data->validation);
    data->test_count = read_rows("test", data, data->test);
}
Rows row_sequence(const Row *rows, int count) {
    Rows result = { .count = count };
    for (int i = 0; i < count; ++i) result.items[i] = &rows[i];
    return result;
}
