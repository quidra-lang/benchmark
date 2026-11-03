#include "clustering.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;

static void release_allocations(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations);
        allocations = next;
    }
}
void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_allocations); registered = true; }
    Allocation *block = calloc(1, sizeof *block + bytes);
    if (!block) exit(1);
    block->next = allocations;
    allocations = block;
    return block + 1;
}
static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)count + 1);
    vsnprintf(result, (size_t)count + 1, pattern, arguments);
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
    if (text->length + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? text->capacity : 64;
        while (capacity < text->length + length + 1) capacity *= 2;
        char *storage = allocate(capacity);
        if (text->length) memcpy(storage, text->data, text->length);
        text->data = storage;
        text->capacity = capacity;
    }
    memcpy(text->data + text->length, part, length + 1);
    text->length += length;
}
void add_line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        size_t capacity = lines->capacity ? lines->capacity * 2 : 16;
        char **items = allocate(capacity * sizeof *items);
        if (lines->count) memcpy(items, lines->items, lines->count * sizeof *items);
        lines->items = items;
        lines->capacity = capacity;
    }
    va_list arguments;
    va_start(arguments, pattern);
    lines->items[lines->count++] = formatted(pattern, arguments);
    va_end(arguments);
}
void append_lines(Lines *target, Lines source) {
    for (size_t i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}
void paragraph(Lines *target, Lines source) {
    if (target->count) add_line(target, "");
    append_lines(target, source);
}
Lines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    if (!input) exit(1);
    Lines lines = {0};
    Text line = {0};
    int character;
    while ((character = fgetc(input)) != EOF) {
        if (character == '\n') { add_line(&lines, "%s", line.data ? line.data : ""); line = (Text){0}; }
        else text_add(&line, "%c", character);
    }
    fclose(input);
    return lines;
}
static Lines fields(const char *line, char separator) {
    Lines result = {0};
    const char *start = line;
    for (const char *position = line;; ++position) {
        if (*position == separator || !*position) {
            add_line(&result, "%.*s", (int)(position - start), start);
            if (!*position) break;
            start = position + 1;
        }
    }
    return result;
}
Dataset *read_dataset(void) {
    Dataset *data = allocate(sizeof *data);
    Lines source = read_lines("input/data.csv"), header = fields(source.items[0], ',');
    data->features = (int)header.count - 2;
    for (int feature = 0; feature < data->features; ++feature) data->feature_names[feature] = header.items[feature + 2];
    data->count = (int)source.count - 1;
    for (int i = 0; i < data->count; ++i) {
        Lines row = fields(source.items[i + 1], ',');
        data->ids[i] = row.items[0];
        data->labels[i] = row.items[1];
        for (int feature = 0; feature < data->features; ++feature) data->raw[i][feature] = strtod(row.items[feature + 2], NULL);
    }
    Lines parameters = read_lines("input/params.txt");
    Settings *settings = &data->settings;
    for (size_t i = 0; i < parameters.count; ++i) {
        Lines row = fields(parameters.items[i], ' ');
        char **word = row.items;
        if (!strcmp(word[0], "DISTANCE")) settings->distance = word[1];
        else if (!strcmp(word[0], "STANDARDIZE")) settings->standardize = word[1];
        else if (!strcmp(word[0], "LINKAGES")) {
            settings->linkage_count = (int)row.count - 1;
            for (int j = 0; j < settings->linkage_count; ++j) settings->linkages[j] = word[j + 1];
        } else if (!strcmp(word[0], "CUT_HEIGHTS")) {
            settings->height_count = row.count - 1;
            settings->cut_heights = allocate(settings->height_count * sizeof *settings->cut_heights);
            for (size_t j = 0; j < settings->height_count; ++j) settings->cut_heights[j] = strtod(word[j + 1], NULL);
        } else if (!strcmp(word[0], "CUT_K")) {
            settings->cut_count = (int)row.count - 1;
            for (int j = 0; j < settings->cut_count; ++j) settings->cut_counts[j] = atoi(word[j + 1]);
        } else if (!strcmp(word[0], "INCONSISTENCY")) {
            settings->depth_text = word[1];
            settings->depth = strlen(word[1]) > 3 ? 120 : atoi(word[1]);
            if (settings->depth > 120) settings->depth = 120;
            settings->inconsistency_count = atoi(word[2]);
        } else if (!strcmp(word[0], "GAP_MAX_K")) settings->gap_max_k = atoi(word[1]);
        else if (!strcmp(word[0], "LIST_SIZE")) settings->list_size = atoi(word[1]);
        else if (!strcmp(word[0], "DENDROGRAM_WIDTH")) settings->width = atoi(word[1]);
        else if (!strcmp(word[0], "COMPARE_LINKAGE")) settings->compare_linkage = word[1];
        else if (!strcmp(word[0], "SUBSAMPLES")) { settings->replicates = atoi(word[1]); settings->percent = atoi(word[2]); settings->seed = strtoll(word[3], NULL, 10); }
        else if (!strcmp(word[0], "REFINE_ITERATIONS")) settings->refine_iterations = atoi(word[1]);
    }
    return data;
}
void write_lines(const char *name, Lines lines) {
    FILE *output = fopen(format("output/%s", name), "wb");
    if (!output) exit(1);
    for (size_t i = 0; i < lines.count; ++i) fprintf(output, "%s\n", lines.items[i]);
    fclose(output);
}
