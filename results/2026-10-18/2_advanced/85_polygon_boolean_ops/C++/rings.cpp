#include "geometry.hpp"
#include <algorithm>
#include <cmath>
Ring integerRing(std::vector<Point> points) {
    Ring ring;
    ring.points = std::move(points);
    for (std::size_t i = 0; i < ring.points.size(); ++i)
        ring.edges.push_back(
            originalLine(ring.points[i], ring.points[(i + 1) % ring.points.size()]));
    return ring;
}
bool insideRing(Point p, const Ring &ring) {
    bool inside = false;
    for (std::size_t i = 0; i < ring.points.size(); ++i) {
        Point a = ring.points[i], b = ring.points[(i + 1) % ring.points.size()];
        if ((a.yValue().compare(p.yValue()) > 0) == (b.yValue().compare(p.yValue()) > 0))
            continue;
        Integer cross = lineCross(ring.edges[i], p);
        if (a.yValue().compare(b.yValue()) > 0)
            cross = -cross;
        if (cross > 0)
            inside = !inside;
    }
    return inside;
}
bool interior(Point p, const Rings &rings) {
    bool inside = false;
    for (const Ring &ring : rings)
        if (insideRing(p, ring))
            inside = !inside;
    return inside;
}
bool boundary(Point p, const Ring &ring) {
    for (std::size_t i = 0; i < ring.points.size(); ++i)
        if (onEdge(p, ring, i))
            return true;
    return false;
}
Ring rotateRing(Ring ring) {
    std::size_t first = 0;
    for (std::size_t i = 1; i < ring.points.size(); ++i)
        if (pointLess(ring.points[i], ring.points[first]))
            first = i;
    std::rotate(ring.points.begin(), ring.points.begin() + first, ring.points.end());
    std::rotate(ring.edges.begin(), ring.edges.begin() + first, ring.edges.end());
    return ring;
}
bool counterclockwise(const Ring &ring) {
    return directionCross(ring.edges.back(), ring.edges.front()) > 0;
}
Ring reverseRing(const Ring &ring) {
    Ring result;
    std::size_t n = ring.points.size();
    result.points.push_back(ring.points[0]);
    for (std::size_t i = 1; i < n; ++i)
        result.points.push_back(ring.points[n - i]);
    for (std::size_t i = 0; i < n; ++i)
        result.edges.push_back(reverseLine(ring.edges[n - i - 1]));
    return result;
}
PolygonPtr canonical(const Rings &input) {
    Polygon result;
    result.input = input;
    for (std::size_t i = 0; i < input.size(); ++i) {
        Ring ring = rotateRing(input[i]);
        if (counterclockwise(ring) != (i == 0))
            ring = reverseRing(ring);
        result.rings.push_back(std::move(ring));
    }
    std::sort(result.rings.begin() + 1, result.rings.end(),
              [](const Ring &a, const Ring &b) { return pointLess(a.points[0], b.points[0]); });
    return std::make_shared<const Polygon>(std::move(result));
}
PolygonList assemble(Rings rings) {
    std::vector<int> depth(rings.size());
    for (Ring &ring : rings)
        ring = rotateRing(std::move(ring));
    for (std::size_t i = 0; i < rings.size(); ++i) {
        for (std::size_t j = 0; j < rings.size(); ++j)
            if (i != j && insideRing(rings[i].points[0], rings[j]))
                ++depth[i];
        if (counterclockwise(rings[i]) != (depth[i] % 2 == 0))
            rings[i] = reverseRing(rings[i]);
    }
    std::vector<std::size_t> outer;
    for (std::size_t i = 0; i < rings.size(); ++i)
        if (depth[i] % 2 == 0)
            outer.push_back(i);
    std::sort(outer.begin(), outer.end(), [&](std::size_t a, std::size_t b) {
        return pointLess(rings[a].points[0], rings[b].points[0]);
    });
    PolygonList result;
    for (std::size_t i : outer) {
        Polygon polygon;
        polygon.rings.push_back(rings[i]);
        Rings holes;
        for (std::size_t j = 0; j < rings.size(); ++j)
            if (depth[j] == depth[i] + 1 && insideRing(rings[j].points[0], rings[i]))
                holes.push_back(rings[j]);
        std::sort(holes.begin(), holes.end(),
                  [](const Ring &a, const Ring &b) { return pointLess(a.points[0], b.points[0]); });
        polygon.rings.insert(polygon.rings.end(), holes.begin(), holes.end());
        result.push_back(std::make_shared<const Polygon>(std::move(polygon)));
    }
    return result;
}
double ringArea(const Ring &ring) {
    double sum = 0.0;
    for (std::size_t i = 0; i < ring.points.size(); ++i) {
        Point a = ring.points[i], b = ring.points[(i + 1) % ring.points.size()];
        sum += a.xValue().real() * b.yValue().real() - b.xValue().real() * a.yValue().real();
    }
    return sum / 2.0;
}
double ringPerimeter(const Ring &ring) {
    double sum = 0.0;
    for (std::size_t i = 0; i < ring.points.size(); ++i) {
        Point a = ring.points[i], b = ring.points[(i + 1) % ring.points.size()];
        double dx = b.xValue().real() - a.xValue().real(),
               dy = b.yValue().real() - a.yValue().real();
        sum += std::sqrt(dx * dx + dy * dy);
    }
    return sum;
}
Rings flatten(const PolygonList &polygons) {
    Rings result;
    for (const PolygonPtr &polygon : polygons)
        result.insert(result.end(), polygon->rings.begin(), polygon->rings.end());
    return result;
}
double totalArea(const PolygonList &polygons) {
    double sum = 0.0;
    for (const PolygonPtr &polygon : polygons)
        for (const Ring &ring : polygon->rings)
            sum += ringArea(ring);
    return sum;
}
