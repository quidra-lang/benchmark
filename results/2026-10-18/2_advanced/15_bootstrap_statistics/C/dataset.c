#include "statistics.h"

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
void extend(Lines *target, Lines source) {
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    char buffer[128];
    while (fgets(buffer, sizeof buffer, file)) {
        buffer[strcspn(buffer, "\n")] = '\0';
        add_line(&lines, "%s", buffer);
    }
    if (ferror(file) || fclose(file)) exit(EXIT_FAILURE);
    return lines;
}
static int fields(char *line, const char *separator, char **parts) {
    int count = 0;
    for (char *part = strtok(line, separator); part; part = strtok(NULL, separator)) parts[count++] = part;
    return count;
}
static Integer hundredths(const char *word) {
    Integer value = 100 * atoll(word);
    const char *point = strchr(word, '.');
    if (point) value += 10 * (point[1] - '0') + (point[2] ? point[2] - '0' : 0);
    return value;
}
static int group_index(const Dataset *data, const char *name) {
    for (int i = 0; i < data->group_count; ++i) if (!strcmp(data->groups[i].name, name)) return i;
    return -1;
}
void load_dataset(Dataset *data) {
    Lines samples = read_lines("input/samples.csv");
    for (int i = 1; i < samples.count; ++i) {
        char *parts[2];
        fields(samples.items[i], ",", parts);
        int index = group_index(data, parts[0]);
        if (index < 0) {
            index = data->group_count++;
            strcpy(data->groups[index].name, parts[0]);
        }
        Group *group = &data->groups[index];
        group->values[group->count++] = hundredths(parts[1]);
    }
    Lines paired = read_lines("input/paired.csv");
    data->subjects = paired.count - 1;
    for (int i = 1; i < paired.count; ++i) {
        char *parts[3];
        fields(paired.items[i], ",", parts);
        data->before[i - 1] = hundredths(parts[1]);
        data->after[i - 1] = hundredths(parts[2]);
        data->differences[i - 1] = data->after[i - 1] - data->before[i - 1];
    }
    Lines parameters = read_lines("input/params.txt");
    Integer values[7][2] = {{0}};
    for (int i = 0; i < parameters.count; ++i) {
        char *parts[3];
        int count = fields(parameters.items[i], " ", parts);
        if (i < 7) for (int j = 1; j < count; ++j) values[i][j - 1] = atoll(parts[j]);
        else {
            int *pair = data->pairs[data->pair_count++];
            pair[0] = group_index(data, parts[1]);
            pair[1] = group_index(data, parts[2]);
        }
    }
    data->settings = (Settings){values[0][0], (int)values[1][0], (int)values[2][0], (int)values[3][0], (int)values[4][0], (int)values[5][0], (int)values[5][1], (int)values[6][0]};
}
Sample group_sample(const Group *group) { return (Sample){(Integer *)group->values, group->count}; }
