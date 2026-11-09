#include "analysis.hpp"

PageRankResult powerIteration(const WeightedEdges& edges, const Nodes& teleport, double damping, int iterations, double tolerance) {
    int count = static_cast<int>(edges.size()), size = static_cast<int>(teleport.size());
    Nodes weight(count);
    for (const std::vector<Link>& group : edges) for (const Link& edge : group) weight[edge.first] += edge.second;
    std::vector<bool> inTeleport(count);
    for (int node : teleport) inTeleport[node] = true;
    PageRankResult result;
    result.values.resize(count);
    for (int node = 0; node < count; ++node) if (inTeleport[node]) result.values[node] = 1.0 / size;
    for (int step = 1; step <= iterations; ++step) {
        double dangling = 0;
        for (int node = 0; node < count; ++node) if (!weight[node]) dangling += result.values[node];
        double base = ((1 - damping) + damping * dangling) / size;
        Values updated(count);
        for (int node = 0; node < count; ++node) {
            double inflow = 0;
            for (const Link& edge : edges[node]) inflow += (result.values[edge.first] * edge.second) / weight[edge.first];
            updated[node] = damping * inflow + (inTeleport[node] ? base : 0);
        }
        double change = 0;
        for (int node = 0; node < count; ++node) change += std::abs(updated[node] - result.values[node]);
        result.changes.push_back(change);
        if (!result.converged && change < tolerance) result.converged = step;
        result.values = std::move(updated);
    }
    return result;
}
