using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Predicates {
    public record Point(long x, long y) {
    }
    public record Center(long x, long y, long d) {
    }
    public static long Orient(Point p, Point q, Point r) {
        return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
    }
    public static long D2(Point p, Point q) {
        long x = p.x - q.x, y = p.y - q.y;
        return x * x + y * y;
    }
    public static long Dot(Point o, Point p, Point q) {
        return (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y);
    }
    public static long Incircle(Point a, Point b, Point c, Point d) {
        long ax = a.x - d.x, ay = a.y - d.y, bx = b.x - d.x, by = b.y - d.y, cx = c.x - d.x, cy = c.y - d.y,
             aa = ax * ax + ay * ay, bb = bx * bx + by * by, cc = cx * cx + cy * cy;
        return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx);
    }
    public static Center Circumcenter(Point a, Point b, Point c) {
        long bx = b.x - a.x, by = b.y - a.y, cx = c.x - a.x, cy = c.y - a.y, bb = bx * bx + by * by,
             cc = cx * cx + cy * cy, d = 2 * (bx * cy - by * cx);
        return new Center(a.x * d + cy * bb - by * cc, a.y * d + bx * cc - cx * bb, d);
    }
    public static long Gcd(long a, long b) {
        a = Math.Abs(a);
        b = Math.Abs(b);
        while (b != 0) {
            long rest = a % b;
            a = b;
            b = rest;
        }
        return a;
    }
    public static string Fraction(long n, long d) {
        long g = Gcd(n, d);
        n /= g;
        d /= g;
        return d == 1 ? Convert.ToString(n) : n + "/" + d;
    }
    public static Point Reduce(long x, long y) {
        long g = Gcd(x, y);
        return new Point(x / g, y / g);
    }
}
