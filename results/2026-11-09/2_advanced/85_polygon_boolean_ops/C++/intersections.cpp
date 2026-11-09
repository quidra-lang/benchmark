#include "geometry.hpp"
#include <algorithm>
static bool between(Fraction value, Fraction a, Fraction b) {
    if (a.compare(b) > 0)
        std::swap(a, b);
    return a.compare(value) <= 0 && value.compare(b) <= 0;
}
bool onSegment(Point p, Point a, Point b) {
    return lineCross(originalLine(a, b), p) == 0 && between(p.xValue(), a.xValue(), b.xValue()) &&
           between(p.yValue(), a.yValue(), b.yValue());
}
static int sign(Integer n) { return (n > 0) - (n < 0); }
bool touching(Point a, Point b, Point c, Point d) {
    int x = sign(integerCross(a, b, c)), y = sign(integerCross(a, b, d)),
        z = sign(integerCross(c, d, a)), w = sign(integerCross(c, d, b));
    return (x * y < 0 && z * w < 0) || onSegment(c, a, b) || onSegment(d, a, b) ||
           onSegment(a, c, d) || onSegment(b, c, d);
}
bool overlapping(Point a, Point b, Point c, Point d) {
    if (integerCross(a, b, c) || integerCross(a, b, d))
        return false;
    Fraction aa = a.xValue(), bb = b.xValue(), cc = c.xValue(), dd = d.xValue();
    if (aa.compare(bb) == 0) {
        aa = a.yValue();
        bb = b.yValue();
        cc = c.yValue();
        dd = d.yValue();
    }
    if (aa.compare(bb) > 0)
        std::swap(aa, bb);
    if (cc.compare(dd) > 0)
        std::swap(cc, dd);
    if (cc.compare(aa) > 0)
        aa = cc;
    if (dd.compare(bb) < 0)
        bb = dd;
    return aa.compare(bb) < 0;
}
static Intersection intersection(OriginalLine a, OriginalLine b) {
    Integer rx = a.bx - a.ax, ry = a.by - a.ay, sx = b.bx - b.ax, sy = b.by - b.ay,
            den = rx * sy - ry * sx, gx = b.ax - a.ax, gy = b.ay - a.ay, t = gx * sy - gy * sx,
            u = gx * ry - gy * rx;
    if (den < 0) {
        den = -den;
        t = -t;
        u = -u;
    }
    return {{t, den}, {u, den}, {a.ax * den + t * rx, a.ay * den + t * ry, den}};
}
std::optional<Intersection> crossing(OriginalLine a, OriginalLine b) {
    if (!directionCross(a, b))
        return std::nullopt;
    Intersection value = intersection(a, b);
    if (value.first.numerator <= 0 || value.first.compare(Fraction(1)) >= 0 ||
        value.second.numerator <= 0 || value.second.compare(Fraction(1)) >= 0)
        return std::nullopt;
    return value;
}
Point lineIntersection(OriginalLine a, OriginalLine b) { return intersection(a, b).point; }
bool onEdge(Point p, const Ring &ring, std::size_t index) {
    Point a = ring.points[index], b = ring.points[(index + 1) % ring.points.size()];
    return lineCross(ring.edges[index], p) == 0 && between(p.xValue(), a.xValue(), b.xValue()) &&
           between(p.yValue(), a.yValue(), b.yValue());
}
