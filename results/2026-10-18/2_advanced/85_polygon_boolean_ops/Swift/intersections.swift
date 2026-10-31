enum Intersections {
    static func on(_ a: Point, _ b: Point, _ p: Point) -> Bool {
        cross(a, b, p) == 0 && !xLess(p, xLess(a, b) ? a : b) && !xLess(xLess(a, b) ? b : a, p) && !yLess(p, yLess(a, b) ? a : b) && !yLess(yLess(a, b) ? b : a, p)
    }
    static func touch(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
        func opposite(_ x: Int128, _ y: Int128) -> Bool {
            x < 0 && y > 0 || x > 0 && y < 0
        }
        return opposite(cross(a, b, c), cross(a, b, d)) && opposite(cross(c, d, a), cross(c, d, b)) || on(a, b, c) || on(a, b, d) || on(c, d, a) || on(c, d, b)
    }
    static func overlap(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Bool {
        if cross(a, b, c) != 0 || cross(a, b, d) != 0 {
            return false
        }
        let less: (Point, Point) -> Bool = a.x * b.d != b.x * a.d ? xLess : yLess
        let abMin = less(a, b) ? a : b, abMax = less(a, b) ? b : a
        let cdMin = less(c, d) ? c : d, cdMax = less(c, d) ? d : c
        return less(less(abMin, cdMin) ? cdMin : abMin, less(abMax, cdMax) ? abMax : cdMax)
    }
    static func line(_ a: Point, _ b: Point) -> (Int128, Int128, Int128) {
        let x = a.y * b.d - a.d * b.y, y = a.d * b.x - a.x * b.d, z = a.x * b.y - a.y * b.x
        let g = gcd(gcd(x, y), z)
        return (x / g, y / g, z / g)
    }
    static func lineIntersection(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Point {
        let (x, y, z) = line(a, b), (u, v, w) = line(c, d)
        return Point(y * w - z * v, z * u - x * w, x * v - y * u)
    }
    static func crossing(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> (Point, Fraction, Fraction)? {
        let rx = b.x - a.x, ry = b.y - a.y, sx = d.x - c.x, sy = d.y - c.y
        var den = rx * sy - ry * sx
        if den == 0 {
            return nil
        }
        let gx = c.x - a.x, gy = c.y - a.y
        var nt = gx * sy - gy * sx, nu = gx * ry - gy * rx
        if den < 0 {
            den = -den;
            nt = -nt;
            nu = -nu
        }
        if nt <= 0 || nt >= den || nu <= 0 || nu >= den {
            return nil
        }
        return (Point(a.x * den + nt * rx, a.y * den + nt * ry, den), Fraction(nt, den), Fraction(nu, den))
    }
    static func segment(_ a: Point, _ b: Point) -> String {
        "\(a)-\(b)"
    }
}
