#include "image.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;

static void release_all(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations);
        allocations = next;
    }
}

void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}

static char *formatted(const char *pattern, va_list arguments) {
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
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? text->capacity * 2 : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}

void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}

Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    Text line = {0};
    int ch;
    while ((ch = fgetc(file)) != EOF) {
        if (ch == '\n') {
            add_line(&lines, "%s", line.data ? line.data : "");
            line.size = 0;
            if (line.data) line.data[0] = '\0';
        }
        else text_add(&line, "%c", ch);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return lines;
}

int words(char *line, char **parts) {
    int count = 0;
    for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) parts[count++] = word;
    return count;
}

Image *read_images(int *count) {
    Lines source = read_lines("input/images.txt");
    Text joined = {0};
    for (int i = 0; i < source.count; ++i) {
        char *comment = strchr(source.items[i], '#');
        if (comment) *comment = '\0';
        text_add(&joined, "%s ", source.items[i]);
    }
    char **parts = allocate((joined.size + 1) * sizeof(*parts));
    int total = words(joined.data, parts), position = 0;
    Image *images = allocate(8 * sizeof(*images));
    *count = 0;
    while (position < total) {
        Image *image = &images[(*count)++];
        image->name = parts[position + 1];
        image->width = atoi(parts[position + 3]);
        image->height = atoi(parts[position + 4]);
        image->maxval = atoi(parts[position + 5]);
        position += 6;
        int size = image->width * image->height;
        image->pixels = allocate((size_t)size * sizeof(*image->pixels));
        for (int i = 0; i < size; ++i) image->pixels[i] = atoi(parts[position++]);
    }
    return images;
}
