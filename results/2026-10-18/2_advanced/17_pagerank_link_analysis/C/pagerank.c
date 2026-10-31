#include "analysis.h"

PageRank power_iteration(const Graph *graph, const bool *teleport, double damping, int iterations, double tolerance) {
    PageRank result = {.iterations = iterations};
    int size = 0, weights[500] = {0};
    for (int u = 0; u < graph->count; ++u) {
        if (teleport[u]) ++size;
        for (int j = 0; j < graph->out[u].count; ++j) weights[u] += graph->weights[u * graph->count + graph->out[u].values[j]];
    }
    for (int v = 0; v < graph->count; ++v) result.values[v] = teleport[v] ? 1.0 / size : 0;
    for (int t = 0; t < iterations; ++t) {
        double dangling = 0, updated[500];
        for (int u = 0; u < graph->count; ++u) if (!weights[u]) dangling += result.values[u];
        double base = ((1 - damping) + damping * dangling) / size;
        for (int v = 0; v < graph->count; ++v) {
            double inflow = 0;
            for (int j = 0; j < graph->in[v].count; ++j) {
                int u = graph->in[v].values[j];
                inflow += (result.values[u] * graph->weights[u * graph->count + v]) / weights[u];
            }
            updated[v] = damping * inflow + (teleport[v] ? base : 0);
        }
        double change = 0;
        for (int v = 0; v < graph->count; ++v) change += fabs(updated[v] - result.values[v]);
        result.changes[t] = change;
        if (!result.converged_at && change < tolerance) result.converged_at = t + 1;
        memcpy(result.values, updated, (size_t)graph->count * sizeof(double));
    }
    return result;
}
