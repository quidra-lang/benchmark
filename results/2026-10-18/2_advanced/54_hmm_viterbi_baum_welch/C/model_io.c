#include "hmm.h"
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
void line(Lines *lines, const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *text = allocate((size_t)length + 1, 1);
    vsnprintf(text, (size_t)length + 1, pattern, args);
    va_end(args);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? lines->capacity * 2 : 32;
        char **values = allocate(capacity, sizeof(char *));
        if (lines->count)
            memcpy(values, lines->data, lines->count * sizeof(char *));
        lines->data = values;
        lines->capacity = capacity;
    }
    lines->data[lines->count++] = text;
}
void *allocation_mark(void) {
    return allocations;
}
void release_to(void *mark) {
    while (allocations != (Allocation *)mark) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
Path path_new(int count) {
    return (Path){allocate(count, sizeof(int)), count};
}
void extend(Lines *target, Lines values) {
    for (int i = 0; i < values.count; ++i)
        line(target, "%s", values.data[i]);
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
static Rows read_rows(const char *name) {
    FILE *input = fopen(format("input/%s", name), "r");
    Rows out = {.data = allocate(100, sizeof(Tokens))};
    char *text;
    while ((text = read_line(input)) != NULL) {
        Tokens row = {.data = allocate(strlen(text) + 1, sizeof(char *))};
        for (char *token = strtok(text, " "); token; token = strtok(NULL, " "))
            row.data[row.count++] = token;
        out.data[out.count++] = row;
    }
    fclose(input);
    return out;
}
void normalize(double *values, int count) {
    double sum = 0;
    for (int i = 0; i < count; ++i)
        sum += values[i];
    for (int i = 0; i < count; ++i)
        values[i] /= sum;
}
void load(Input *out) {
    Rows rows = read_rows("model.txt");
    Model *model = &out->model;
    model->name = "INITIAL";
    model->k = rows.data[0].count - 1;
    model->m = rows.data[1].count - 1;
    for (int i = 0; i < model->k; ++i)
        model->states[i] = rows.data[0].data[i + 1][0];
    for (int i = 0; i < model->m; ++i)
        model->symbols[i] = rows.data[1].data[i + 1][0];
    model->missing = rows.data[2].data[1][0];
    for (int i = 0; i < model->k; ++i)
        model->initial[i] = strtod(rows.data[3].data[i + 1], NULL);
    normalize(model->initial, model->k);
    for (int i = 0; i < model->k; ++i) {
        for (int j = 0; j < model->k; ++j)
            model->transition[i][j] = strtod(rows.data[4 + i].data[j + 2], NULL);
        normalize(model->transition[i], model->k);
        for (int j = 0; j < model->m; ++j)
            model->emission[i][j] = strtod(rows.data[4 + model->k + i].data[j + 2], NULL);
        normalize(model->emission[i], model->m);
    }
    out->sequences = read_rows("sequences.txt");
    out->labeled = read_rows("labeled.txt");
    out->parameters = read_rows("params.txt");
}
char *real(double value, int places) {
    I factor = 1;
    for (int i = 0; i < places; ++i)
        factor *= 10;
    I amount = (I)floor(fabs(value) * (double)factor + 0.5);
    return format("%s%" PRId64 ".%0*" PRId64, value < 0 && amount ? "-" : "", amount / factor, places,
                  amount % factor);
}
Lines model_lines(Model model) {
    Lines out = {0};
    line(&out, "MODEL %s", model.name);
    char states[16] = "STATES", symbols[32] = "SYMBOLS";
    size_t offset = strlen(states);
    for (int i = 0; i < model.k; ++i) {
        states[offset++] = ' ';
        states[offset++] = model.states[i];
    }
    states[offset] = 0;
    offset = strlen(symbols);
    for (int i = 0; i < model.m; ++i) {
        symbols[offset++] = ' ';
        symbols[offset++] = model.symbols[i];
    }
    symbols[offset] = 0;
    line(&out, "%s", states);
    line(&out, "%s", symbols);
    line(&out, "MISSING %c", model.missing);
    char *initial = "INITIAL";
    for (int i = 0; i < model.k; ++i)
        initial = format("%s %s", initial, real(model.initial[i], 4));
    line(&out, "%s", initial);
    for (int i = 0; i < model.k; ++i) {
        char *row = format("TRANSITION %c", model.states[i]);
        for (int j = 0; j < model.k; ++j)
            row = format("%s %s", row, real(model.transition[i][j], 4));
        line(&out, "%s", row);
    }
    for (int i = 0; i < model.k; ++i) {
        char *row = format("EMISSION %c", model.states[i]);
        for (int j = 0; j < model.m; ++j)
            row = format("%s %s", row, real(model.emission[i][j], 4));
        line(&out, "%s", row);
    }
    return out;
}
void save(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "w");
    for (int i = 0; i < lines.count; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
