#include "mixture.h"
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
typedef struct {
    char **data;
    int count;
} Tokens;
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
static Tokens tokens(char *line) {
    Tokens out = {.data = allocate(strlen(line) + 1, sizeof(char *))};
    for (char *token = strtok(line, " "); token; token = strtok(NULL, " "))
        out.data[out.count++] = token;
    return out;
}
const char *type_name(Type type) {
    static const char *names[] = {"FULL", "TIED", "DIAG", "SPHERICAL"};
    return names[type];
}
static Type parse_type(const char *name) {
    for (int i = 0; i < 4; ++i)
        if (!strcmp(name, type_name((Type)i)))
            return (Type)i;
    return FULL;
}
void load(Input *out) {
    FILE *input = fopen("input/points.csv", "r");
    read_line(input);
    char *row;
    while ((row = read_line(input)) != NULL) {
        Point *point = &out->points[out->count++];
        sscanf(row, "%8[^,],%lf,%lf", point->id, &point->xy.x, &point->xy.y);
    }
    fclose(input);
    input = fopen("input/params.txt", "r");
    Params *p = &out->params;
    Tokens fields = tokens(read_line(input));
    for (int i = 1; i < fields.count; ++i)
        p->ks[p->k_count++] = atoi(fields.data[i]);
    fields = tokens(read_line(input));
    p->iterations = atoi(fields.data[1]);
    fields = tokens(read_line(input));
    for (int i = 1; i < fields.count; ++i)
        p->types[p->type_count++] = parse_type(fields.data[i]);
    fields = tokens(read_line(input));
    p->epsilon = strtod(fields.data[1], NULL);
    fields = tokens(read_line(input));
    p->tolerance = strtod(fields.data[1], NULL);
    fields = tokens(read_line(input));
    p->kmeans_max = atoi(fields.data[1]);
    fields = tokens(read_line(input));
    p->folds = atoi(fields.data[1]);
    fields = tokens(read_line(input));
    p->uncertain = strtod(fields.data[1], NULL);
    fields = tokens(read_line(input));
    p->low_density = strtod(fields.data[1], NULL);
    fields = tokens(read_line(input));
    p->gof_count = fields.count - 1;
    p->gof = allocate(p->gof_count, sizeof(double));
    for (int i = 0; i < p->gof_count; ++i)
        p->gof[i] = strtod(fields.data[i + 1], NULL);
    fields = tokens(read_line(input));
    p->xmin = strtod(fields.data[1], NULL);
    p->xmax = strtod(fields.data[2], NULL);
    fields = tokens(read_line(input));
    p->ymin = strtod(fields.data[1], NULL);
    p->ymax = strtod(fields.data[2], NULL);
    fields = tokens(read_line(input));
    p->width = atoi(fields.data[1]);
    p->height = atoi(fields.data[2]);
    fclose(input);
    input = fopen("input/init.txt", "r");
    char key[16];
    int k;
    while (fscanf(input, "%15s %d", key, &k) == 2) {
        Model model = {.k = k};
        fscanf(input, "%15s", key);
        for (int j = 0; j < k; ++j) {
            double weight;
            fscanf(input, "%lf", &weight);
            if (j < 4)
                model.components[j].weight = weight;
        }
        for (int j = 0; j < k; ++j) {
            int number;
            Component component = {0};
            fscanf(input, "%15s %d %lf %lf %lf %lf %lf", key, &number, &component.mean.x, &component.mean.y,
                   &component.cov.a, &component.cov.b, &component.cov.c);
            if (j < 4) {
                component.weight = model.components[j].weight;
                model.components[j] = component;
            }
        }
        if (k >= 1 && k <= 4)
            out->initial[k] = model;
    }
    fclose(input);
}
