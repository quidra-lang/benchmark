final class Predicates {
    record Point(long x, long y) {}
    record Center(long x, long y, long d) {}
    static long orient(Point p, Point q, Point r) {
        return (q.x() - p.x()) * (r.y() - p.y()) - (q.y() - p.y()) * (r.x() - p.x());
    }
    static long d2(Point p, Point q) {
        long x = p.x() - q.x(), y = p.y() - q.y();
        return x * x + y * y;
    }
    static long dot(Point o, Point p, Point q) {
        return (p.x() - o.x()) * (q.x() - o.x()) + (p.y() - o.y()) * (q.y() - o.y());
    }
    static long incircle(Point a, Point b, Point c, Point d) {
        long ax = a.x() - d.x(), ay = a.y() - d.y(), bx = b.x() - d.x(), by = b.y() - d.y(),
             cx = c.x() - d.x(), cy = c.y() - d.y(), aa = ax * ax + ay * ay, bb = bx * bx + by * by,
             cc = cx * cx + cy * cy;
        return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx);
    }
    static Center center(Point a, Point b, Point c) {
        long bx = b.x() - a.x(), by = b.y() - a.y(), cx = c.x() - a.x(), cy = c.y() - a.y(),
             bb = bx * bx + by * by, cc = cx * cx + cy * cy, d = 2 * (bx * cy - by * cx);
        return new Center(a.x() * d + cy * bb - by * cc, a.y() * d + bx * cc - cx * bb, d);
    }
    static long gcd(long a, long b) {
        a = Math.abs(a);
        b = Math.abs(b);
        while (b != 0) {
            long rest = a % b;
            a = b;
            b = rest;
        }
        return a;
    }
    static String fraction(long n, long d) {
        long g = gcd(n, d);
        n /= g;
        d /= g;
        return d == 1 ? Long.toString(n) : n + "/" + d;
    }
    static Point reduce(long x, long y) {
        long g = gcd(x, y);
        return new Point(x / g, y / g);
    }
}
