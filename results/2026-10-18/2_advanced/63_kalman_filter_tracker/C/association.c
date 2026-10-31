#include "tracker.h"
static int pair_order(const void *a, const void *b) {
    const Pair *x = a, *y = b;
    return x->row != y->row ? x->row - y->row : x->column - y->column;
}
Pairs minimum_matching(const double *costs, int row_count, int column_count) {
    Pairs out = {0};
    if (!row_count || !column_count)
        return out;
    bool flipped = row_count > column_count;
    int rows = flipped ? column_count : row_count, columns = flipped ? row_count : column_count;
    double *u = allocate((size_t)rows + 1, sizeof(double)),
           *v = allocate((size_t)columns + 1, sizeof(double)),
           *distances = allocate((size_t)columns + 1, sizeof(double));
    int *matched = allocate((size_t)columns + 1, sizeof(int)),
        *previous = allocate((size_t)columns + 1, sizeof(int));
    bool *used = allocate((size_t)columns + 1, sizeof(bool));
    for (int row = 1; row <= rows; ++row) {
        matched[0] = row;
        int column = 0;
        for (int j = 0; j <= columns; ++j) {
            distances[j] = INFINITY;
            used[j] = false;
        }
        do {
            used[column] = true;
            int current = matched[column], following = 0;
            double delta = INFINITY;
            for (int candidate = 1; candidate <= columns; ++candidate)
                if (!used[candidate]) {
                    double value = flipped ? costs[(candidate - 1) * column_count + current - 1]
                                           : costs[(current - 1) * column_count + candidate - 1],
                           reduced = value - u[current] - v[candidate];
                    if (reduced < distances[candidate]) {
                        distances[candidate] = reduced;
                        previous[candidate] = column;
                    }
                    if (distances[candidate] < delta) {
                        delta = distances[candidate];
                        following = candidate;
                    }
                }
            for (int candidate = 0; candidate <= columns; ++candidate) {
                if (used[candidate]) {
                    u[matched[candidate]] += delta;
                    v[candidate] -= delta;
                } else
                    distances[candidate] -= delta;
            }
            column = following;
        } while (matched[column] != 0);
        while (column) {
            int following = previous[column];
            matched[column] = matched[following];
            column = following;
        }
    }
    out.data = allocate((size_t)rows, sizeof(Pair));
    for (int column = 1; column <= columns; ++column)
        if (matched[column])
            out.data[out.count++] = flipped ? (Pair){column - 1, matched[column] - 1}
                                            : (Pair){matched[column] - 1, column - 1};
    qsort(out.data, (size_t)out.count, sizeof(Pair), pair_order);
    return out;
}
Pairs optimal_assignment(const double *costs, const bool *usable, int rows, int columns) {
    Pairs out = {0};
    if (!rows || !columns)
        return out;
    double largest = 0;
    for (int i = 0; i < rows * columns; ++i)
        if (usable[i] && costs[i] > largest)
            largest = costs[i];
    double penalty = ((rows < columns ? rows : columns) + 1) * (fmax(1, largest) + 1);
    double *matrix = allocate((size_t)(rows * columns), sizeof(double));
    for (int i = 0; i < rows * columns; ++i)
        matrix[i] = usable[i] ? costs[i] : penalty;
    Pairs matching = minimum_matching(matrix, rows, columns);
    out.data = allocate((size_t)matching.count, sizeof(Pair));
    for (int i = 0; i < matching.count; ++i) {
        Pair pair = matching.data[i];
        if (usable[pair.row * columns + pair.column])
            out.data[out.count++] = pair;
    }
    return out;
}
