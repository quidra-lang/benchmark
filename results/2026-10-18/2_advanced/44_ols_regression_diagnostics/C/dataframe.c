#include "regression.h"
#include <stdarg.h>
void *resize(void *memory, size_t size) {
    void *out = realloc(memory, size ? size : 1);
    if (!out)
        exit(1);
    return out;
}
char *text(const char *value) {
    char *out = resize(NULL, strlen(value) + 1);
    strcpy(out, value);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = resize(NULL, (size_t)length + 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    va_end(args);
    return out;
}
void line_push(Lines *lines, char *line) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 16;
        lines->data = resize(lines->data, (size_t)lines->capacity * sizeof(char *));
    }
    lines->data[lines->count++] = line;
}
void lines_extend(Lines *target, const Lines *source) {
    for (int i = 0; i < source->count; ++i)
        line_push(target, text(source->data[i]));
}
void lines_free(Lines *lines) {
    for (int i = 0; i < lines->count; ++i)
        free(lines->data[i]);
    free(lines->data);
    *lines = (Lines){0};
}
void int_push(IntList *list, int value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof(int));
    }
    list->data[list->count++] = value;
}
bool int_contains(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->data[i] == value)
            return true;
    return false;
}
static int int_compare(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
void int_sort(IntList *list) {
    if (list->count > 1)
        qsort(list->data, (size_t)list->count, sizeof(int), int_compare);
}
Vector vector_new(int count) {
    return (Vector){calloc((size_t)count, sizeof(double)), count};
}
Matrix matrix_new(int rows, int columns) {
    return (Matrix){calloc((size_t)rows * (size_t)columns, sizeof(double)), rows, columns};
}
static Lines read_lines(const char *path) {
    Lines out = {0};
    FILE *file = fopen(path, "rb");
    char *buffer = NULL;
    size_t length = 0, capacity = 0;
    int character;
    while ((character = fgetc(file)) != EOF) {
        if (character == '\n') {
            if (length + 1 > capacity)
                buffer = resize(buffer, length + 1);
            buffer[length] = 0;
            line_push(&out, text(buffer));
            length = 0;
        } else {
            if (length + 1 >= capacity) {
                capacity = capacity ? 2 * capacity : 128;
                buffer = resize(buffer, capacity);
            }
            buffer[length++] = (char)character;
        }
    }
    free(buffer);
    fclose(file);
    return out;
}
static Lines split(const char *line, char delimiter) {
    Lines out = {0};
    const char *first = line;
    while (true) {
        const char *end = strchr(first, delimiter);
        size_t length = end ? (size_t)(end - first) : strlen(first);
        char *value = resize(NULL, length + 1);
        memcpy(value, first, length);
        value[length] = 0;
        line_push(&out, value);
        if (!end)
            break;
        first = end + 1;
    }
    return out;
}
Input *read_input(void) {
    Input *out = calloc(1, sizeof(Input));
    Lines lines = read_lines("input/data.csv");
    out->data.names = split(lines.data[0], ',');
    out->data.count = lines.count - 1;
    out->data.rows = calloc((size_t)out->data.count, sizeof(Record));
    for (int i = 1; i < lines.count; ++i) {
        Lines fields = split(lines.data[i], ',');
        for (int j = 0; j < fields.count; ++j) {
            Cell *cell = &out->data.rows[i - 1].cells[j];
            cell->missing = !strcmp(fields.data[j], "NA");
            if (cell->missing)
                continue;
            if (fields.data[j][0] >= 'A' && fields.data[j][0] <= 'Z') {
                cell->label = text(fields.data[j]);
                out->data.categorical[j] = true;
            } else
                cell->number = strtod(fields.data[j], NULL);
        }
        lines_free(&fields);
    }
    lines_free(&lines);
    lines = read_lines("input/predict.csv");
    Lines header = split(lines.data[0], ',');
    int mapping[12];
    for (int i = 0; i < header.count; ++i) {
        mapping[i] = 0;
        while (strcmp(out->data.names.data[mapping[i]], header.data[i]))
            ++mapping[i];
    }
    out->prediction.count = lines.count - 1;
    out->prediction.rows = calloc((size_t)out->prediction.count, sizeof(Record));
    for (int i = 1; i < lines.count; ++i) {
        Record *record = &out->prediction.rows[i - 1];
        for (int j = 0; j < out->data.names.count; ++j)
            record->cells[j].missing = true;
        Lines fields = split(lines.data[i], ',');
        for (int j = 0; j < fields.count; ++j) {
            Cell *cell = &record->cells[mapping[j]];
            if (!strcmp(fields.data[j], "NA"))
                continue;
            cell->missing = false;
            if (out->data.categorical[mapping[j]])
                cell->label = text(fields.data[j]);
            else
                cell->number = strtod(fields.data[j], NULL);
        }
        lines_free(&fields);
    }
    lines_free(&header);
    lines_free(&lines);
    out->formulas = read_lines("input/model.txt");
    lines = read_lines("input/params.txt");
    for (int i = 0; i < lines.count; ++i) {
        Lines fields = split(lines.data[i], ' ');
        const char *key = fields.data[0];
        double value = strtod(fields.data[1], NULL);
        if (!strcmp(key, "RANK_TOL"))
            out->params.rank_tol = value;
        else if (!strcmp(key, "ALPHA_REMOVE"))
            out->params.alpha = value;
        else if (!strcmp(key, "CONFIDENCE"))
            out->params.confidence = value;
        else if (!strcmp(key, "LEVERAGE"))
            out->params.leverage = value;
        else if (!strcmp(key, "STUDENTIZED"))
            out->params.studentized = value;
        else if (!strcmp(key, "COOK"))
            out->params.cook = value;
        else if (!strcmp(key, "DFFITS"))
            out->params.dffits = value;
        else if (!strcmp(key, "VIF"))
            out->params.vif = value;
        else if (!strcmp(key, "DURBIN_WATSON"))
            out->params.durbin = value;
        else if (!strcmp(key, "BREUSCH_PAGAN"))
            out->params.breusch = value;
        else if (!strcmp(key, "NORMALITY"))
            out->params.normality = value;
        else if (!strcmp(key, "BEST_SUBSETS"))
            out->params.best_subsets = (int)value;
        else if (!strcmp(key, "PLOT")) {
            out->params.plot_width = (int)value;
            out->params.plot_height = atoi(fields.data[2]);
            out->params.plot_limit = strtod(fields.data[3], NULL);
        }
        lines_free(&fields);
    }
    lines_free(&lines);
    return out;
}
