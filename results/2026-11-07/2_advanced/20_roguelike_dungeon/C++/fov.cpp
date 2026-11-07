#include "dungeon.hpp"

const Lines directionNames{"N", "NE", "E", "SE", "S", "SW", "W", "NW"};
const std::array<Point, 8> directions{{{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}}};
bool passable(const Level& level, Point point) { if (point.first < 0 || point.second < 0 || point.first >= level.width || point.second >= level.height) return false; return std::string(".#+<>").find(level.terrain[point.second][point.first]) != std::string::npos; }
bool canMove(const Level& level, Point point, Point direction) { Point target{point.first + direction.first, point.second + direction.second}; if (!passable(level, target)) return false; return !direction.first || !direction.second || (level.terrain[point.second][point.first] != '+' && level.terrain[target.second][target.first] != '+'); }
Points line(Point first, Point last) {
    int dx = std::abs(last.first - first.first), dy = std::abs(last.second - first.second), sx = last.first > first.first ? 1 : -1, sy = last.second > first.second ? 1 : -1, error = dx - dy;
    Points result;
    while (first != last) { int doubled = 2 * error; if (doubled > -dy) { error -= dy; first.first += sx; } if (doubled < dx) { error += dx; first.second += sy; } result.push_back(first); }
    return result;
}
std::vector<std::vector<bool>> fieldOfView(const Level& level, Point point, int radius) {
    std::vector<std::vector<bool>> visible(level.height, std::vector<bool>(level.width));
    for (int y = std::max(0, point.second - radius); y < std::min(level.height, point.second + radius + 1); ++y) for (int x = std::max(0, point.first - radius); x < std::min(level.width, point.first + radius + 1); ++x) {
        int dx = x - point.first, dy = y - point.second; if (dx * dx + dy * dy > radius * radius) continue;
        Points ray = line(point, {x, y}); bool clear = true;
        for (std::size_t i = 0; i + 1 < ray.size(); ++i) if (!passable(level, ray[i])) { clear = false; break; }
        visible[y][x] = clear;
    }
    return visible;
}
std::vector<std::vector<int>> distances(const Level& level, Point point) {
    std::vector<std::vector<int>> result(level.height, std::vector<int>(level.width, -1)); result[point.second][point.first] = 0; Points queue{point};
    for (std::size_t head = 0; head < queue.size(); ++head) { Point current = queue[head]; for (const Point& direction : directions) if (canMove(level, current, direction)) { Point next{current.first + direction.first, current.second + direction.second}; if (result[next.second][next.first] < 0) { result[next.second][next.first] = result[current.second][current.first] + 1; queue.push_back(next); } } }
    return result;
}
