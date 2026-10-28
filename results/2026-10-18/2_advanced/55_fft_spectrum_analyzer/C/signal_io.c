#include "analyzer.h"
typedef struct Allocation {
    void *value;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
void *allocate(size_t count, size_t size) {
    void *value = calloc(count ? count : 1, size);
    Allocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    *record = (Allocation){value, allocations};
    allocations = record;
    return value;
}
void release_all(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1, 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
void release_one(void *value) {
    Allocation **current = &allocations;
    while (*current && (*current)->value != value)
        current = &(*current)->next;
    if (*current) {
        Allocation *record = *current;
        *current = record->next;
        free(record->value);
        free(record);
    }
}
Values values_new(int count) {
    return (Values){allocate(count, sizeof(double)), count};
}
Complexes complex_new(int count) {
    return (Complexes){allocate(count, sizeof(Complex)), count};
}
Complexes complex_values(Values values, int length) {
    if (length < 0)
        length = values.count;
    Complexes out = complex_new(length);
    for (int i = 0; i < values.count; ++i)
        out.data[i] = values.data[i];
    return out;
}
static char *read_line(FILE *input) {
    int capacity = 128, count = 0;
    char *data = allocate(capacity, 1);
    int ch;
    while ((ch = fgetc(input)) != EOF && ch != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            char *replacement = allocate(capacity, 1);
            memcpy(replacement, data, count);
            data = replacement;
        }
        data[count++] = (char)ch;
    }
    return ch == EOF && count == 0 ? NULL : data;
}
typedef struct {
    char **data;
    int count;
} Tokens;
static Tokens tokens(char *text) {
    Tokens out = {.data = allocate(strlen(text) + 1, sizeof(char *))};
    for (char *word = strtok(text, " "); word; word = strtok(NULL, " "))
        out.data[out.count++] = word;
    return out;
}
Input load(void) {
    Input out = {0};
    FILE *signal = fopen("input/signal.csv", "r");
    int count;
    fscanf(signal, "%d,%d", &out.fs, &count);
    out.signal[0] = values_new(count);
    out.signal[1] = values_new(count);
    for (int i = 0; i < count; ++i)
        fscanf(signal, " %lf,%lf", &out.signal[0].data[i], &out.signal[1].data[i]);
    fclose(signal);
    FILE *settings = fopen("input/params.txt", "r");
    Tokens rows[18];
    for (int i = 0; i < 18; ++i)
        rows[i] = tokens(read_line(settings));
    fclose(settings);
    Params *p = &out.params;
    p->main_length = atoi(rows[0].data[1]);
    p->main_window = rows[1].data[1];
    p->peak_threshold = strtod(rows[2].data[1], NULL);
    p->peak_count = atoi(rows[3].data[1]);
    p->fundamental = strtod(rows[4].data[1], NULL);
    p->search = atoi(rows[4].data[2]);
    p->welch_length = atoi(rows[5].data[1]);
    p->welch_window = rows[5].data[2];
    p->frame_length = atoi(rows[6].data[1]);
    p->hop = atoi(rows[6].data[2]);
    p->shade = atoi(rows[6].data[3]);
    p->frame_window = rows[6].data[4];
    p->onset_factor = strtod(rows[7].data[1], NULL);
    p->pitch_low = atoi(rows[8].data[1]);
    p->pitch_high = atoi(rows[8].data[2]);
    p->band_low = atoi(rows[9].data[1]);
    p->band_high = atoi(rows[9].data[2]);
    p->notch_frequency = atoi(rows[10].data[1]);
    p->notch_width = atoi(rows[10].data[2]);
    p->envelope_low = atoi(rows[11].data[1]);
    p->envelope_high = atoi(rows[11].data[2]);
    p->zoom_low = atoi(rows[12].data[1]);
    p->zoom_high = atoi(rows[12].data[2]);
    p->zoom_points = atoi(rows[12].data[3]);
    p->fir = values_new(rows[13].count - 1);
    for (int i = 0; i < p->fir.count; ++i)
        p->fir.data[i] = strtod(rows[13].data[i + 1], NULL);
    p->max_lag = atoi(rows[14].data[1]);
    p->bands = (Ids){allocate(rows[15].count - 1, sizeof(int)), rows[15].count - 1};
    for (int i = 0; i < p->bands.count; ++i)
        p->bands.data[i] = atoi(rows[15].data[i + 1]);
    p->third_low = atoi(rows[16].data[1]);
    p->third_high = atoi(rows[16].data[2]);
    p->block_length = atoi(rows[17].data[1]);
    return out;
}
