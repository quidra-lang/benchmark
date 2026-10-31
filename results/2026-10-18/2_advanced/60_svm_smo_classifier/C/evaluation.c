#include "classifier.h"
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
Lines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    rewind(input);
    char *text = allocate((size_t)size + 1, 1);
    fread(text, 1, (size_t)size, input);
    fclose(input);
    Lines out = {0};
    char *start = text;
    for (long i = 0; i < size; ++i)
        if (text[i] == '\n') {
            text[i] = '\0';
            line(&out, "%s", start);
            start = text + i + 1;
        }
    return out;
}
int sign(double value) { return value > 0 ? 1 : -1; }
Fold *folds(int count, int k) {
    Fold *out = allocate((size_t)k, sizeof(Fold));
    for (int fold = 0; fold < k; ++fold)
        for (int i = 0; i < count; ++i) {
            if (i % k == fold)
                out[fold].test[out[fold].test_count++] = i;
            else
                out[fold].train[out[fold].train_count++] = i;
        }
    return out;
}
Evaluation evaluate(const Example *data, const double *values, int count) {
    Evaluation out = {0};
    for (int i = 0; i < count; ++i) {
        bool positive = sign(values[i]) == 1;
        if (data[i].label == 1) {
            if (positive)
                ++out.tp;
            else
                ++out.fn;
        } else {
            if (positive)
                ++out.fp;
            else
                ++out.tn;
        }
    }
    return out;
}
double auc(const Example *data, const double *values, int count) {
    double out = 0;
    int positive = 0, negative = 0;
    for (int i = 0; i < count; ++i) {
        positive += data[i].label == 1;
        negative += data[i].label == -1;
    }
    for (int i = 0; i < count; ++i)
        if (data[i].label == 1)
            for (int j = 0; j < count; ++j)
                if (data[j].label == -1)
                    out += values[i] > values[j] ? 1 : values[i] == values[j] ? 0.5 : 0;
    return out / (positive * negative);
}
char *real(double value, int digits) {
    char *out = format("%.*f", digits, value);
    if (out[0] == '-') {
        bool zero = true;
        for (int i = 1; out[i]; ++i)
            if (out[i] != '0' && out[i] != '.')
                zero = false;
        if (zero)
            memmove(out, out + 1, strlen(out));
    }
    return out;
}
char *ratio(int numerator, int denominator) {
    return denominator ? real((double)numerator / denominator, 4) : "-";
}
void confusion_matrix(const Example *data, const MultiPrediction *predictions, int count, bool rest,
                      int out[3][3]) {
    memset(out, 0, 9 * sizeof(int));
    for (int i = 0; i < count; ++i)
        ++out[data[i].label - 1][(rest ? predictions[i].ovr : predictions[i].ovo) - 1];
}
void save(const char *name, Lines lines) {
    mkdir("output", 0777);
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
