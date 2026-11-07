#include "raster.hpp"
#include <cstdlib>

Points bresenham(Point start, Point end) {
    int dx = std::abs(end.x - start.x), dy = -std::abs(end.y - start.y), sx = start.x < end.x ? 1 : -1, sy = start.y < end.y ? 1 : -1, error = dx + dy; Points points;
    while (true) { points.push_back(start); if (start == end) return points; int doubled = 2 * error; if (doubled >= dy) { error += dy; start.x += sx; } if (doubled <= dx) { error += dx; start.y += sy; } }
}
Points expandSquare(Point point, int width) { Points result; int low = -(width - 1) / 2; for (int j = low; j < low + width; ++j) for (int i = low; i < low + width; ++i) result.push_back({point.x + i,point.y + j}); return result; }
Pixels circlePoints(int radius) {
    Pixels points; int a = radius, b = 0, error = 1 - radius;
    while (a >= b) { for (Point point : {Point{a,b},{b,a},{-b,a},{-a,b},{-a,-b},{-b,-a},{b,-a},{a,-b}}) points.insert(point); ++b; if (error < 0) error += 2 * b + 1; else { --a; error += 2 * (b - a) + 1; } } return points;
}
static void quadrants(Pixels& points, int x, int y) { for (Point point : {Point{x,y},{-x,y},{x,-y},{-x,-y}}) points.insert(point); }
Pixels ellipsePoints(int rx, int ry) {
    int rx2 = rx * rx, ry2 = ry * ry, x = 0, y = ry; Pixels points{{0,ry},{0,-ry}};
    while (ry2 * x < rx2 * y) { int decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2; ++x; if (decision >= 0) --y; quadrants(points,x,y); }
    while (y > 0) { int decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2; --y; if (decision <= 0) ++x; quadrants(points,x,y); } return points;
}
Points bezierPoints(const Points& controls, int segments) {
    Points result; bool cubic = controls.size() == 4; int scale = segments * segments * (cubic ? segments : 1);
    for (int i = 0; i <= segments; ++i) { int rest = segments - i; std::vector<int> weights = cubic ? std::vector<int>{rest * rest * rest,3 * i * rest * rest,3 * i * i * rest,i * i * i} : std::vector<int>{rest * rest,2 * i * rest,i * i}; int x = 0, y = 0; for (int j = 0; j < static_cast<int>(weights.size()); ++j) { x += weights[j] * controls[j].x; y += weights[j] * controls[j].y; } result.push_back({roundRatio(x,scale),roundRatio(y,scale)}); } return result;
}
