#include "layout.h"
void positions(const Orders *orders, int *out) {
    for (int i = 0; i < orders->count; ++i)
        for (int j = 0; j < orders->rows[i].count; ++j)
            out[orders->rows[i].data[j]] = j;
}
typedef struct {
    int upper, lower;
} PositionPair;
static int compare_pairs(const void *left, const void *right) {
    const PositionPair *a = left, *b = right;
    if (a->upper != b->upper)
        return (a->upper > b->upper) - (a->upper < b->upper);
    return (a->lower > b->lower) - (a->lower < b->lower);
}
int gap_crossings(const Segment *segments, const IntList *indices, const int *pos, int width) {
    PositionPair pairs[120];
    for (int i = 0; i < indices->count; ++i) {
        const Segment *segment = &segments[indices->data[i]];
        pairs[i] = (PositionPair){pos[segment->upper], pos[segment->lower]};
    }
    if (indices->count > 1)
        qsort(pairs, (size_t)indices->count, sizeof *pairs, compare_pairs);
    int capacity = 1;
    while (capacity < width)
        capacity *= 2;
    int tree[2047] = {0}, out = 0;
    for (int i = 0; i < indices->count; ++i) {
        int at = pairs[i].lower + capacity - 1;
        ++tree[at];
        while (at) {
            if (at % 2)
                out += tree[at + 1];
            at = (at - 1) / 2;
            ++tree[at];
        }
    }
    return out;
}
int total_crossings(const Layout *layout, const Orders *orders) {
    int pos[600] = {0}, out = 0;
    positions(orders, pos);
    for (int i = 0; i < layout->gaps.count; ++i)
        out +=
            gap_crossings(layout->segments, &layout->gaps.rows[i], pos, orders->rows[i + 1].count);
    return out;
}
int brute_crossings(Layout *layout, const Orders *orders, bool count_edges) {
    int pos[600] = {0}, out = 0;
    positions(orders, pos);
    for (int gap = 0; gap < layout->gaps.count; ++gap) {
        const IntList *indices = &layout->gaps.rows[gap];
        for (int i = 0; i < indices->count; ++i)
            for (int j = i + 1; j < indices->count; ++j) {
                const Segment *a = &layout->segments[indices->data[i]],
                              *b = &layout->segments[indices->data[j]];
                if ((pos[a->upper] - pos[b->upper]) * (pos[a->lower] - pos[b->lower]) < 0) {
                    ++out;
                    if (count_edges) {
                        ++layout->edges[a->edge].crossings;
                        ++layout->edges[b->edge].crossings;
                    }
                }
            }
    }
    return out;
}
int adjacent_cost(const Layout *layout, int left, int right, const int *pos) {
    int out = 0;
    const Vertex *a = &layout->vertices[left], *b = &layout->vertices[right];
    for (int i = 0; i < a->upper.count; ++i)
        for (int j = 0; j < b->upper.count; ++j)
            if (pos[a->upper.data[i]] > pos[b->upper.data[j]])
                ++out;
    for (int i = 0; i < a->lower.count; ++i)
        for (int j = 0; j < b->lower.count; ++j)
            if (pos[a->lower.data[i]] > pos[b->lower.data[j]])
                ++out;
    return out;
}
