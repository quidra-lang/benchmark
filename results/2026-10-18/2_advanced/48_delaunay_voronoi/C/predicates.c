#include "geometry.h"
Integer orient(Point p, Point q, Point r) {
    return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
}
Integer d2(Point p, Point q) {
    return (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y);
}
Integer dot(Point o, Point p, Point q) {
    return (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y);
}
Integer incircle(Point a, Point b, Point c, Point d) {
    a = (Point){a.x - d.x, a.y - d.y};
    b = (Point){b.x - d.x, b.y - d.y};
    c = (Point){c.x - d.x, c.y - d.y};
    const Integer aa = a.x * a.x + a.y * a.y, bb = b.x * b.x + b.y * b.y, cc = c.x * c.x + c.y * c.y;
    return a.x * (b.y * cc - bb * c.y) - a.y * (b.x * cc - bb * c.x) + aa * (b.x * c.y - b.y * c.x);
}
Center center(Point a, Point b, Point c) {
    const Point u = {b.x - a.x, b.y - a.y}, v = {c.x - a.x, c.y - a.y};
    const Integer dd = 2 * (u.x * v.y - u.y * v.x), uu = u.x * u.x + u.y * u.y, vv = v.x * v.x + v.y * v.y;
    return (Center){a.x * dd + v.y * uu - u.y * vv, a.y * dd + u.x * vv - v.x * uu, dd};
}
static Integer gcd(Integer a, Integer b) {
    if (a < 0)
        a = -a;
    if (b < 0)
        b = -b;
    while (b) {
        const Integer r = a % b;
        a = b;
        b = r;
    }
    return a;
}
const char *fraction(Integer numerator, Integer denominator) {
    static char buffers[64][96];
    static unsigned next;
    char *out = buffers[next++ % 64];
    const Integer divisor = gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;
    if (denominator == 1)
        snprintf(out, 96, "%lld", (long long)numerator);
    else
        snprintf(out, 96, "%lld/%lld", (long long)numerator, (long long)denominator);
    return out;
}
Point outward(Point u, Point v) {
    const Integer dx = v.x - u.x, dy = v.y - u.y, g = gcd(dx, dy);
    return (Point){dy / g, -dx / g};
}
Triangle canonical(Triangle t) {
    if (t.b < t.a && t.b < t.c)
        return (Triangle){t.b, t.c, t.a};
    if (t.c < t.a && t.c < t.b)
        return (Triangle){t.c, t.a, t.b};
    return t;
}
