#include "spatial.hpp"
Grid::Grid(int w, int g) : world(w), side(g), dimension(w / g), cells(dimension * dimension) {
}
void Grid::insert(Point point) {
    auto &cell = cells[(point.y / side) * dimension + point.x / side];
    const auto where = std::lower_bound(cell.begin(), cell.end(), point.id,
                                        [](Point value, int id) { return value.id < id; });
    cell.insert(where, point);
}
void Grid::erase(Point point) {
    auto &cell = cells[(point.y / side) * dimension + point.x / side];
    cell.erase(std::find_if(cell.begin(), cell.end(), [&](Point value) { return value.id == point.id; }));
}
