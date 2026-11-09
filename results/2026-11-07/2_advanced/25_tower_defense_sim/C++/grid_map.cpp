#include "defense.hpp"

Point cellCenter(Cell cell) { return {100 * cell.x, 100 * cell.y}; }
bool GridMap::inside(Cell cell) const { return cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height; }
char GridMap::terrain(Cell cell) const { return rows[cell.y][cell.x]; }
bool GridMap::rock(Cell cell) const { return terrain(cell) == '#'; }
bool GridMap::water(Cell cell) const { return terrain(cell) == '~'; }
bool GridMap::buildable(Cell cell) const { return terrain(cell) == '.'; }
std::size_t GridMap::index(Cell cell) const { return static_cast<std::size_t>(cell.y * width + cell.x); }
GridMap readMap(const std::string& path) {
    Lines lines = readLines(path);
    Lines dimensions = splitFields(lines[0]);
    GridMap grid;
    grid.width = std::stoi(dimensions[0]);
    grid.height = std::stoi(dimensions[1]);
    grid.rows.assign(lines.begin() + 1, lines.begin() + 1 + grid.height);
    std::map<int, Cell> found;
    for (int y = 0; y < grid.height; ++y) for (int x = 0; x < grid.width; ++x) {
        char terrain = grid.rows[y][x];
        if (terrain >= '1' && terrain <= '9') found[terrain - '0'] = {x, y};
        else if (terrain == 'E') grid.exit = {x, y};
    }
    for (const std::pair<const int, Cell>& spawn : found) grid.spawns.push_back(spawn.second);
    return grid;
}
