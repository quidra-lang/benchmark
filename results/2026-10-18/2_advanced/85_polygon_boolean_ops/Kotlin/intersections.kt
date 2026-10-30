object Intersections {
    fun on(a: Point, b: Point, p: Point): Boolean = cross(a, b, p) == ZERO &&
        xCompare(p, if (xCompare(a, b) < 0) a else b) >= 0 && xCompare(p, if (xCompare(a, b) < 0) b else a) <= 0 &&
        yCompare(p, if (yCompare(a, b) < 0) a else b) >= 0 && yCompare(p, if (yCompare(a, b) < 0) b else a) <= 0
    fun touch(a: Point, b: Point, c: Point, d: Point): Boolean =
        cross(a, b, c).signum() * cross(a, b, d).signum() < 0 && cross(c, d, a).signum() * cross(c, d, b).signum() < 0 ||
        on(a, b, c) || on(a, b, d) || on(c, d, a) || on(c, d, b)
    fun overlap(a: Point, b: Point, c: Point, d: Point): Boolean {
        if (cross(a, b, c) != ZERO || cross(a, b, d) != ZERO) return false
        val compare: (Point, Point) -> Int = if (xCompare(a, b) != 0) ::xCompare else ::yCompare
        val abMin = if (compare(a, b) < 0) a else b
        val abMax = if (compare(a, b) < 0) b else a
        val cdMin = if (compare(c, d) < 0) c else d
        val cdMax = if (compare(c, d) < 0) d else c
        return compare(if (compare(abMin, cdMin) < 0) cdMin else abMin, if (compare(abMax, cdMax) < 0) abMax else cdMax) < 0
    }
    fun line(a: Point, b: Point): Triple<BI, BI, BI> {
        val x = a.y * b.d - a.d * b.y
        val y = a.d * b.x - a.x * b.d
        val z = a.x * b.y - a.y * b.x
        val g = x.gcd(y).gcd(z)
        return Triple(x / g, y / g, z / g)
    }
    fun lineIntersection(a: Point, b: Point, c: Point, d: Point): Point {
        val (x, y, z) = line(a, b)
        val (u, v, w) = line(c, d)
        return Point(y * w - z * v, z * u - x * w, x * v - y * u)
    }
    fun crossing(a: Point, b: Point, c: Point, d: Point): Triple<Point, Fraction, Fraction>? {
        val rx = b.x - a.x
        val ry = b.y - a.y
        val sx = d.x - c.x
        val sy = d.y - c.y
        var den = rx * sy - ry * sx
        if (den == ZERO) return null
        val gx = c.x - a.x
        val gy = c.y - a.y
        var t = gx * sy - gy * sx
        var u = gx * ry - gy * rx
        if (den < ZERO) { den = -den; t = -t; u = -u }
        if (t <= ZERO || t >= den || u <= ZERO || u >= den) return null
        return Triple(Point(a.x * den + t * rx, a.y * den + t * ry, den), Fraction(t, den), Fraction(u, den))
    }
    fun segment(a: Point, b: Point): String = "$a-$b"
}
