import Foundation
func gcd(_ x: Int128, _ y: Int128) -> Int128 {
    var a = abs(x), b = abs(y)
    while b != 0 {
        let r = a % b;
        a = b;
        b = r
    }
    return a
}
struct Fraction: Comparable, CustomStringConvertible {
    let n: Int128, d: Int128
    init(_ n: Int128, _ d: Int128 = 1) {
        let g = gcd(n, d), sign: Int128 = d < 0 ? -1 : 1
        self.n = n / g * sign;
        self.d = d / g * sign
    }
    static func < (a: Self, b: Self) -> Bool {
        a.n * b.d < b.n * a.d
    }
    var description: String {
        d == 1 ? String(n) : "\(n)/\(d)"
    }
}
struct Point: Hashable, Comparable, CustomStringConvertible {
    let x: Int128, y: Int128, d: Int128
    init(_ x: Int128, _ y: Int128, _ d: Int128 = 1) {
        let g = gcd(gcd(x, y), d), sign: Int128 = d < 0 ? -1 : 1
        self.x = x / g * sign;
        self.y = y / g * sign;
        self.d = d / g * sign
    }
    static func < (a: Self, b: Self) -> Bool {
        a.y * b.d == b.y * a.d ? a.x * b.d < b.x * a.d : a.y * b.d < b.y * a.d
    }
    var real: (Double, Double) {
        (Double(x) / Double(d), Double(y) / Double(d))
    }
    var snapped: Point {
        func floorDivide(_ a: Int128, _ b: Int128) -> Int128 {
            let q = a / b;
            return a % b < 0 ? q - 1 : q
        }
        return Point(floorDivide(2 * x + d, 2 * d), floorDivide(2 * y + d, 2 * d))
    }
    var description: String {
        "(\(Fraction(x, d)),\(Fraction(y, d)))"
    }
}
func cross(_ a: Point, _ b: Point, _ c: Point) -> Int128 {
    (b.x * c.y - b.y * c.x) * a.d + (c.x * a.y - c.y * a.x) * b.d + (a.x * b.y - a.y * b.x) * c.d
}
func xLess(_ a: Point, _ b: Point) -> Bool {
    a.x * b.d < b.x * a.d
}
func yLess(_ a: Point, _ b: Point) -> Bool {
    a.y * b.d < b.y * a.d
}
func realText(_ value: Double, _ digits: Int = 3) -> String {
    String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, value)
}
