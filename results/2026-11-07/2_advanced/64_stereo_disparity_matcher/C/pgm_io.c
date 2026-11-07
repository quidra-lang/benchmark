#include "stereo.h"
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
PGM read_pgm(const char *path) {
    FILE *input = fopen(path, "rb");
    char magic[3];
    int maximum;
    PGM out = {0};
    fscanf(input, "%2s %d %d %d", magic, &out.width, &out.height, &maximum);
    out.pixels = allocate((size_t)(out.width * out.height), sizeof(I));
    for (int i = 0; i < out.width * out.height; ++i)
        fscanf(input, "%lld", &out.pixels[i]);
    fclose(input);
    return out;
}
Params read_parameters(void) {
    FILE *input = fopen("input/params.txt", "rb");
    Params p = {0};
    char text[512];
    while (fgets(text, sizeof(text), input)) {
        char key[40];
        sscanf(text, "%39s", key);
        const char *value = text + strlen(key) + 1;
        if (strcmp(key, "disparity_min") == 0)
            sscanf(value, "%d", &p.minimum);
        else if (strcmp(key, "disparity_max") == 0)
            sscanf(value, "%d", &p.maximum);
        else if (strcmp(key, "sad_windows") == 0 || strcmp(key, "ssd_windows") == 0 ||
                 strcmp(key, "census_windows") == 0) {
            int kind = strcmp(key, "sad_windows") == 0   ? 0
                       : strcmp(key, "ssd_windows") == 0 ? 1
                                                         : 2,
                offset = 0, used, window;
            while (sscanf(value + offset, "%d %n", &window, &used) == 1) {
                p.windows[kind][p.window_counts[kind]++] = window;
                offset += used;
            }
        } else if (strcmp(key, "texture_window") == 0)
            sscanf(value, "%d", &p.texture_window);
        else if (strcmp(key, "texture_threshold") == 0)
            sscanf(value, "%lld", &p.texture_threshold);
        else if (strcmp(key, "uniqueness") == 0)
            sscanf(value, "%lld", &p.uniqueness);
        else if (strcmp(key, "lr_max_diff") == 0)
            sscanf(value, "%lld", &p.lr);
        else if (strcmp(key, "wta_cost") == 0 || strcmp(key, "sgm_cost") == 0) {
            char kind[10];
            sscanf(value, "%9s", kind);
            int index = strcmp(kind, "sad") == 0 ? 0 : strcmp(kind, "ssd") == 0 ? 1 : 2;
            if (strcmp(key, "wta_cost") == 0)
                p.wta_kind = index;
            else
                p.sgm_kind = index;
        } else if (strcmp(key, "sgm_window") == 0)
            sscanf(value, "%d", &p.sgm_window);
        else if (strcmp(key, "sgm_paths") == 0)
            sscanf(value, "%d", &p.paths);
        else if (strcmp(key, "p1") == 0)
            sscanf(value, "%lld", &p.p1);
        else if (strcmp(key, "p2") == 0)
            sscanf(value, "%lld", &p.p2);
        else if (strcmp(key, "p2_gamma") == 0)
            sscanf(value, "%lld", &p.gamma);
        else if (strcmp(key, "speckle_size") == 0)
            sscanf(value, "%d", &p.speckle_size);
        else if (strcmp(key, "speckle_range") == 0)
            sscanf(value, "%d", &p.speckle_range);
        else if (strcmp(key, "fusion_min_votes") == 0)
            sscanf(value, "%d", &p.fusion_votes);
        else if (strcmp(key, "object_range") == 0)
            sscanf(value, "%d", &p.object_range);
        else if (strcmp(key, "object_min_size") == 0)
            sscanf(value, "%d", &p.object_size);
        else if (strcmp(key, "focal_length") == 0)
            sscanf(value, "%lld", &p.focal);
        else if (strcmp(key, "baseline") == 0)
            sscanf(value, "%lld", &p.baseline);
        else if (strcmp(key, "sample") == 0) {
            Point *point = &p.samples[p.sample_count++];
            sscanf(value, "%d %d", &point->x, &point->y);
        }
    }
    fclose(input);
    return p;
}
void write_pgm(const char *name, PGM image) {
    Lines out = {0};
    line(&out, "P2");
    line(&out, "%d %d", image.width, image.height);
    line(&out, "255");
    for (int y = 0; y < image.height; ++y) {
        char *row = "";
        for (int x = 0; x < image.width; ++x)
            row = joined(row, format("%s%lld", x ? " " : "", image.pixels[y * image.width + x]));
        line(&out, "%s", row);
    }
    save(name, out);
}
void save(const char *name, Lines lines) {
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
