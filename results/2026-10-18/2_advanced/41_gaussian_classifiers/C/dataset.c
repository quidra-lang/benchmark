#include "gaussian.h"
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
void double_push(DoubleList *list, double value) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof(double));
    }
    list->data[list->count++] = value;
}
void row_push(Rows *rows, Row row) {
    if (rows->count == rows->capacity) {
        rows->capacity = rows->capacity ? 2 * rows->capacity : 16;
        rows->data = resize(rows->data, (size_t)rows->capacity * sizeof(Row));
    }
    rows->data[rows->count++] = row;
}
static Lines read_lines(const char *path) {
    Lines out = {0};
    FILE *file = fopen(path, "rb");
    if (!file)
        return out;
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
static Lines split(const char *value, char delimiter) {
    Lines out = {0};
    const char *first = value;
    while (true) {
        const char *end = strchr(first, delimiter);
        size_t length = end ? (size_t)(end - first) : strlen(first);
        char *part = resize(NULL, length + 1);
        memcpy(part, first, length);
        part[length] = 0;
        line_push(&out, part);
        if (!end)
            break;
        first = end + 1;
    }
    return out;
}
static int string_compare(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}
static int name_index(const Lines *names, const char *value) {
    for (int i = 0; i < names->count; ++i)
        if (!strcmp(names->data[i], value))
            return i;
    return -1;
}
static Rows parse_rows(const Lines *lines, const Dataset *data) {
    Rows out = {0};
    for (int i = 1; i < lines->count; ++i) {
        Lines fields = split(lines->data[i], ',');
        Row row = {.id = atoi(fields.data[0]),
                   .label = name_index(&data->classes, fields.data[fields.count - 1])};
        for (int j = 0; j < data->features.count; ++j)
            row.values.v[j] = strtod(fields.data[j + 1], NULL);
        row_push(&out, row);
        lines_free(&fields);
    }
    return out;
}
Dataset *read_dataset(void) {
    Dataset *out = calloc(1, sizeof(Dataset));
    out->params.empirical = true;
    Lines training = read_lines("input/train.csv"), header = split(training.data[0], ',');
    for (int i = 1; i < header.count - 1; ++i)
        line_push(&out->features, text(header.data[i]));
    for (int i = 1; i < training.count; ++i) {
        Lines fields = split(training.data[i], ',');
        const char *label = fields.data[fields.count - 1];
        if (name_index(&out->classes, label) < 0)
            line_push(&out->classes, text(label));
        lines_free(&fields);
    }
    qsort(out->classes.data, (size_t)out->classes.count, sizeof(char *), string_compare);
    out->train = parse_rows(&training, out);
    Lines testing = read_lines("input/test.csv");
    out->test = parse_rows(&testing, out);
    lines_free(&testing);
    lines_free(&training);
    lines_free(&header);
    Lines costs = read_lines("input/costs.csv"), cost_header = split(costs.data[0], ',');
    for (int i = 1; i < costs.count; ++i) {
        Lines fields = split(costs.data[i], ',');
        int actual = name_index(&out->classes, fields.data[0]);
        for (int j = 1; j < fields.count; ++j)
            out->costs[actual][name_index(&out->classes, cost_header.data[j])] = strtod(fields.data[j], NULL);
        lines_free(&fields);
    }
    lines_free(&costs);
    lines_free(&cost_header);
    Lines settings = read_lines("input/params.txt");
    for (int line = 0; line < settings.count; ++line) {
        Lines fields = split(settings.data[line], ' ');
        const char *name = fields.data[0];
        if (!strcmp(name, "PRIOR"))
            out->params.empirical = !strcmp(fields.data[1], "empirical");
        else if (!strcmp(name, "VAR_SMOOTHING"))
            out->params.smoothing = strtod(fields.data[1], NULL);
        else if (!strcmp(name, "QDA_GAMMA"))
            out->params.gamma = strtod(fields.data[1], NULL);
        else if (!strcmp(name, "CV_FOLDS"))
            out->params.folds = atoi(fields.data[1]);
        else if (!strcmp(name, "OUTLIER_THRESHOLD"))
            out->params.outlier = strtod(fields.data[1], NULL);
        else if (!strcmp(name, "SMOOTHING_GRID") || !strcmp(name, "GAMMA_GRID") ||
                 !strcmp(name, "CALIBRATION_EDGES") || !strcmp(name, "REJECT_THRESHOLDS")) {
            DoubleList *list = !strcmp(name, "SMOOTHING_GRID")      ? &out->params.smoothing_grid
                               : !strcmp(name, "GAMMA_GRID")        ? &out->params.gamma_grid
                               : !strcmp(name, "CALIBRATION_EDGES") ? &out->params.calibration
                                                                    : &out->params.reject;
            for (int i = 1; i < fields.count; ++i)
                double_push(list, strtod(fields.data[i], NULL));
        } else if (!strcmp(name, "CURVE")) {
            for (int i = 1; i < fields.count; ++i)
                int_push(&out->params.curve, atoi(fields.data[i]));
        } else if (!strcmp(name, "BOOTSTRAP")) {
            out->params.bootstrap = atoi(fields.data[1]);
            out->params.seed = strtoll(fields.data[2], NULL, 10);
        } else if (!strcmp(name, "MAP_SIZE")) {
            out->params.map_width = atoi(fields.data[1]);
            out->params.map_height = atoi(fields.data[2]);
        } else if (!strcmp(name, "PLOT_SIZE")) {
            out->params.plot_width = atoi(fields.data[1]);
            out->params.plot_height = atoi(fields.data[2]);
        } else if (!strcmp(name, "SUBSET")) {
            Subset subset = {.name = text(fields.data[1])};
            for (int i = 2; i < fields.count; ++i)
                subset.features.v[subset.features.count++] = name_index(&out->features, fields.data[i]);
            out->params.subsets =
                resize(out->params.subsets, (size_t)(out->params.subset_count + 1) * sizeof(Subset));
            out->params.subsets[out->params.subset_count++] = subset;
        } else if (!strcmp(name, "PAIR")) {
            Pair pair = {name_index(&out->features, fields.data[1]),
                         name_index(&out->features, fields.data[2])};
            out->params.pairs =
                resize(out->params.pairs, (size_t)(out->params.pair_count + 1) * sizeof(Pair));
            out->params.pairs[out->params.pair_count++] = pair;
        }
        lines_free(&fields);
    }
    lines_free(&settings);
    return out;
}
