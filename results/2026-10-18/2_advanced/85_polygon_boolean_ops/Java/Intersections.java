final class Intersections {
    static boolean onSegment(Rational.Point point, Rational.Point first, Rational.Point second) {
        return Rational.cross(first, second, point).sign() == 0 &&
            Rational.min(first.x(), second.x()).compareTo(point.x()) <= 0 &&
            point.x().compareTo(Rational.max(first.x(), second.x())) <= 0 &&
            Rational.min(first.y(), second.y()).compareTo(point.y()) <= 0 &&
            point.y().compareTo(Rational.max(first.y(), second.y())) <= 0;
    }
    static boolean touch(Rational.Point a, Rational.Point b, Rational.Point c, Rational.Point d) {
        return Rational.cross(a, b, c).sign() * Rational.cross(a, b, d).sign() < 0 &&
            Rational.cross(c, d, a).sign() * Rational.cross(c, d, b).sign() < 0 ||
            onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d);
    }
    static boolean overlap(Rational.Point a, Rational.Point b, Rational.Point c, Rational.Point d) {
        if (Rational.cross(a, b, c).sign() != 0 || Rational.cross(a, b, d).sign() != 0)
            return false;
        boolean x = !a.x().equals(b.x());
        Rational.Fraction alpha = x ? a.x() : a.y(), beta = x ? b.x() : b.y(),
                          gamma = x ? c.x() : c.y(), delta = x ? d.x() : d.y();
        return Rational.max(Rational.min(alpha, beta), Rational.min(gamma, delta))
                   .compareTo(Rational.min(Rational.max(alpha, beta), Rational.max(gamma, delta))) <
            0;
    }
    record Crossing(Rational.Fraction first, Rational.Fraction second, Rational.Point point) {}
    static Crossing crossing(Rational.Point a, Rational.Point b, Rational.Point c,
                             Rational.Point d) {
        Rational.Fraction rx = b.x().subtract(a.x()), ry = b.y().subtract(a.y()),
                          sx = d.x().subtract(c.x()), sy = d.y().subtract(c.y());
        Rational.Fraction denominator = rx.multiply(sy).subtract(ry.multiply(sx));
        if (denominator.sign() == 0)
            return null;
        Rational.Fraction gx = c.x().subtract(a.x()), gy = c.y().subtract(a.y()),
                          t = gx.multiply(sy).subtract(gy.multiply(sx)).divide(denominator),
                          u = gx.multiply(ry).subtract(gy.multiply(rx)).divide(denominator);
        if (t.sign() <= 0 || t.compareTo(Rational.ONE) >= 0 || u.sign() <= 0 ||
            u.compareTo(Rational.ONE) >= 0)
            return null;
        return new Crossing(t, u, Rational.along(a, b, t));
    }
    static Rational.Point clippingPoint(Rational.Point previous, Rational.Point current,
                                        Rational.Fraction a, Rational.Fraction b) {
        return Rational.along(previous, current, a.divide(a.subtract(b)));
    }
}
