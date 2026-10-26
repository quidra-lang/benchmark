#include "analysis.h"

Components strong_components(const Graph *graph) {
    int order[500], low[500], stack[500], stack_size = 0, counter = 0;
    bool on_stack[500] = {0};
    Components result = {0};
    for (int i = 0; i < graph->count; ++i) order[i] = -1;
    typedef struct { int node, next; } Frame;
    Frame work[500];
    for (int root = 0; root < graph->count; ++root) {
        if (order[root] >= 0) continue;
        order[root] = low[root] = counter++;
        stack[stack_size++] = root; on_stack[root] = true;
        int depth = 1; work[0] = (Frame){root, 0};
        while (depth) {
            Frame *frame = &work[depth - 1];
            int node = frame->node;
            if (frame->next < graph->out[node].count) {
                int child = graph->out[node].values[frame->next++];
                if (order[child] < 0) {
                    order[child] = low[child] = counter++;
                    stack[stack_size++] = child; on_stack[child] = true;
                    work[depth++] = (Frame){child, 0};
                } else if (on_stack[child] && order[child] < low[node]) low[node] = order[child];
                continue;
            }
            --depth;
            if (depth && low[node] < low[work[depth - 1].node]) low[work[depth - 1].node] = low[node];
            if (low[node] == order[node]) {
                int minimum = graph->count, member;
                do {
                    member = stack[--stack_size]; on_stack[member] = false;
                    result.labels[member] = result.count; ++result.sizes[result.count];
                    if (member < minimum) minimum = member;
                } while (member != node);
                result.minimum[result.count++] = minimum;
            }
        }
    }
    int ranking[500], mapping[500], sizes[500], minimum[500];
    for (int c = 0; c < result.count; ++c) {
        int j = c;
        while (j && result.minimum[ranking[j - 1]] > result.minimum[c]) { ranking[j] = ranking[j - 1]; --j; }
        ranking[j] = c;
    }
    for (int c = 0; c < result.count; ++c) { mapping[ranking[c]] = c; sizes[c] = result.sizes[ranking[c]]; minimum[c] = result.minimum[ranking[c]]; }
    for (int i = 0; i < graph->count; ++i) result.labels[i] = mapping[result.labels[i]];
    memcpy(result.sizes, sizes, (size_t)result.count * sizeof(int));
    memcpy(result.minimum, minimum, (size_t)result.count * sizeof(int));
    return result;
}
void reachable(const Graph *graph, const bool *starts, bool reverse, bool *seen) {
    int stack[500], count = 0;
    memset(seen, 0, (size_t)graph->count * sizeof(bool));
    for (int i = 0; i < graph->count; ++i) if (starts[i]) { seen[i] = true; stack[count++] = i; }
    while (count) {
        int node = stack[--count];
        Nodes neighbors = reverse ? graph->in[node] : graph->out[node];
        for (int j = 0; j < neighbors.count; ++j) {
            int child = neighbors.values[j];
            if (!seen[child]) { seen[child] = true; stack[count++] = child; }
        }
    }
}
void bfs_distances(const Graph *graph, const bool *starts, int *distances) {
    int queue[500], head = 0, count = 0;
    for (int i = 0; i < graph->count; ++i) { distances[i] = starts[i] ? 0 : -1; if (starts[i]) queue[count++] = i; }
    while (head < count) {
        int node = queue[head++];
        for (int j = 0; j < graph->out[node].count; ++j) {
            int child = graph->out[node].values[j];
            if (distances[child] < 0) { distances[child] = distances[node] + 1; queue[count++] = child; }
        }
    }
}
int weak_components(const Graph *graph, int *labels) {
    int count = 0;
    for (int i = 0; i < graph->count; ++i) labels[i] = -1;
    for (int root = 0; root < graph->count; ++root) {
        if (labels[root] >= 0) continue;
        int stack[500], size = 1; stack[0] = root; labels[root] = count;
        while (size) {
            int node = stack[--size];
            for (int reverse = 0; reverse < 2; ++reverse) {
                Nodes neighbors = reverse ? graph->in[node] : graph->out[node];
                for (int j = 0; j < neighbors.count; ++j) {
                    int child = neighbors.values[j];
                    if (labels[child] < 0) { labels[child] = count; stack[size++] = child; }
                }
            }
        }
        ++count;
    }
    return count;
}
