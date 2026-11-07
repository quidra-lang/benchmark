#include "raster.hpp"
#include <array>

static int region(Point point, Rect clip) { return (point.x < clip.x0 ? 1 : 0) | (point.x > clip.x1 ? 2 : 0) | (point.y < clip.y0 ? 4 : 0) | (point.y > clip.y1 ? 8 : 0); }
std::optional<Segment> clipSegment(Point start, Point end, Rect clip) {
    while (true) {
        int first = region(start,clip), second = region(end,clip); if (!first && !second) return Segment{start,end}; if (first & second) return std::nullopt;
        int code = first ? first : second; Point a = first ? start : end, b = first ? end : start, point;
        if (code & 4) point = {a.x + roundRatio((b.x - a.x) * (clip.y0 - a.y),b.y - a.y),clip.y0};
        else if (code & 8) point = {a.x + roundRatio((b.x - a.x) * (clip.y1 - a.y),b.y - a.y),clip.y1};
        else if (code & 2) point = {clip.x1,a.y + roundRatio((b.y - a.y) * (clip.x1 - a.x),b.x - a.x)};
        else point = {clip.x0,a.y + roundRatio((b.y - a.y) * (clip.x0 - a.x),b.x - a.x)};
        if (first) start = point; else end = point;
    }
}
Points clipPolygon(Points vertices, Rect clip) {
    for (std::array<int, 3> boundary : {std::array<int, 3>{0,clip.x0,1},{0,clip.x1 + 1,0},{1,clip.y0,1},{1,clip.y1 + 1,0}}) {
        int axis = boundary[0], limit = boundary[1]; auto inside = [&](Point point) { int value = axis ? point.y : point.x; return boundary[2] ? value >= limit : value <= limit; };
        auto intersection = [&](Point a, Point b) { return axis ? Point{a.x + roundRatio((limit - a.y) * (b.x - a.x),b.y - a.y),limit} : Point{limit,a.y + roundRatio((limit - a.x) * (b.y - a.y),b.x - a.x)}; };
        Points output; for (int i = 0; i < static_cast<int>(vertices.size()); ++i) { Point start = vertices[i == 0 ? vertices.size() - 1 : i - 1], end = vertices[i]; if (inside(end)) { if (!inside(start)) output.push_back(intersection(start,end)); output.push_back(end); } else if (inside(start)) output.push_back(intersection(start,end)); } vertices = std::move(output);
    } return vertices;
}
