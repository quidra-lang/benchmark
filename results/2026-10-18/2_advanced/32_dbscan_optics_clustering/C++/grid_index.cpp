#include "clustering.hpp"
Grid build_grid(const std::vector<Point> &points, const Distances &distances, int radius) {
    Grid grid;
    grid.radius = radius;
    grid.neighbors.resize(points.size());
    grid.candidates.resize(points.size());
    for (std::size_t i = 0; i < points.size(); ++i)
        grid.cells[{points[i].x / radius, points[i].y / radius}].push_back(int(i));
    for (const auto &item : grid.cells) {
        const int gx = item.first.first, gy = item.first.second, count = int(item.second.size());
        ++grid.occupancy[count];
        if (count > grid.busiest_count ||
            (count == grid.busiest_count && std::tie(gy, gx) < std::tie(grid.busiest_y, grid.busiest_x))) {
            grid.busiest_count = count;
            grid.busiest_x = gx;
            grid.busiest_y = gy;
        }
    }
    Integer neighbors = 0, brute = 0;
    for (std::size_t i = 0; i < points.size(); ++i) {
        const int gx = points[i].x / radius, gy = points[i].y / radius;
        for (int row = gy - 1; row <= gy + 1; ++row)
            for (int column = gx - 1; column <= gx + 1; ++column) {
                const auto found = grid.cells.find({column, row});
                if (found == grid.cells.end())
                    continue;
                for (int j : found->second) {
                    ++grid.candidates[i];
                    if (distances[i][j] <= Integer(radius) * radius)
                        grid.neighbors[i].push_back(j);
                }
            }
        int brute_count = 0;
        for (std::size_t j = 0; j < points.size(); ++j)
            if (distances[i][j] <= Integer(radius) * radius)
                ++brute_count;
        if (brute_count != int(grid.neighbors[i].size()))
            grid.correct = false;
        brute += brute_count;
        neighbors += grid.neighbors[i].size();
        grid.total_candidates += grid.candidates[i];
    }
    grid.pairs = (neighbors - Integer(points.size())) / 2;
    grid.brute_pairs = (brute - Integer(points.size())) / 2;
    return grid;
}
