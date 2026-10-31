#include "clustering.hpp"
Optics optics(const Grid &grid, const Distances &distances, int min_points) {
    const int n = int(grid.neighbors.size());
    Optics result{std::vector<Integer>(n, INF), std::vector<Integer>(n, INF), std::vector<int>(n, -1), {}};
    for (int p = 0; p < n; ++p)
        if (grid.neighbors[p].size() >= std::size_t(min_points)) {
            std::vector<Integer> values;
            for (int q : grid.neighbors[p])
                values.push_back(distances[p][q]);
            std::sort(values.begin(), values.end());
            result.core[p] = values[min_points - 1];
        }
    std::vector<bool> processed(n), seeds(n);
    for (int t = 0; t < n; ++t) {
        if (processed[t])
            continue;
        seeds[t] = true;
        while (true) {
            int p = -1;
            for (int q = 0; q < n; ++q)
                if (seeds[q] && (p < 0 || std::tie(result.reach[q], q) < std::tie(result.reach[p], p)))
                    p = q;
            if (p < 0)
                break;
            seeds[p] = false;
            processed[p] = true;
            result.order.push_back(p);
            if (result.core[p] == INF)
                continue;
            for (int q : grid.neighbors[p])
                if (!processed[q]) {
                    const Integer reach = std::max(result.core[p], distances[p][q]);
                    if (reach < result.reach[q]) {
                        result.reach[q] = reach;
                        result.predecessor[q] = p;
                        seeds[q] = true;
                    }
                }
        }
    }
    return result;
}
