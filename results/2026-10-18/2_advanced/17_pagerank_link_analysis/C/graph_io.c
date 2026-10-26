#include "analysis.h"

typedef struct Block { struct Block *next; size_t used, capacity; max_align_t data[]; } Block;
static Block *arena;
static void release_arena(void) { while (arena) { Block *next = arena->next; free(arena); arena = next; } }
void *allocate(size_t bytes) {
    size_t alignment = _Alignof(max_align_t), size = (bytes + alignment - 1) / alignment * alignment;
    if (!arena || size > arena->capacity - arena->used) {
        size_t capacity = size > 65536 ? size : 65536;
        Block *block = malloc(sizeof(*block) + capacity);
        if (!block) exit(EXIT_FAILURE);
        if (!arena && atexit(release_arena)) exit(EXIT_FAILURE);
        *block = (Block){arena, 0, capacity}; arena = block;
    }
    void *result = (unsigned char *)arena->data + arena->used;
    arena->used += size; memset(result, 0, bytes); return result;
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
    va_end(arguments); return result;
}
void add_line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        char **items = allocate((size_t)lines->capacity * sizeof(char *));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(char *));
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
    Lines lines = {0};
    int length = 0, capacity = 256, character;
    char *buffer = allocate((size_t)capacity);
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') { buffer[length] = '\0'; add_line(&lines, "%s", buffer); length = 0; }
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
    return lines;
}
int split_fields(char *line, const char *separator, char **parts) {
    int count = 0;
    for (char *part = strtok(line, separator); part; part = strtok(NULL, separator)) parts[count++] = part;
    return count;
}
static int compare_pages(const void *first, const void *second) { return ((const Page *)first)->id - ((const Page *)second)->id; }
void read_input(Input *input) {
    Lines pages = read_lines("input/pages.csv");
    for (int i = 1; i < pages.count; ++i) {
        char *parts[3];
        split_fields(pages.items[i], ",", parts);
        Page *page = &input->pages[input->count++];
        page->id = atoi(parts[0]); page->host = parts[1]; page->title = parts[2];
        char *copy = format("%s", page->title);
        page->word_count = split_fields(copy, " ", page->words);
    }
    qsort(input->pages, (size_t)input->count, sizeof(Page), compare_pages);
    Lines links = read_lines("input/links.csv");
    for (int i = 1; i < links.count; ++i) {
        char *parts[2]; split_fields(links.items[i], ",", parts);
        input->records[input->record_count++] = (Record){i + 1, atoi(parts[0]), atoi(parts[1])};
    }
    Lines queries = read_lines("input/queries.txt");
    for (int i = 0; i < queries.count; ++i) {
        Query *query = &input->queries[input->query_count++];
        char *bar = strstr(queries.items[i], " | ");
        *bar = '\0';
        query->word_count = split_fields(queries.items[i], " ", query->words);
        char *seeds[5]; query->seed_count = split_fields(bar + 3, " ", seeds);
        for (int s = 0; s < query->seed_count; ++s) query->seeds[s] = atoi(seeds[s]);
    }
    Lines parameters = read_lines("input/params.txt");
    char *values[11][11]; int counts[11];
    for (int i = 0; i < 11; ++i) {
        char *parts[11]; int count = split_fields(parameters.items[i], " ", parts);
        counts[i] = count - 1;
        for (int j = 1; j < count; ++j) values[i][j - 1] = parts[j];
    }
    Settings *settings = &input->settings;
    settings->damping = atof(values[0][0]); settings->iterations = atoi(values[1][0]); settings->tolerance = atof(values[2][0]);
    settings->sweep_count = counts[3];
    for (int i = 0; i < counts[3]; ++i) settings->sweep[i] = atof(values[3][i]);
    settings->trusted_count = counts[4];
    for (int i = 0; i < counts[4]; ++i) settings->trusted[i] = atoi(values[4][i]);
    settings->spam_top = atoi(values[5][0]); settings->spam_threshold = atof(values[6][0]); settings->hits_iterations = atoi(values[7][0]);
    settings->top_k = atoi(values[8][0]); settings->root_limit = atoi(values[9][0]); settings->neighbor_limit = atoi(values[10][0]);
}
Graph graph_from_weights(int count, int *weights) {
    Graph result = {.count = count, .weights = weights};
    for (int u = 0; u < count; ++u) for (int v = 0; v < count; ++v) if (weights[u * count + v] > 0) { ++result.out[u].count; ++result.in[v].count; }
    for (int u = 0; u < count; ++u) {
        result.out[u].values = allocate((size_t)result.out[u].count * sizeof(int));
        result.in[u].values = allocate((size_t)result.in[u].count * sizeof(int));
        result.out[u].count = 0; result.in[u].count = 0;
    }
    for (int u = 0; u < count; ++u) for (int v = 0; v < count; ++v) if (weights[u * count + v] > 0) {
        result.out[u].values[result.out[u].count++] = v;
        result.in[v].values[result.in[v].count++] = u;
    }
    return result;
}
