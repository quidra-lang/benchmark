#include "coherence.h"
struct MemoryBlock {
    MemoryBlock *next;
    size_t used, capacity;
    max_align_t alignment;
    unsigned char data[];
};
Memory permanent = {0};
Memory *memory = &permanent;
void *allocate(size_t size) {
    size_t alignment = _Alignof(max_align_t);
    size = (size + alignment - 1) / alignment * alignment;
    if (!memory->head || memory->head->capacity - memory->head->used < size) {
        size_t capacity = size > 65536 ? size : 65536;
        MemoryBlock *block = malloc(sizeof(*block) + capacity);
        if (!block)
            exit(1);
        block->next = memory->head;
        block->used = 0;
        block->capacity = capacity;
        memory->head = block;
    }
    void *result = memory->head->data + memory->head->used;
    memory->head->used += size;
    memset(result, 0, size);
    return result;
}
void clear_memory(Memory *pool) {
    while (pool->head) {
        MemoryBlock *next = pool->head->next;
        free(pool->head);
        pool->head = next;
    }
}
char *substring(const char *source, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, source, length);
    return result;
}
char *copy_text(const char *source) { return substring(source, strlen(source)); }
char *format(const char *pattern, ...) {
    va_list arguments, copy;
    va_start(arguments, pattern);
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    va_end(arguments);
    return result;
}
Names split(const char *source, const char *separator) {
    Names out = {0};
    size_t length = strlen(separator);
    const char *start = source;
    for (;;) {
        const char *end = strstr(start, separator);
        Names_add(&out, end ? substring(start, (size_t)(end - start)) : copy_text(start));
        if (!end)
            return out;
        start = end + length;
    }
}
char *join(Names values, const char *separator) {
    size_t length = 1;
    for (size_t i = 0; i < values.count; ++i)
        length += strlen(values.items[i]) + (i ? strlen(separator) : 0);
    char *out = allocate(length), *at = out;
    for (size_t i = 0; i < values.count; ++i) {
        if (i) {
            size_t n = strlen(separator);
            memcpy(at, separator, n);
            at += n;
        }
        size_t n = strlen(values.items[i]);
        memcpy(at, values.items[i], n);
        at += n;
    }
    return out;
}
char *trim(const char *source) {
    while (*source == ' ')
        ++source;
    size_t length = strlen(source);
    while (length && source[length - 1] == ' ')
        --length;
    return substring(source, length);
}
Names read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(1);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *source = allocate((size_t)length + 1);
    fread(source, 1, (size_t)length, file);
    fclose(file);
    Names lines = split(source, "\n");
    if (length && source[length - 1] == '\n')
        --lines.count;
    return lines;
}

bool decimal_integer(const char *s, size_t maximum) {
    size_t length = strlen(s);
    if (!length || length > maximum || (length > 1 && s[0] == '0'))
        return false;
    for (size_t i = 0; i < length; ++i)
        if (s[i] < '0' || s[i] > '9')
            return false;
    return true;
}
bool valid_hex_address(const char *s) {
    if (strlen(s) != 8)
        return false;
    for (int i = 0; i < 8; ++i)
        if (!((s[i] >= '0' && s[i] <= '9') || (s[i] >= 'a' && s[i] <= 'f')))
            return false;
    return true;
}
Number hex_value(const char *s) { return strtoll(s, NULL, 16); }
char *hex_address(Number value) { return format("%08llx", (unsigned long long)value); }
static int lookup(const char *name, const char *const *names, int count) {
    for (int i = 0; i < count; ++i)
        if (!strcmp(name, names[i]))
            return i;
    return -1;
}
Config read_config(void) {
    Config c = {0};
    Names lines = read_lines("input/config.txt");
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        char **s = f.items;
        if (!strcmp(s[0], "CORES"))
            c.cores = atoi(s[1]);
        else if (!strcmp(s[0], "LINE"))
            c.line_size = atoi(s[1]);
        else if (!strcmp(s[0], "L1")) {
            c.l1_size = atoi(s[1]);
            c.l1_ways = atoi(s[2]);
        } else if (!strcmp(s[0], "L2")) {
            c.l2_size = atoi(s[1]);
            c.l2_ways = atoi(s[2]);
        } else if (!strcmp(s[0], "LATENCY")) {
            c.t1 = atoll(s[1]);
            c.t2 = atoll(s[2]);
            c.tm = atoll(s[3]);
            c.tb = atoll(s[4]);
        } else if (!strcmp(s[0], "SCENARIO")) {
            int order = c.scenario_count;
            c.scenarios[c.scenario_count++] =
                (Scenario){s[1], (Protocol)lookup(s[2], protocol_names, 4),
                           (Replacement)lookup(s[3], replacement_names, 3),
                           (Replacement)lookup(s[4], replacement_names, 3), order};
        } else if (!strcmp(s[0], "PRIMARY"))
            c.primary = s[1];
        else if (!strcmp(s[0], "INTERVAL"))
            c.interval = atoll(s[1]);
        else if (!strcmp(s[0], "TOP"))
            c.top = atoi(s[1]);
        else if (!strcmp(s[0], "REGION"))
            c.regions[c.region_count++] = (Region){s[1], hex_value(s[2]), hex_value(s[3])};
        else if (!strcmp(s[0], "WATCH"))
            c.watch[c.watch_count++] = hex_value(s[1]) / c.line_size;
    }
    c.l1_sets = c.l1_size / (c.line_size * c.l1_ways);
    c.l2_sets = c.l2_size / (c.line_size * c.l2_ways);
    c.cap = c.l1_sets * c.l1_ways;
    return c;
}
void write_lines(const char *filename, Names lines) {
    mkdir("output", 0777);
    FILE *file = fopen(format("output/%s", filename), "wb");
    for (size_t i = 0; i < lines.count; ++i)
        fprintf(file, "%s\n", lines.items[i]);
    fclose(file);
}
