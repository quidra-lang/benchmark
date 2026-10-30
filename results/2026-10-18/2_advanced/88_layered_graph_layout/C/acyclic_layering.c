#include "layout.h"
IntList acyclic(int nodes, const Edge *edges, int edge_count) {
    bool remaining[40] = {0};
    for (int i = 0; i < nodes; ++i)
        remaining[i] = true;
    IntList head = {0}, tail = {0};
    for (int count = 0; count < nodes; ++count) {
        int incoming[40] = {0}, outgoing[40] = {0};
        for (int i = 0; i < edge_count; ++i)
            if (remaining[edges[i].from] && remaining[edges[i].to]) {
                ++outgoing[edges[i].from];
                ++incoming[edges[i].to];
            }
        int chosen = -1;
        bool to_tail = false;
        for (int v = 0; v < nodes; ++v)
            if (remaining[v] && !outgoing[v]) {
                chosen = v;
                to_tail = true;
                break;
            }
        if (chosen < 0)
            for (int v = 0; v < nodes; ++v)
                if (remaining[v] && !incoming[v]) {
                    chosen = v;
                    break;
                }
        if (chosen < 0)
            for (int v = 0; v < nodes; ++v)
                if (remaining[v] &&
                    (chosen < 0 || outgoing[v] - incoming[v] > outgoing[chosen] - incoming[chosen]))
                    chosen = v;
        remaining[chosen] = false;
        if (to_tail)
            int_push(&tail, chosen);
        else
            int_push(&head, chosen);
    }
    for (int i = tail.count - 1; i >= 0; --i)
        int_push(&head, tail.data[i]);
    int_free(&tail);
    return head;
}
static int longest_height(int node, const Orders *successors, int *height, bool *known) {
    if (known[node])
        return height[node];
    const IntList *next = &successors->rows[node];
    for (int i = 0; i < next->count; ++i) {
        int value = longest_height(next->data[i], successors, height, known) + 1;
        if (value > height[node])
            height[node] = value;
    }
    known[node] = true;
    return height[node];
}
static int compare_sequences(const IntList *a, const IntList *b) {
    int size = a->count < b->count ? a->count : b->count;
    for (int i = 0; i < size; ++i)
        if (a->data[i] != b->data[i])
            return a->data[i] < b->data[i] ? -1 : 1;
    return (a->count > b->count) - (a->count < b->count);
}
static int compare_descending(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a < b) - (a > b);
}
static int promote(int node, const Orders *predecessors, const Orders *successors, int *height) {
    int difference = 0;
    const IntList *previous = &predecessors->rows[node];
    for (int i = 0; i < previous->count; ++i) {
        int p = previous->data[i];
        if (height[p] == height[node] + 1)
            difference += promote(p, predecessors, successors, height);
    }
    ++height[node];
    return difference + successors->rows[node].count - predecessors->rows[node].count;
}
LayeringResult assign_layers(const Orders *predecessors, const Orders *successors,
                             Settings settings) {
    LayeringResult out = {0};
    int nodes = predecessors->count;
    if (!settings.coffman) {
        bool known[40] = {0};
        for (int i = 0; i < nodes; ++i)
            longest_height(i, successors, out.height, known);
    } else {
        for (int label = 1; label <= nodes; ++label) {
            int chosen = -1;
            IntList best = {0};
            for (int v = 0; v < nodes; ++v)
                if (!out.labels[v]) {
                    bool ready = true;
                    IntList key = {0};
                    const IntList *previous = &predecessors->rows[v];
                    for (int i = 0; i < previous->count; ++i) {
                        if (!out.labels[previous->data[i]]) {
                            ready = false;
                            break;
                        }
                        int_push(&key, out.labels[previous->data[i]]);
                    }
                    if (!ready) {
                        int_free(&key);
                        continue;
                    }
                    if (key.count > 1)
                        qsort(key.data, (size_t)key.count, sizeof *key.data, compare_descending);
                    if (chosen < 0 || compare_sequences(&key, &best) < 0) {
                        chosen = v;
                        int_free(&best);
                        best = key;
                    } else
                        int_free(&key);
                }
            out.labels[chosen] = label;
            int_free(&best);
        }
        for (int i = 0; i < nodes; ++i)
            out.height[i] = -1;
        int current = 0, count = 0;
        for (int k = 0; k < nodes; ++k) {
            int chosen = -1;
            for (int v = 0; v < nodes; ++v)
                if (out.height[v] < 0) {
                    bool ready = true;
                    const IntList *next = &successors->rows[v];
                    for (int i = 0; i < next->count; ++i)
                        if (out.height[next->data[i]] < 0)
                            ready = false;
                    if (ready && (chosen < 0 || out.labels[v] > out.labels[chosen]))
                        chosen = v;
                }
            bool next = count == settings.width;
            const IntList *successor = &successors->rows[chosen];
            for (int i = 0; i < successor->count; ++i)
                if (out.height[successor->data[i]] == current)
                    next = true;
            if (next) {
                ++current;
                count = 0;
            }
            out.height[chosen] = current;
            ++count;
        }
    }
    for (int v = 0; v < nodes; ++v)
        for (int i = 0; i < successors->rows[v].count; ++i)
            out.dummies_before += out.height[v] - out.height[successors->rows[v].data[i]] - 1;
    if (settings.promotion)
        for (;;) {
            ++out.rounds;
            int accepted = 0;
            for (int v = 0; v < nodes; ++v)
                if (predecessors->rows[v].count) {
                    int saved[40];
                    memcpy(saved, out.height, sizeof saved);
                    int difference = promote(v, predecessors, successors, out.height);
                    if (difference < 0) {
                        ++accepted;
                        if (out.promotion_count == out.promotion_capacity) {
                            out.promotion_capacity =
                                out.promotion_capacity ? out.promotion_capacity * 2 : 16;
                            out.promotions = resize(out.promotions, (size_t)out.promotion_capacity *
                                                                        sizeof *out.promotions);
                        }
                        out.promotions[out.promotion_count++] =
                            (Promotion){out.rounds, v, difference};
                    } else
                        memcpy(out.height, saved, sizeof saved);
                }
            if (!accepted)
                break;
        }
    return out;
}
