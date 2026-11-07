#include "analysis.h"

Hits hits(const Graph *graph, const bool *nodes, int iterations) {
    Hits result = {0};
    for (int v = 0; v < graph->count; ++v) if (nodes[v]) { result.authority[v] = 1; result.hub[v] = 1; }
    for (int t = 0; t < iterations; ++t) {
        double incoming[500] = {0}, outgoing[500] = {0}, a_square = 0, h_square = 0;
        for (int v = 0; v < graph->count; ++v) if (nodes[v]) for (int j = 0; j < graph->in[v].count; ++j) incoming[v] += result.hub[graph->in[v].values[j]];
        for (int u = 0; u < graph->count; ++u) if (nodes[u]) for (int j = 0; j < graph->out[u].count; ++j) outgoing[u] += incoming[graph->out[u].values[j]];
        for (int v = 0; v < graph->count; ++v) if (nodes[v]) { a_square += incoming[v] * incoming[v]; h_square += outgoing[v] * outgoing[v]; }
        double a_norm = sqrt(a_square), h_norm = sqrt(h_square);
        for (int v = 0; v < graph->count; ++v) if (nodes[v]) { result.authority[v] = incoming[v] / a_norm; result.hub[v] = outgoing[v] / h_norm; }
    }
    return result;
}
