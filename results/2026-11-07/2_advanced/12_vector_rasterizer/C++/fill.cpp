#include "raster.hpp"
#include <algorithm>
#include <cstdlib>
#include <map>

Pixels fillPolygons(const std::vector<Points>& sequences, const std::string& rule, Rect clip) {
    Segments edges; for (const Points& vertices : sequences) for (int i = 0; i < static_cast<int>(vertices.size()); ++i) { Point a = vertices[i], b = vertices[(i + 1) % vertices.size()]; if (a.y != b.y) edges.push_back({a,b}); } Pixels result;
    for (int y = clip.y0; y <= clip.y1; ++y) {
        std::vector<std::pair<int, int>> crossings; for (const Segment& edge : edges) { Point a = edge.first, b = edge.second; if (std::min(a.y,b.y) <= y && y < std::max(a.y,b.y)) { int d = b.y - a.y, n = 2 * a.x * d + (2 * y + 1 - 2 * a.y) * (b.x - a.x); if (d < 0) { n = -n; d = -d; } crossings.push_back({floorDiv(n - d,2 * d) + 1,b.y > a.y ? 1 : -1}); } }
        std::sort(crossings.begin(),crossings.end()); int index = 0, count = 0, winding = 0;
        for (int x = clip.x0; x <= clip.x1; ++x) { while (index < static_cast<int>(crossings.size()) && crossings[index].first <= x) { ++count; winding += crossings[index++].second; } if (rule == "evenodd" ? count % 2 != 0 : winding != 0) result.insert({x,y}); }
    } return result;
}
Pixels fillShape(Point center, const Pixels& shape, Rect clip) {
    std::map<int, int> extents; for (Point point : shape) extents[point.y] = std::max(extents[point.y],std::abs(point.x)); Pixels result;
    for (const auto& extent : extents) { int y = center.y + extent.first; if (y < clip.y0 || y > clip.y1) continue; for (int x = std::max(clip.x0,center.x - extent.second); x <= std::min(clip.x1,center.x + extent.second); ++x) result.insert({x,y}); } return result;
}
Pixels floodFill(const Layer& layer, Point seed, Rect clip) {
    std::optional<Color> target = layer.colorAt(seed); Pixels result{seed}; Points pending{seed};
    while (!pending.empty()) { Point point = pending.back(); pending.pop_back(); for (Point neighbor : {Point{point.x + 1,point.y},{point.x - 1,point.y},{point.x,point.y + 1},{point.x,point.y - 1}}) if (clip.contains(neighbor) && !result.count(neighbor) && layer.colorAt(neighbor) == target) { result.insert(neighbor); pending.push_back(neighbor); } } return result;
}
