#include "tracker.h"
double squared_distance(Position a, Position b) {
    double x = a.x - b.x, y = a.y - b.y;
    return x * x + y * y;
}
double distance(Position a, Position b) { return sqrt(squared_distance(a, b)); }
double ospa(const Position *a, int a_count, const Position *b, int b_count, double cutoff) {
    if (!a_count && !b_count)
        return 0;
    if (!a_count || !b_count)
        return cutoff;
    const Position *small = a_count <= b_count ? a : b, *large = a_count <= b_count ? b : a;
    int rows = a_count <= b_count ? a_count : b_count,
        columns = a_count <= b_count ? b_count : a_count;
    double *costs = allocate((size_t)(rows * columns), sizeof(double));
    for (int i = 0; i < rows; ++i)
        for (int j = 0; j < columns; ++j) {
            double value = fmin(cutoff, distance(small[i], large[j]));
            costs[i * columns + j] = value * value;
        }
    Pairs matching = minimum_matching(costs, rows, columns);
    double sum = 0;
    for (int i = 0; i < matching.count; ++i)
        sum += costs[matching.data[i].row * columns + matching.data[i].column];
    return sqrt((sum + cutoff * cutoff * (columns - rows)) / columns);
}
Continuity continuity(const int *labels, int count) {
    Continuity out = {0, 0, 0, -1};
    int previous = -1, groups = 0;
    bool adjacent = false;
    for (int i = 0; i < count; ++i) {
        int label = labels[i];
        if (label < 0) {
            adjacent = false;
            continue;
        }
        ++out.covered;
        if (out.delay < 0)
            out.delay = i;
        if (!adjacent)
            ++groups;
        if (previous >= 0 && previous != label)
            ++out.swaps;
        previous = label;
        adjacent = true;
    }
    out.breaks = groups ? groups - 1 : 0;
    return out;
}
char *real(double value) {
    char *out = format("%.4f", value);
    return strcmp(out, "-0.0000") == 0 ? "0.0000" : out;
}
