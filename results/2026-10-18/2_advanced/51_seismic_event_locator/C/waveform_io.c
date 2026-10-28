#include "seismic.h"
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
void load(Station *stations, int *count, Params *p) {
    FILE *input = fopen("input/stations.csv", "r");
    char line[256];
    fgets(line, sizeof(line), input);
    while (fgets(line, sizeof(line), input)) {
        Station *s = &stations[(*count)++];
        sscanf(line, "%8[^,],%" SCNd64 ",%" SCNd64 ",%" SCNd64, s->code, &s->x, &s->y, &s->elevation);
    }
    fclose(input);
    input = fopen("input/waveforms.txt", "r");
    for (int i = 0; i < *count; ++i) {
        Station *s = &stations[i];
        char marker[16], code[9];
        fscanf(input, "%15s %8s %" SCNd64 " %d", marker, code, &s->start, &s->count);
        s->samples = allocate(s->count, sizeof(I));
        for (int j = 0; j < s->count; ++j)
            fscanf(input, "%" SCNd64, &s->samples[j]);
    }
    fclose(input);
    input = fopen("input/params.txt", "r");
    char key[64];
    I *integers[] = {&p->sw,           &p->lw,    &p->on_p, &p->on_q, &p->off_p,  &p->off_q,
                     &p->min_duration, &p->noise, &p->aw,   &p->clip, &p->window, &p->minimum};
    int sizes[] = {1, 1, 2, 2, 1, 1, 1, 1, 1, 1};
    int offset = 0;
    for (int line_number = 0; line_number < 10; ++line_number) {
        fscanf(input, "%63s", key);
        for (int j = 0; j < sizes[line_number]; ++j)
            fscanf(input, "%" SCNd64, integers[offset++]);
    }
    fscanf(input, "%63s %lf", key, &p->velocity);
    I *grids[] = {p->gx, p->gy, p->gz};
    for (int i = 0; i < 3; ++i) {
        fscanf(input, "%63s", key);
        for (int j = 0; j < 3; ++j)
            fscanf(input, "%" SCNd64, &grids[i][j]);
    }
    fscanf(input, "%63s %lf", key, &p->limit);
    double *real_groups[] = {p->qa, p->qb, p->cluster, p->local, p->duration};
    for (int i = 0; i < 5; ++i) {
        fscanf(input, "%63s", key);
        for (int j = 0; j < (i == 2 ? 2 : 3); ++j)
            fscanf(input, "%lf", &real_groups[i][j]);
    }
    I *groups[] = {p->area, p->map_size, p->section, p->timeline};
    const int lengths[] = {4, 2, 2, 5};
    for (int i = 0; i < 4; ++i) {
        fscanf(input, "%63s", key);
        for (int j = 0; j < lengths[i]; ++j)
            fscanf(input, "%" SCNd64, &groups[i][j]);
    }
    fclose(input);
}
