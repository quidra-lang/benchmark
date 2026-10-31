#include "segments.h"

typedef struct Block { struct Block *next; size_t used, capacity; max_align_t data[]; } Block;
static Block *arena;
static void release_arena(void) {
    while (arena) { Block *next = arena->next; free(arena); arena = next; }
}
void *allocate(size_t bytes) {
    size_t alignment = _Alignof(max_align_t), size = (bytes + alignment - 1) / alignment * alignment;
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
void extend(Lines *target, Lines source) { for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]); }
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines result = {0};
    int length = 0, capacity = 256, character;
    char *buffer = allocate((size_t)capacity);
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') { buffer[length] = '\0'; add_line(&result, "%s", buffer); length = 0; }
        else {
            if (length + 1 == capacity) {
                capacity *= 2;
                char *next = allocate((size_t)capacity);
                memcpy(next, buffer, (size_t)length);
                buffer = next;
            }
            buffer[length++] = (char)character;
        }
    }
    if (ferror(file) || fclose(file)) exit(EXIT_FAILURE);
    return result;
}
int split_fields(char *line, const char *separator, char **parts) {
    int count = 0;
    for (char *part = strtok(line, separator); part; part = strtok(NULL, separator)) parts[count++] = part;
    return count;
}
int string_index(char *const *values, int count, const char *value) {
    for (int i = 0; i < count; ++i) if (!strcmp(values[i], value)) return i;
    return -1;
}
static int compare_strings(const void *first, const void *second) { return strcmp(*(char *const *)first, *(char *const *)second); }
static Settings read_settings(void) {
    Lines lines = read_lines("input/params.txt");
    char **parts[17];
    int counts[17];
    for (int i = 0; i < 17; ++i) {
        parts[i] = allocate((strlen(lines.items[i]) + 1) * sizeof(char *));
        counts[i] = split_fields(lines.items[i], " ", parts[i]) - 1;
        ++parts[i];
    }
    Settings result = {0};
    result.reference = atoi(parts[0][0]);
    result.snapshot = atoi(parts[1][0]);
    result.outcome_days = atoi(parts[2][0]);
    result.min_k = atoi(parts[3][0]); result.max_k = atoi(parts[3][1]);
    result.method_count = counts[4];
    for (int i = 0; i < counts[4]; ++i) result.methods[i] = parts[4][i];
    result.restarts = atoi(parts[5][0]); result.iterations = atoi(parts[6][0]); result.seed = atoll(parts[7][0]);
    result.subsamples = atoi(parts[8][0]); result.percent = atoi(parts[9][0]); result.outlier_sd = atof(parts[10][0]);
    result.overdue_factor = atoi(parts[11][0]); result.bin_count = counts[12];
    for (int i = 0; i < counts[12]; ++i) result.order_bins[i] = atoi(parts[12][i]);
    result.top_categories = atoi(parts[13][0]); result.top_customers = atoi(parts[14][0]);
    result.period_days = atoi(parts[15][0]); result.periods = atoi(parts[16][0]);
    return result;
}
Transactions read_transactions(void) {
    Transactions data = {.settings = read_settings()};
    Lines lines = read_lines("input/transactions.csv");
    data.row_count = lines.count - 1;
    data.rows = allocate((size_t)data.row_count * sizeof(Row));
    data.ids = allocate(400 * sizeof(char *));
    data.categories = allocate((size_t)data.row_count * sizeof(char *));
    char **customer_names = allocate((size_t)data.row_count * sizeof(char *)), **category_names = allocate((size_t)data.row_count * sizeof(char *));
    for (int i = 1; i < lines.count; ++i) {
        char *parts[5], *copy = format("%s", lines.items[i]);
        split_fields(copy, ",", parts);
        if (string_index(data.ids, data.customer_count, parts[0]) < 0) data.ids[data.customer_count++] = parts[0];
        bool duplicate = false;
        for (int j = 1; j < i; ++j) if (!strcmp(lines.items[i], lines.items[j])) { duplicate = true; break; }
        if (duplicate) { ++data.duplicates; continue; }
        Integer value = atoll(parts[4]);
        if (!value) { ++data.free_rows; continue; }
        int index = data.valid_count++;
        Row *row = &data.rows[index];
        row->day = atoi(parts[1]); row->amount = value; strcpy(row->order_id, parts[2]);
        customer_names[index] = parts[0]; category_names[index] = parts[3];
        if (string_index(data.categories, data.category_count, parts[3]) < 0) data.categories[data.category_count++] = parts[3];
    }
    qsort(data.ids, (size_t)data.customer_count, sizeof(char *), compare_strings);
    qsort(data.categories, (size_t)data.category_count, sizeof(char *), compare_strings);
    for (int i = 0; i < data.valid_count; ++i) {
        data.rows[i].customer = string_index(data.ids, data.customer_count, customer_names[i]);
        data.rows[i].category = string_index(data.categories, data.category_count, category_names[i]);
    }
    return data;
}
Orders group_orders(const Transactions *data, int first, int last) {
    Orders result = {.items = allocate((size_t)data->valid_count * sizeof(Order))};
    int *groups = allocate((size_t)data->valid_count * sizeof(int));
    for (int r = 0; r < data->valid_count; ++r) {
        const Row *row = &data->rows[r];
        groups[r] = -1;
        if (row->day < first || row->day > last) continue;
        int index = 0;
        while (index < result.count && strcmp(result.items[index].id, row->order_id)) ++index;
        if (index == result.count) result.items[result.count++] = (Order){.customer = row->customer, .day = row->day, .id = row->order_id};
        Order *order = &result.items[index];
        if (row->day < order->day) order->day = row->day;
        order->net += row->amount;
        ++order->row_count;
        groups[r] = index;
    }
    for (int i = 0; i < result.count; ++i) {
        Order *order = &result.items[i];
        order->rows = allocate((size_t)order->row_count * sizeof(Row *));
        order->row_count = 0;
    }
    for (int r = 0; r < data->valid_count; ++r) if (groups[r] >= 0) {
        Order *order = &result.items[groups[r]];
        order->rows[order->row_count++] = &data->rows[r];
    }
    return result;
}
