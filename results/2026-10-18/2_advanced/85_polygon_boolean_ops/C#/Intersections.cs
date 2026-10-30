static class Intersections
{
    public static bool On(Point a, Point b, Point p) => Cross(a, b, p).IsZero &&
        XCompare(p, XCompare(a, b) < 0 ? a : b) >= 0 && XCompare(p, XCompare(a, b) < 0 ? b : a) <= 0 &&
        YCompare(p, YCompare(a, b) < 0 ? a : b) >= 0 && YCompare(p, YCompare(a, b) < 0 ? b : a) <= 0;
    public static bool Touch(Point a, Point b, Point c, Point d) =>
        Cross(a, b, c).Sign * Cross(a, b, d).Sign < 0 && Cross(c, d, a).Sign * Cross(c, d, b).Sign < 0 ||
        On(a, b, c) || On(a, b, d) || On(c, d, a) || On(c, d, b);
    public static bool Overlap(Point a, Point b, Point c, Point d)
    {
        if (!Cross(a, b, c).IsZero || !Cross(a, b, d).IsZero) return false;
        Comparison<Point> compare = XCompare(a, b) != 0 ? XCompare : YCompare;
        Point abMin = compare(a, b) < 0 ? a : b;
        Point abMax = compare(a, b) < 0 ? b : a;
        Point cdMin = compare(c, d) < 0 ? c : d;
        Point cdMax = compare(c, d) < 0 ? d : c;
        return compare(compare(abMin, cdMin) < 0 ? cdMin : abMin, compare(abMax, cdMax) < 0 ? abMax : cdMax) < 0;
    }
    static (BigInteger X, BigInteger Y, BigInteger Z) Line(Point a, Point b)
    {
        BigInteger x = a.Y * b.D - a.D * b.Y;
        BigInteger y = a.D * b.X - a.X * b.D;
        BigInteger z = a.X * b.Y - a.Y * b.X;
        BigInteger g = BigInteger.GreatestCommonDivisor(BigInteger.GreatestCommonDivisor(x, y), z);
        return (x / g, y / g, z / g);
    }
    public static Point LineIntersection(Point a, Point b, Point c, Point d)
    {
        var (x, y, z) = Line(a, b);
        var (u, v, w) = Line(c, d);
        return new Point(y * w - z * v, z * u - x * w, x * v - y * u);
    }
    public static (Point Point, Fraction T, Fraction U)? Crossing(Point a, Point b, Point c, Point d)
    {
        BigInteger rx = b.X - a.X, ry = b.Y - a.Y, sx = d.X - c.X, sy = d.Y - c.Y;
        BigInteger den = rx * sy - ry * sx;
        if (den.IsZero) return null;
        BigInteger gx = c.X - a.X, gy = c.Y - a.Y;
        BigInteger t = gx * sy - gy * sx, u = gx * ry - gy * rx;
        if (den < 0) { den = -den; t = -t; u = -u; }
        if (t <= 0 || t >= den || u <= 0 || u >= den) return null;
        return (new Point(a.X * den + t * rx, a.Y * den + t * ry, den), new Fraction(t, den), new Fraction(u, den));
    }
    public static string Segment(Point a, Point b) => $"{a}-{b}";
}
