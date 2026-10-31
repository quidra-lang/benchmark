import Foundation
struct Fraction: Comparable, CustomStringConvertible {
    let n: Int, d: Int
    static func gcd(_ x: Int, _ y: Int) -> Int {
        var a = abs(x), b = abs(y)
        while b != 0 {
            let remainder = a % b;
            a = b;
            b = remainder
        }
        return a
    }
    init(_ n: Int, _ d: Int = 1) {
        let g = Self.gcd(n, d), sign = d < 0 ? -1 : 1
        self.n = n / g * sign
        self.d = d / g * sign
    }
    static func < (a: Self, b: Self) -> Bool {
        a.n * b.d < b.n * a.d
    }
    static func + (a: Self, b: Self) -> Self {
        let g = gcd(a.d, b.d)
        return Self(a.n * (b.d / g) + b.n * (a.d / g), a.d / g * b.d)
    }
    static func - (a: Self, b: Self) -> Self {
        a + Self(-b.n, b.d)
    }
    static func * (a: Self, b: Self) -> Self {
        let x = gcd(a.n, b.d), y = gcd(b.n, a.d)
        return Self((a.n / x) * (b.n / y), (a.d / y) * (b.d / x))
    }
    static func / (a: Self, b: Self) -> Self {
        a * Self(b.d, b.n)
    }
    var description: String {
        d == 1 ? String(n) : "\(n)/\(d)"
    }
}
enum Report {
    static func bundle(_ mask: Int, _ names: [String]) -> String {
        let items = names.indices.filter {
            mask & (1 << $0) != 0
        }.map {
            names[$0]
        }
        return items.isEmpty ? "-" : items.joined(separator: "+")
    }
    static func numbers(_ values: [Int]) -> String {
        values.isEmpty ? "-" : values.map(String.init).joined(separator: "+")
    }
    static func write(_ file: String, _ lines: [String]) {
        try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + file, atomically: false, encoding: .ascii)
    }
}
