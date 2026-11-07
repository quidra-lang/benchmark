#include "geometry.hpp"
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
    a = {a.x - d.x, a.y - d.y};
    b = {b.x - d.x, b.y - d.y};
    c = {c.x - d.x, c.y - d.y};
    const Integer aa = a.x * a.x + a.y * a.y, bb = b.x * b.x + b.y * b.y, cc = c.x * c.x + c.y * c.y;
    return a.x * (b.y * cc - bb * c.y) - a.y * (b.x * cc - bb * c.x) + aa * (b.x * c.y - b.y * c.x);
}
Center center(Point a, Point b, Point c) {
    const Point u{b.x - a.x, b.y - a.y}, v{c.x - a.x, c.y - a.y};
    const Integer dd = 2 * (u.x * v.y - u.y * v.x), uu = u.x * u.x + u.y * u.y, vv = v.x * v.x + v.y * v.y;
    return {a.x * dd + v.y * uu - u.y * vv, a.y * dd + u.x * vv - v.x * uu, dd};
}
std::string fraction(Integer numerator, Integer denominator) {
    const Integer divisor = std::gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;
    return std::to_string(numerator) + (denominator == 1 ? "" : "/" + std::to_string(denominator));
}
Point outward(Point u, Point v) {
    const Integer dx = v.x - u.x, dy = v.y - u.y, g = std::gcd(dx, dy);
    return {dy / g, -dx / g};
}
Triangle canonical(Triangle triangle) {
    const int start = std::min_element(triangle.begin(), triangle.end()) - triangle.begin();
    return {triangle[start], triangle[(start + 1) % 3], triangle[(start + 2) % 3]};
}
