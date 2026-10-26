#include "analysis.hpp"

std::pair<Values, Values> hits(int count, const Nodes& nodes, const Links& links, int iterations) {
    Adjacency sources(count), targets(count);
    Links sorted = links;
    std::sort(sorted.begin(), sorted.end());
    for (const Link& edge : sorted) { sources[edge.second].push_back(edge.first); targets[edge.first].push_back(edge.second); }
    Values authority(count), hub(count);
    for (int node : nodes) authority[node] = hub[node] = 1;
    for (int step = 0; step < iterations; ++step) {
        Values incoming(count), outgoing(count);
        for (int node : nodes) for (int source : sources[node]) incoming[node] += hub[source];
        for (int node : nodes) for (int target : targets[node]) outgoing[node] += incoming[target];
        double normA = 0, normH = 0;
        for (int node : nodes) { normA += incoming[node] * incoming[node]; normH += outgoing[node] * outgoing[node]; }
        normA = std::sqrt(normA); normH = std::sqrt(normH);
        for (int node : nodes) { authority[node] = incoming[node] / normA; hub[node] = outgoing[node] / normH; }
    }
    return {authority, hub};
}
