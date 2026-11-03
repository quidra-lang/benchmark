#include "collector.h"
static char *vformat(const char *pattern, va_list args) {
    va_list measure;
    va_copy(measure, args);
    int length = vsnprintf(NULL, 0, pattern, measure);
    va_end(measure);
    char *text = malloc((size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    return text;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *text = vformat(pattern, args);
    va_end(args);
    return text;
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *text = vformat(pattern, args);
    va_end(args);
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? lines->capacity * 2 : 16;
        lines->items = realloc(lines->items, (size_t)lines->capacity * sizeof *lines->items);
    }
    lines->items[lines->count++] = text;
}
void extend_lines(Lines *lines, const Lines *other) {
    for (int i = 0; i < other->count; ++i)
        add_line(lines, "%s", other->items[i]);
}
void write_lines(FILE *file, const Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->items[i]);
}
char *read_line(FILE *file) {
    size_t length = 0, capacity = 128;
    char *text = malloc(capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            text = realloc(text, capacity);
        }
        text[length++] = (char)c;
    }
    if (c == EOF && !length) {
        free(text);
        return NULL;
    }
    text[length] = 0;
    return text;
}
void add_object(Pair *pair, int size) {
    ++pair->count;
    pair->words += size;
}
void merge_pair(Pair *pair, Pair other) {
    pair->count += other.count;
    pair->words += other.words;
}
int object_size(Object object) {
    return 1 + object.p + object.d;
}
const char *type_name(CollectorType type) {
    static const char *names[] = {"MARK_SWEEP", "MARK_COMPACT", "COPYING", "GENERATIONAL", "REFCOUNT"};
    return names[type];
}
const char *kind_name(int kind) {
    static const char *names[] = {"ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"};
    return names[kind];
}
typedef struct {
    int address, id;
} Address;
static int address_compare(const void *first, const void *second) {
    const Address *a = first, *b = second;
    return (a->address > b->address) - (a->address < b->address);
}
Indices address_order(const Heap *heap) {
    Address addresses[5000];
    Indices result = {0};
    for (int i = 0; i < heap->count; ++i)
        if (heap->objects[i].present) {
            addresses[result.count++] = (Address){heap->objects[i].address, i + 1};
        }
    qsort(addresses, (size_t)result.count, sizeof *addresses, address_compare);
    for (int i = 0; i < result.count; ++i)
        result.values[i] = addresses[i].id;
    return result;
}
Blocks range_blocks(const Heap *heap, int first, int end) {
    bool occupied[4096] = {0};
    for (int i = 0; i < heap->count; ++i) {
        Object object = heap->objects[i];
        if (!object.present || object.address < first || object.address >= end)
            continue;
        for (int word = object.address; word < object.address + object_size(object); ++word)
            occupied[word] = true;
    }
    Blocks result = {0};
    for (int start = first; start < end;) {
        if (occupied[start]) {
            ++start;
            continue;
        }
        int stop = start + 1;
        while (stop < end && !occupied[stop])
            ++stop;
        result.values[result.count++] = (Block){start, stop - start};
        start = stop;
    }
    return result;
}
Blocks free_blocks(const Heap *heap) {
    CollectorType type = heap->collector.type;
    Blocks result = {0};
    if (type == MARK_COMPACT || type == COPYING) {
        int end = type == COPYING ? heap->base + heap->size / 2 : heap->size;
        if (heap->top < end)
            result.values[result.count++] = (Block){heap->top, end - heap->top};
        return result;
    }
    if (type == GENERATIONAL) {
        int end = heap->base + heap->collector.young / 2;
        if (heap->top < end)
            result.values[result.count++] = (Block){heap->top, end - heap->top};
        Blocks old = range_blocks(heap, heap->collector.young, heap->size);
        for (int i = 0; i < old.count; ++i)
            result.values[result.count++] = old.values[i];
        return result;
    }
    return range_blocks(heap, 0, heap->size);
}
void free_amount(const Heap *heap, int *total, int *largest) {
    *total = *largest = 0;
    Blocks blocks = free_blocks(heap);
    for (int i = 0; i < blocks.count; ++i) {
        *total += blocks.values[i].length;
        if (blocks.values[i].length > *largest)
            *largest = blocks.values[i].length;
    }
}
int first_fit(const Heap *heap, int size, int first, int end) {
    Blocks blocks = range_blocks(heap, first, end);
    for (int i = 0; i < blocks.count; ++i)
        if (blocks.values[i].length >= size)
            return blocks.values[i].address;
    return -1;
}
int used(const Heap *heap) {
    int words = 0;
    for (int i = 0; i < heap->count; ++i)
        if (heap->objects[i].present)
            words += object_size(heap->objects[i]);
    return words;
}
char *dec2(Integer a, Integer b) {
    Integer value = (200 * a + b) / (2 * b);
    return format("%" PRId64 ".%02" PRId64, value / 100, value % 100);
}
char *pct(Integer a, Integer b) {
    return b ? dec2(100 * a, b) : "-";
}
char *class_table(const int *sizes, int count) {
    int counts[5] = {0};
    for (int i = 0; i < count; ++i) {
        int size = sizes[i];
        ++counts[size == 1 ? 0 : size < 4 ? 1 : size < 8 ? 2 : size < 16 ? 3 : 4];
    }
    return format("1:%d 2-3:%d 4-7:%d 8-15:%d 16+:%d", counts[0], counts[1], counts[2], counts[3], counts[4]);
}
char *heap_map(const Heap *heap, const bool *reachable) {
    char *map = malloc((size_t)heap->size + 1);
    memset(map, '.', (size_t)heap->size);
    map[heap->size] = 0;
    int half = heap->collector.type == COPYING        ? heap->size / 2
               : heap->collector.type == GENERATIONAL ? heap->collector.young / 2
                                                      : 0;
    if (half)
        memset(map + half - heap->base, '-', (size_t)half);
    for (int i = 0; i < heap->count; ++i) {
        Object object = heap->objects[i];
        if (!object.present)
            continue;
        map[object.address] = reachable[i] ? (char)('A' + i % 26) : '#';
        memset(map + object.address + 1, reachable[i] ? 'a' + i % 26 : '=', (size_t)object_size(object) - 1);
    }
    return map;
}

void append_text(char **text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *part = vformat(pattern, args);
    va_end(args);
    size_t old = *text ? strlen(*text) : 0, length = strlen(part);
    *text = realloc(*text, old + length + 1);
    memcpy(*text + old, part, length + 1);
    free(part);
}
