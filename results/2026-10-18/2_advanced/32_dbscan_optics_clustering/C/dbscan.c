#include "clustering.h"
int *dbscan(const Grid *grid, int min_points) {
    int n = grid->count, *labels = malloc((size_t)n * sizeof *labels);
    for (int i = 0; i < n; ++i)
        labels[i] = -2;
    int cluster = 0;
    for (int p = 0; p < n; ++p) {
        if (labels[p] != -2)
            continue;
        if (grid->neighbors[p].count < min_points) {
            labels[p] = -1;
            continue;
        }
        labels[p] = cluster;
        IntList queue = {0};
        for (int i = 0; i < grid->neighbors[p].count; ++i)
            push(&queue, grid->neighbors[p].values[i]);
        for (int front = 0; front < queue.count; ++front) {
            int q = queue.values[front];
            if (labels[q] == -1) {
                labels[q] = cluster;
                continue;
            }
            if (labels[q] >= 0)
                continue;
            labels[q] = cluster;
            if (grid->neighbors[q].count >= min_points)
                for (int i = 0; i < grid->neighbors[q].count; ++i)
                    push(&queue, grid->neighbors[q].values[i]);
        }
        free(queue.values);
        ++cluster;
    }
    return labels;
}
