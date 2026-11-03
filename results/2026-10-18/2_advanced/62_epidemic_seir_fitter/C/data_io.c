#include "epidemic.h"
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
Input *load(void) {
    Input *out = allocate(1, sizeof(Input));
    Lines cases = read_lines("input/cases.csv");
    for (int i = 1; i < cases.count; ++i) {
        int day;
        sscanf(cases.data[i], "%d,%lld,%lld", &day, &out->cases[out->days],
               &out->deaths[out->days]);
        ++out->days;
    }
    Lines population = read_lines("input/population.txt");
    int row_index = 0;
    for (int i = 0; i < population.count; ++i) {
        if (strncmp(population.data[i], "group ", 6) == 0) {
            Group *group = &out->groups[out->group_count++];
            sscanf(population.data[i], "group %12s %lld %lf", group->name, &group->population,
                   &group->fatality);
        } else {
            const char *text = population.data[i] + 8;
            int offset = 0, used;
            for (int j = 0; j < out->group_count; ++j) {
                sscanf(text + offset, "%lf %n", &out->contacts[row_index][j], &used);
                offset += used;
            }
            ++row_index;
        }
    }
    Lines interventions = read_lines("input/interventions.txt");
    for (int i = 0; i < interventions.count; ++i) {
        Intervention *item = &out->interventions[out->intervention_count++];
        sscanf(interventions.data[i], "%d %lf", &item->day, &item->multiplier);
    }
    Lines settings = read_lines("input/params.txt");
    Params *p = &out->params;
    for (int i = 0; i < settings.count; ++i) {
        char key[32];
        sscanf(settings.data[i], "%31s", key);
        const char *value = settings.data[i] + strlen(key) + 1;
        if (strcmp(key, "sigma") == 0)
            sscanf(value, "%lf", &p->sigma);
        else if (strcmp(key, "gamma") == 0)
            sscanf(value, "%lf", &p->gamma);
        else if (strcmp(key, "initial") == 0)
            sscanf(value, "%lf %lf", &p->e0, &p->i0);
        else if (strcmp(key, "beta_grid") == 0)
            sscanf(value, "%lf %lf %d", &p->beta_min, &p->beta_max, &p->beta_count);
        else if (strcmp(key, "rho_grid") == 0)
            sscanf(value, "%lf %lf %d", &p->rho_min, &p->rho_max, &p->rho_count);
        else if (strcmp(key, "golden") == 0)
            sscanf(value, "%d %d", &p->golden, &p->rounds);
        else if (strcmp(key, "simplex") == 0)
            sscanf(value, "%lf %lf", &p->delta_beta, &p->delta_gamma);
        else if (strcmp(key, "nelder_mead") == 0)
            sscanf(value, "%lf %lf %lf %lf %d", &p->alpha, &p->chi, &p->psi, &p->omega, &p->nelder);
        else if (strcmp(key, "holdout") == 0)
            sscanf(value, "%d", &p->holdout);
        else if (strcmp(key, "effect_width") == 0)
            sscanf(value, "%lf", &p->effect_width);
        else if (strcmp(key, "outlier") == 0)
            sscanf(value, "%lf", &p->outlier);
        else if (strcmp(key, "death_lag") == 0)
            sscanf(value, "%d", &p->death_lag);
        else if (strcmp(key, "milestones") == 0) {
            int offset = 0, used;
            I target;
            while (sscanf(value + offset, "%lld %n", &target, &used) == 1) {
                p->milestones[p->milestone_count++] = target;
                offset += used;
            }
        } else if (strcmp(key, "generation") == 0)
            sscanf(value, "%d", &p->generation);
        else if (strcmp(key, "horizon") == 0)
            sscanf(value, "%d", &p->horizon);
        else if (strcmp(key, "threshold") == 0)
            sscanf(value, "%lf", &p->threshold);
        else if (strcmp(key, "scenario") == 0) {
            Scenario *scenario = &p->scenarios[p->scenario_count++];
            sscanf(value, "%12s %lf", scenario->name, &scenario->multiplier);
        } else if (strcmp(key, "contact_change") == 0) {
            ContactChange *change = &p->changes[p->change_count++];
            sscanf(value, "%12s %12s %lf", change->name, change->group, &change->factor);
        }
    }
    return out;
}
void save(const char *name, Lines lines) {
    mkdir("output", 0777);
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
