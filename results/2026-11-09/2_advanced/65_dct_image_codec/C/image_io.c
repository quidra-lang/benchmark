#include "codec.h"
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
void byte(Bytes *bytes, int value) {
    if (bytes->count == bytes->capacity) {
        int capacity = bytes->capacity ? 2 * bytes->capacity : 32;
        int *data = allocate((size_t)capacity, sizeof(int));
        if (bytes->count)
            memcpy(data, bytes->data, (size_t)bytes->count * sizeof(int));
        bytes->data = data;
        bytes->capacity = capacity;
    }
    bytes->data[bytes->count++] = value;
}
void append(Bytes *first, const Bytes *second) {
    for (int i = 0; i < second->count; ++i)
        byte(first, second->data[i]);
}
Image read_ppm(const char *path) {
    FILE *input = fopen(path, "rb");
    char magic[3];
    int maximum;
    Image out = {0};
    fscanf(input, "%2s %d %d %d", magic, &out.width, &out.height, &maximum);
    out.pixels = allocate((size_t)(out.width * out.height), sizeof(Pixel));
    for (int i = 0; i < out.width * out.height; ++i)
        for (int c = 0; c < 3; ++c)
            fscanf(input, "%lld", &out.pixels[i].values[c]);
    fclose(input);
    return out;
}
Params read_params(void) {
    FILE *input = fopen("input/params.txt", "rb");
    char text[512];
    Params out = {0};
    while (fgets(text, sizeof(text), input)) {
        char key[32];
        sscanf(text, "%31s", key);
        const char *value = text + strlen(key) + 1;
        if (strcmp(key, "qualities") == 0 || strcmp(key, "truncate") == 0) {
            int *values = strcmp(key, "qualities") == 0 ? out.qualities : out.truncate,
                *count = strcmp(key, "qualities") == 0 ? &out.quality_count : &out.truncate_count;
            int offset = 0, used, item;
            while (sscanf(value + offset, "%d %n", &item, &used) == 1) {
                values[(*count)++] = item;
                offset += used;
            }
        } else if (strcmp(key, "sampling") == 0)
            sscanf(value, "%d", &out.sampling);
        else if (strcmp(key, "restart_interval") == 0)
            sscanf(value, "%d", &out.restart);
        else if (strcmp(key, "huffman") == 0)
            out.optimized = strncmp(value, "optimized", 9) == 0;
        else if (strcmp(key, "target_bytes") == 0)
            sscanf(value, "%d", &out.target);
        else if (strcmp(key, "generations") == 0)
            sscanf(value, "%d", &out.generations);
    }
    fclose(input);
    return out;
}
SourceTables *read_tables(void) {
    FILE *input = fopen("input/tables.txt", "rb");
    SourceTables *out = allocate(1, sizeof(SourceTables));
    char key[32];
    fscanf(input, "%31s", key);
    for (int u = 0; u < 8; ++u)
        for (int x = 0; x < 8; ++x)
            fscanf(input, "%lld", &out->transform.values[u][x]);
    for (int t = 0; t < 2; ++t) {
        int id;
        fscanf(input, "%31s %d", key, &id);
        for (int u = 0; u < 8; ++u)
            for (int v = 0; v < 8; ++v)
                fscanf(input, "%lld", &out->basic[t].values[u][v]);
    }
    for (int t = 0; t < 4; ++t) {
        int kind, id, counts[16], symbols[256], total = 0;
        fscanf(input, "%31s %d %d", key, &kind, &id);
        for (int i = 0; i < 16; ++i) {
            fscanf(input, "%d", &counts[i]);
            total += counts[i];
        }
        for (int i = 0; i < total; ++i)
            fscanf(input, "%d", &symbols[i]);
        out->huffman.values[kind][id] = huffman(counts, symbols, total);
    }
    fclose(input);
    return out;
}
Bytes read_hex(const char *path) {
    FILE *input = fopen(path, "rb");
    char text[128];
    Bytes out = {0};
    while (fscanf(input, "%127s", text) == 1)
        for (int i = 0; text[i]; i += 2) {
            char pair[3] = {text[i], text[i + 1], 0};
            byte(&out, (int)strtol(pair, NULL, 16));
        }
    fclose(input);
    return out;
}
void save(const char *name, Lines lines) {
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
void write_ppm(const char *name, Image image) {
    Lines out = {0};
    line(&out, "P3");
    line(&out, "%d %d", image.width, image.height);
    line(&out, "255");
    for (int y = 0; y < image.height; ++y) {
        char *row = "";
        for (int x = 0; x < image.width; ++x)
            for (int c = 0; c < 3; ++c)
                row = joined(row, format("%s%lld", strlen(row) ? " " : "",
                                         image.pixels[y * image.width + x].values[c]));
        line(&out, "%s", row);
    }
    save(name, out);
}
void write_hex(const char *name, Bytes bytes) {
    const char *digits = "0123456789abcdef";
    Lines out = {0};
    for (int offset = 0; offset < bytes.count; offset += 32) {
        char row[65];
        int length = 0;
        for (int i = offset; i < offset + 32 && i < bytes.count; ++i) {
            row[length++] = digits[bytes.data[i] / 16];
            row[length++] = digits[bytes.data[i] % 16];
        }
        row[length] = 0;
        line(&out, "%s", row);
    }
    save(name, out);
}
