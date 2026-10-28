#include "regression.h"
static char *read_line(FILE *file) {
    size_t length = 0, capacity = 128;
    char *text = malloc(capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            text = realloc(text, capacity);
        }
        text[length++] = (char)c;
    }
    if (c == EOF && !length) {
        free(text);
        return NULL;
    }
    text[length] = 0;
    return text;
}
Table read_table(const char *name) {
    Table table = {0};
    char path[128];
    snprintf(path, sizeof path, "input/%s", name);
    FILE *file = fopen(path, "r");
    char *line = read_line(file);
    for (const char *cursor = line; *cursor; ++cursor)
        if (*cursor == ',')
            ++table.features;
    --table.features;
    int column = 0;
    for (char *field = strtok(line, ","); field; field = strtok(NULL, ",")) {
        if (column >= 1 && column <= table.features)
            strcpy(table.names[column - 1], field);
        ++column;
    }
    free(line);
    while ((line = read_line(file))) {
        Row *row = &table.rows[table.count++];
        char *field = strtok(line, ",");
        strcpy(row->id, field);
        for (int j = 0; j < table.features; ++j) {
            field = strtok(NULL, ",");
            row->values[j] = strtod(field, NULL);
        }
        row->label = atoi(strtok(NULL, ","));
        free(line);
    }
    fclose(file);
    return table;
}
Params read_params(void) {
    Params p = {0};
    FILE *file = fopen("input/params.txt", "r");
    char *line;
    int row = 0;
    while ((line = read_line(file))) {
        char *keyword = strtok(line, " "), *value = strtok(NULL, " ");
        (void)keyword;
        switch (row++) {
        case 0:
            p.positive = atoi(value);
            break;
        case 1:
            p.degree = atoi(value);
            break;
        case 2:
            p.threshold = strtod(value, NULL);
            break;
        case 3:
            do {
                p.lambdas[p.lambda_count++] = strtod(value, NULL);
            } while ((value = strtok(NULL, " ")));
            break;
        case 4:
            p.gd_rate = strtod(value, NULL);
            p.gd_iterations = atoi(strtok(NULL, " "));
            break;
        case 5:
            p.sgd_rate = strtod(value, NULL);
            p.batch = atoi(strtok(NULL, " "));
            p.epochs = atoi(strtok(NULL, " "));
            p.sgd_seed = strtoll(strtok(NULL, " "), NULL, 10);
            break;
        case 6:
            p.softmax_rate = strtod(value, NULL);
            p.softmax_iterations = atoi(strtok(NULL, " "));
            p.softmax_lambda = strtod(strtok(NULL, " "), NULL);
            break;
        case 7:
            p.bootstrap = atoi(value);
            p.bootstrap_seed = strtoll(strtok(NULL, " "), NULL, 10);
            break;
        case 8:
            p.permutations = atoi(value);
            p.permutation_seed = strtoll(strtok(NULL, " "), NULL, 10);
            break;
        case 9:
            p.width = atoi(value);
            p.height = atoi(strtok(NULL, " "));
            break;
        case 10:
            p.fp_cost = atoi(value);
            p.fn_cost = atoi(strtok(NULL, " "));
            break;
        }
        free(line);
    }
    fclose(file);
    return p;
}
static void visit_features(const Table *table, int remaining, int first, int depth, int *tuple,
                           Features *features) {
    if (!remaining) {
        Feature *feature = &features->values[features->count++];
        feature->degree = depth;
        for (int i = 0; i < depth; ++i) {
            feature->indices[i] = tuple[i];
            if (i)
                strcat(feature->name, "*");
            strcat(feature->name, table->names[tuple[i]]);
        }
        return;
    }
    for (int index = first; index < table->features; ++index) {
        tuple[depth] = index;
        visit_features(table, remaining - 1, index, depth + 1, tuple, features);
    }
}
Features build_features(const Table *table, int degree) {
    Features result = {0};
    int tuple[3];
    for (int k = 1; k <= degree; ++k)
        visit_features(table, k, 0, 0, tuple, &result);
    return result;
}
Vector expand(const double *values, const Features *features) {
    Vector result = {.count = features->count};
    for (int j = 0; j < features->count; ++j) {
        Feature feature = features->values[j];
        double value = values[feature.indices[0]];
        for (int i = 1; i < feature.degree; ++i)
            value *= values[feature.indices[i]];
        result.values[j] = value;
    }
    return result;
}
Matrix expanded(const Table *rows, const Features *features) {
    Matrix result = {.rows = rows->count, .columns = features->count};
    for (int i = 0; i < rows->count; ++i) {
        Vector vector = expand(rows->rows[i].values, features);
        memcpy(result.values[i], vector.values, (size_t)vector.count * sizeof(double));
    }
    return result;
}
Statistics statistics(const Matrix *data, int count) {
    Statistics result = {.count = count};
    for (int j = 0; j < count; ++j) {
        double total = 0;
        for (int i = 0; i < data->rows; ++i)
            total += data->values[i][j];
        result.mean[j] = total / (double)data->rows;
        double squares = 0;
        for (int i = 0; i < data->rows; ++i) {
            double delta = data->values[i][j] - result.mean[j];
            squares += delta * delta;
        }
        result.deviation[j] = sqrt(squares / (double)(data->rows - 1));
    }
    return result;
}
Vector standardize_point(Vector row, const Statistics *stats, int count) {
    Vector result = {.count = count + 1};
    result.values[0] = 1;
    for (int j = 0; j < count; ++j)
        result.values[j + 1] = (row.values[j] - stats->mean[j]) / stats->deviation[j];
    return result;
}
Matrix standardize(const Matrix *rows, const Statistics *stats, int count) {
    Matrix result = {.rows = rows->rows, .columns = count + 1};
    for (int i = 0; i < rows->rows; ++i) {
        result.values[i][0] = 1;
        for (int j = 0; j < count; ++j)
            result.values[i][j + 1] = (rows->values[i][j] - stats->mean[j]) / stats->deviation[j];
    }
    return result;
}
Targets labels(const Table *rows, int positive) {
    Targets result = {.count = rows->count};
    for (int i = 0; i < rows->count; ++i)
        result.values[i] = positive < 0 ? rows->rows[i].label : rows->rows[i].label == positive;
    return result;
}
