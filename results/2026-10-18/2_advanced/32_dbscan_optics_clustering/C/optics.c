#include "clustering.h"
static int integer_compare(const void *a, const void *b) {
    Integer x = *(const Integer *)a, y = *(const Integer *)b;
    return (x > y) - (x < y);
}
Optics optics(const Grid *grid, const Distances *distances, int min_points) {
    int n = grid->count;
    Optics result = {.count = n};
    result.core = malloc((size_t)n * sizeof *result.core);
    result.reach = malloc((size_t)n * sizeof *result.reach);
    result.predecessor = malloc((size_t)n * sizeof *result.predecessor);
    result.order = malloc((size_t)n * sizeof *result.order);
    bool *processed = calloc((size_t)n, sizeof *processed), *seeds = calloc((size_t)n, sizeof *seeds);
    for (int p = 0; p < n; ++p) {
        result.core[p] = result.reach[p] = DISTANCE_INF;
        result.predecessor[p] = -1;
        if (grid->neighbors[p].count >= min_points) {
            int count = grid->neighbors[p].count;
            Integer *values = malloc((size_t)count * sizeof *values);
            for (int i = 0; i < count; ++i)
                values[i] = at(distances, p, grid->neighbors[p].values[i]);
            qsort(values, (size_t)count, sizeof *values, integer_compare);
            result.core[p] = values[min_points - 1];
            free(values);
        }
    }
    int position = 0;
    for (int t = 0; t < n; ++t) {
        if (processed[t])
            continue;
        seeds[t] = true;
        for (;;) {
            int p = -1;
            for (int q = 0; q < n; ++q)
                if (seeds[q] && (p < 0 || result.reach[q] < result.reach[p] ||
                                 (result.reach[q] == result.reach[p] && q < p)))
                    p = q;
            if (p < 0)
                break;
            seeds[p] = false;
            processed[p] = true;
            result.order[position++] = p;
            if (result.core[p] == DISTANCE_INF)
                continue;
            for (int i = 0; i < grid->neighbors[p].count; ++i) {
                int q = grid->neighbors[p].values[i];
                if (processed[q])
                    continue;
                Integer squared = at(distances, p, q),
                        reach = result.core[p] > squared ? result.core[p] : squared;
                if (reach < result.reach[q]) {
                    result.reach[q] = reach;
                    result.predecessor[q] = p;
                    seeds[q] = true;
                }
            }
        }
    }
    free(processed);
    free(seeds);
    return result;
}
