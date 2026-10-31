#include "defense.hpp"

const std::array<Cell, 4> Directions = {{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}};
Cell neighbor(Cell cell, int direction) { return {cell.x + Directions[direction].x, cell.y + Directions[direction].y}; }
DistanceField::DistanceField(const GridMap& grid, const std::vector<bool>& occupied) : distances(grid.width * grid.height, -1), width(grid.width), height(grid.height), exit(grid.exit) {
    distances[grid.index(exit)] = 0;
    std::deque<Cell> queue{exit};
    while (!queue.empty()) {
        Cell cell = queue.front();
        queue.pop_front();
        for (int direction = 0; direction < 4; ++direction) {
            Cell next = neighbor(cell, direction);
            if (!grid.inside(next) || grid.rock(next) || occupied[grid.index(next)] || at(next) >= 0) continue;
            distances[grid.index(next)] = at(cell) + 1;
            queue.push_back(next);
        }
    }
}
int DistanceField::at(Cell cell) const { return distances[cell.y * width + cell.x]; }
int DistanceField::direction(Cell cell) const {
    int best = -1;
    int bestDistance = 0;
    for (int direction = 0; direction < 4; ++direction) {
        Cell next = neighbor(cell, direction);
        if (next.x < 0 || next.x >= width || next.y < 0 || next.y >= height || at(next) < 0) continue;
        if (best < 0 || at(next) < bestDistance) { best = direction; bestDistance = at(next); }
    }
    return best;
}
Cell DistanceField::nextCell(Cell cell) const { return neighbor(cell, direction(cell)); }
std::vector<Cell> DistanceField::path(Cell cell) const {
    std::vector<Cell> cells{cell};
    while (cells.back() != exit) cells.push_back(nextCell(cells.back()));
    return cells;
}
