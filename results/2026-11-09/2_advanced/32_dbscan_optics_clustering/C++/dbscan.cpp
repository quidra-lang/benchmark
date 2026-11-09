#include "clustering.hpp"
std::vector<int> dbscan(const Grid &grid, int min_points) {
    std::vector<int> labels(grid.neighbors.size(), -2);
    int cluster = 0;
    for (std::size_t p = 0; p < labels.size(); ++p) {
        if (labels[p] != -2)
            continue;
        if (grid.neighbors[p].size() < std::size_t(min_points)) {
            labels[p] = -1;
            continue;
        }
        labels[p] = cluster;
        std::deque<int> queue(grid.neighbors[p].begin(), grid.neighbors[p].end());
        while (!queue.empty()) {
            const int q = queue.front();
            queue.pop_front();
            if (labels[q] == -1) {
                labels[q] = cluster;
                continue;
            }
            if (labels[q] >= 0)
                continue;
            labels[q] = cluster;
            if (grid.neighbors[q].size() >= std::size_t(min_points))
                queue.insert(queue.end(), grid.neighbors[q].begin(), grid.neighbors[q].end());
        }
        ++cluster;
    }
    return labels;
}
