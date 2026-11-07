#include "layout.h"
const char *variant_names[4] = {"ul", "ur", "dl", "dr"};
int floor_div(int a, int b) {
    int out = a / b;
    if (a < 0 && a % b)
        --out;
    return out;
}
static int separation(const Layout *layout, int a, int b) {
    int gap = a < layout->nodes && b < layout->nodes ? layout->block->settings.node_sep
                                                     : layout->block->settings.dummy_sep;
    return layout->vertices[a].right + layout->vertices[b].left + 1 + gap;
}
static bool marked(const Coordinates *coordinates, int count, int a, int b) {
    return coordinates->marked[(size_t)a * (size_t)count + (size_t)b] != 0;
}
static void mark(Coordinates *coordinates, int count, int a, int b) {
    if (marked(coordinates, count, a, b))
        return;
    coordinates->marked[(size_t)a * (size_t)count + (size_t)b] = 1;
    coordinates->marked[(size_t)b * (size_t)count + (size_t)a] = 1;
    ++coordinates->conflicts;
}
static int rank_vertex(const Layout *layout, const int *pos, int vertex, bool right) {
    return right ? layout->orders.rows[layout->vertices[vertex].layer].count - 1 - pos[vertex]
                 : pos[vertex];
}
typedef struct {
    int count;
    const int *weights;
    int y1[600], y2[600];
} Compaction;
static int leftmost(Compaction *work, int root) {
    if (work->y1[root] >= 0)
        return work->y1[root];
    int value = 0;
    for (int from = 0; from < work->count; ++from) {
        int weight = work->weights[(size_t)from * (size_t)work->count + (size_t)root];
        if (weight) {
            int candidate = leftmost(work, from) + weight;
            if (candidate > value)
                value = candidate;
        }
    }
    return work->y1[root] = value;
}
static int rightmost(Compaction *work, int root) {
    if (work->y2[root] >= 0)
        return work->y2[root];
    int value = leftmost(work, root), minimum = INT_MAX;
    for (int to = 0; to < work->count; ++to) {
        int weight = work->weights[(size_t)root * (size_t)work->count + (size_t)to];
        if (weight) {
            int candidate = rightmost(work, to) - weight;
            if (candidate < minimum)
                minimum = candidate;
        }
    }
    if (minimum != INT_MAX && minimum > value)
        value = minimum;
    return work->y2[root] = value;
}
static int compare_ints(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}
Coordinates coordinates(Layout *layout) {
    Coordinates out = {0};
    int count = layout->vertex_count, pos[600] = {0};
    positions(&layout->orders, pos);
    out.marked = allocate((size_t)count * (size_t)count);
    for (int i = 0; i + 1 < layout->orders.count; ++i) {
        const IntList *upper = &layout->orders.rows[i], *lower = &layout->orders.rows[i + 1];
        int k0 = 0, start = 0;
        for (int end = 0; end < lower->count; ++end) {
            int v = lower->data[end];
            bool inner = v >= layout->nodes && layout->vertices[v].upper.data[0] >= layout->nodes;
            if (!inner && end != lower->count - 1)
                continue;
            int k1 = inner ? pos[layout->vertices[v].upper.data[0]] : upper->count - 1;
            for (int at = start; at <= end; ++at) {
                int w = lower->data[at];
                const IntList *neighbors = &layout->vertices[w].upper;
                for (int j = 0; j < neighbors->count; ++j) {
                    int u = neighbors->data[j];
                    if (pos[u] < k0 || pos[u] > k1)
                        mark(&out, count, u, w);
                }
            }
            start = end + 1;
            k0 = k1;
        }
    }
    for (int variant = 0; variant < 4; ++variant) {
        bool right = variant % 2, down = variant >= 2;
        int root[600], align[600];
        for (int i = 0; i < count; ++i)
            root[i] = align[i] = i;
        for (int offset = 1; offset < layout->orders.count; ++offset) {
            int layer = down ? layout->orders.count - 1 - offset : offset, rho = -1;
            const IntList *row = &layout->orders.rows[layer];
            for (int at = 0; at < row->count; ++at) {
                int v = row->data[right ? row->count - 1 - at : at];
                const IntList *reference =
                    down ? &layout->vertices[v].lower : &layout->vertices[v].upper;
                if (!reference->count)
                    continue;
                IntList sorted = int_copy(reference);
                for (int i = 1; i < sorted.count; ++i) {
                    int value = sorted.data[i], j = i;
                    while (j && rank_vertex(layout, pos, value, right) <
                                    rank_vertex(layout, pos, sorted.data[j - 1], right)) {
                        sorted.data[j] = sorted.data[j - 1];
                        --j;
                    }
                    sorted.data[j] = value;
                }
                int medians[2] = {(sorted.count - 1) / 2, sorted.count / 2};
                for (int i = 0; i < 2; ++i) {
                    int u = sorted.data[medians[i]], rank = rank_vertex(layout, pos, u, right);
                    if (align[v] == v && !marked(&out, count, u, v) && rho < rank) {
                        align[u] = v;
                        root[v] = root[u];
                        align[v] = root[v];
                        rho = rank;
                    }
                }
                int_free(&sorted);
            }
        }
        int *weights = allocate((size_t)count * (size_t)count * sizeof *weights);
        for (int i = 0; i < layout->orders.count; ++i) {
            const IntList *row = &layout->orders.rows[i];
            for (int at = 0; at + 1 < row->count; ++at) {
                int a = row->data[right ? row->count - 1 - at : at],
                    b = row->data[right ? row->count - 2 - at : at + 1],
                    delta = right ? separation(layout, b, a) : separation(layout, a, b);
                int *weight = &weights[(size_t)root[a] * (size_t)count + (size_t)root[b]];
                if (delta > *weight)
                    *weight = delta;
            }
        }
        Compaction work = {0};
        work.count = count;
        work.weights = weights;
        for (int i = 0; i < count; ++i)
            work.y1[i] = work.y2[i] = -1;
        BKVariant *result = &out.variants[variant];
        bool roots[600] = {0};
        for (int v = 0; v < count; ++v) {
            result->root[v] = root[v];
            if (!roots[root[v]]) {
                roots[root[v]] = true;
                ++result->blocks;
            }
            int x = rightmost(&work, root[v]);
            if (right)
                x = -x;
            result->aligned[v] = x;
            int low = x - layout->vertices[v].left, high = x + layout->vertices[v].right;
            if (!v || low < result->low)
                result->low = low;
            if (!v || high > result->high)
                result->high = high;
        }
        result->width = result->high - result->low + 1;
        free(weights);
    }
    for (int i = 1; i < 4; ++i)
        if (out.variants[i].width < out.variants[out.smallest].width)
            out.smallest = i;
    int best_low = out.variants[out.smallest].low, best_high = out.variants[out.smallest].high;
    for (int i = 0; i < 4; ++i) {
        BKVariant *variant = &out.variants[i];
        int shift = i % 2 ? best_high - variant->high : best_low - variant->low;
        for (int v = 0; v < count; ++v)
            variant->aligned[v] += shift;
    }
    int minimum = 0;
    for (int v = 0; v < count; ++v) {
        int values[4];
        for (int i = 0; i < 4; ++i)
            values[i] = out.variants[i].aligned[v];
        qsort(values, 4, sizeof *values, compare_ints);
        layout->vertices[v].x = floor_div(values[1] + values[2], 2);
        int low = layout->vertices[v].x - layout->vertices[v].left;
        if (!v || low < minimum)
            minimum = low;
    }
    for (int v = 0; v < count; ++v)
        layout->vertices[v].x -= minimum;
    return out;
}
