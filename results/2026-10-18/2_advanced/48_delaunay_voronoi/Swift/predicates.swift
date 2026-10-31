import Foundation

struct Point: Hashable, Comparable {
    let x: Int
    let y: Int
    static func < (a: Point, b: Point) -> Bool { a.x == b.x ? a.y < b.y : a.x < b.x }
}

struct Center {
    let x: Int
    let y: Int
    let denominator: Int
}

func orient(_ p: Point, _ q: Point, _ r: Point) -> Int { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
func d2(_ p: Point, _ q: Point) -> Int { let x = p.x - q.x, y = p.y - q.y; return x * x + y * y }
func dot(_ o: Point, _ p: Point, _ q: Point) -> Int { (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y) }

func incircle(_ a: Point, _ b: Point, _ c: Point, _ d: Point) -> Int {
    let ax = a.x - d.x, ay = a.y - d.y, bx = b.x - d.x, by = b.y - d.y, cx = c.x - d.x, cy = c.y - d.y
    let aa = ax * ax + ay * ay, bb = bx * bx + by * by, cc = cx * cx + cy * cy
    return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx)
}

func circumcenter(_ a: Point, _ b: Point, _ c: Point) -> Center {
    let bx = b.x - a.x, by = b.y - a.y, cx = c.x - a.x, cy = c.y - a.y
    let bb = bx * bx + by * by, cc = cx * cx + cy * cy, denominator = 2 * (bx * cy - by * cx)
    return Center(x: a.x * denominator + cy * bb - by * cc, y: a.y * denominator + bx * cc - cx * bb, denominator: denominator)
}

func gcd(_ first: Int, _ second: Int) -> Int {
    var a = abs(first), b = abs(second)
    while b != 0 { let remainder = a % b; a = b; b = remainder }
    return a
}

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    let common = gcd(numerator, denominator), n = numerator / common, d = denominator / common
    return d == 1 ? String(n) : "\(n)/\(d)"
}

func reduceDirection(_ dx: Int, _ dy: Int) -> Point { let common = gcd(dx, dy); return Point(x: dx / common, y: dy / common) }
