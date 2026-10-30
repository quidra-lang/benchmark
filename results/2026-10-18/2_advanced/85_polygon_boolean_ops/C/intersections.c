#include "geometry.h"
static bool between(Fraction value, Fraction a, Fraction b) {
    if (fraction_compare(a, b) > 0) {
        Fraction temporary = a;
        a = b;
        b = temporary;
    }
    return fraction_compare(a, value) <= 0 && fraction_compare(value, b) <= 0;
}
bool on_segment(Point p, Point a, Point b) {
    return line_cross(original_line(a, b), p) == 0 && between(point_x(p), point_x(a), point_x(b)) &&
           between(point_y(p), point_y(a), point_y(b));
}
static int sign(Integer value) { return (value > 0) - (value < 0); }
bool touching(Point a, Point b, Point c, Point d) {
    int x = sign(integer_cross(a, b, c)), y = sign(integer_cross(a, b, d)),
        z = sign(integer_cross(c, d, a)), w = sign(integer_cross(c, d, b));
    return (x * y < 0 && z * w < 0) || on_segment(c, a, b) || on_segment(d, a, b) ||
           on_segment(a, c, d) || on_segment(b, c, d);
}
bool overlapping(Point a, Point b, Point c, Point d) {
    if (integer_cross(a, b, c) || integer_cross(a, b, d))
        return false;
    Fraction aa = point_x(a), bb = point_x(b), cc = point_x(c), dd = point_x(d);
    if (fraction_compare(aa, bb) == 0) {
        aa = point_y(a);
        bb = point_y(b);
        cc = point_y(c);
        dd = point_y(d);
    }
    if (fraction_compare(aa, bb) > 0) {
        Fraction t = aa;
        aa = bb;
        bb = t;
    }
    if (fraction_compare(cc, dd) > 0) {
        Fraction t = cc;
        cc = dd;
        dd = t;
    }
    if (fraction_compare(cc, aa) > 0)
        aa = cc;
    if (fraction_compare(dd, bb) < 0)
        bb = dd;
    return fraction_compare(aa, bb) < 0;
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
    return (Intersection){fraction(t, den), fraction(u, den),
                          point(a.ax * den + t * rx, a.ay * den + t * ry, den)};
}
bool crossing(OriginalLine a, OriginalLine b, Intersection *out) {
    if (!direction_cross(a, b))
        return false;
    Intersection value = intersection(a, b);
    if (value.first.n <= 0 || fraction_compare(value.first, fraction(1, 1)) >= 0 ||
        value.second.n <= 0 || fraction_compare(value.second, fraction(1, 1)) >= 0)
        return false;
    *out = value;
    return true;
}
Point line_intersection(OriginalLine a, OriginalLine b) { return intersection(a, b).point; }
bool on_edge(Point p, const Ring *ring, size_t index) {
    Point a = ring->points[index], b = ring->points[(index + 1) % ring->count];
    return line_cross(ring->edges[index], p) == 0 && between(point_x(p), point_x(a), point_x(b)) &&
           between(point_y(p), point_y(a), point_y(b));
}
