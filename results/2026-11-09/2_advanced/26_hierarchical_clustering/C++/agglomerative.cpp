#include "clustering.hpp"

static std::array<double, 4> coefficients(const std::string& method, int a, int b, int k) {
    double merged = a + b;
    if (method == "single") return {0.5, 0.5, 0, -0.5};
    if (method == "complete") return {0.5, 0.5, 0, 0.5};
    if (method == "average") return {a / merged, b / merged, 0, 0};
    if (method == "weighted") return {0.5, 0.5, 0, 0};
    if (method == "centroid") return {a / merged, b / merged, -(a * b) / (merged * merged), 0};
    if (method == "median") return {0.5, 0.5, -0.25, 0};
    double total = a + b + k;
    return {(a + k) / total, (b + k) / total, -k / total, 0};
}
std::vector<Merge> agglomerate(const Matrix& delta, const std::string& method) {
    int count = static_cast<int>(delta.size()), capacity = 2 * count - 1;
    bool squared = method == "centroid" || method == "median" || method == "ward";
    Matrix values(capacity, Values(capacity, 0));
    for (int i = 0; i < count; ++i) for (int j = 0; j < count; ++j) values[i][j] = squared ? delta[i][j] * delta[i][j] : delta[i][j];
    Indices sizes(capacity, 1), active(count);
    std::iota(active.begin(), active.end(), 0);
    std::vector<Merge> merges;
    for (int step = 0; step < count - 1; ++step) {
        int a = active[0], b = active[1];
        double best = values[a][b];
        for (std::size_t i = 0; i < active.size(); ++i) for (std::size_t j = i + 1; j < active.size(); ++j) {
            int first = active[i], second = active[j];
            if (values[first][second] < best) { a = first; b = second; best = values[first][second]; }
        }
        int node = count + step;
        sizes[node] = sizes[a] + sizes[b];
        merges.push_back({a, b, squared ? std::sqrt(best) : best, sizes[node]});
        for (int k : active) if (k != a && k != b) {
            std::array<double, 4> c = coefficients(method, sizes[a], sizes[b], sizes[k]);
            double value = c[0] * values[a][k] + c[1] * values[b][k] + c[2] * values[a][b] + c[3] * std::abs(values[a][k] - values[b][k]);
            values[node][k] = values[k][node] = value;
        }
        active.erase(std::remove(active.begin(), active.end(), a), active.end());
        active.erase(std::remove(active.begin(), active.end(), b), active.end());
        active.push_back(node);
    }
    return merges;
}
std::vector<Edge> minimumSpanningTree(const Matrix& delta) {
    int count = static_cast<int>(delta.size());
    std::vector<bool> inTree(count, false);
    inTree[0] = true;
    Values keys = delta[0];
    Indices parents(count, 0);
    std::vector<Edge> edges;
    for (int step = 0; step < count - 1; ++step) {
        int chosen = -1;
        for (int u = 0; u < count; ++u) if (!inTree[u] && (chosen < 0 || keys[u] < keys[chosen])) chosen = u;
        inTree[chosen] = true;
        edges.push_back({parents[chosen], chosen, keys[chosen]});
        for (int u = 0; u < count; ++u) if (!inTree[u] && delta[chosen][u] < keys[u]) { keys[u] = delta[chosen][u]; parents[u] = chosen; }
    }
    return edges;
}
