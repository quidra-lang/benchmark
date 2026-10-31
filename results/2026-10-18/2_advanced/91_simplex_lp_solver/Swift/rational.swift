struct Fraction: Comparable, CustomStringConvertible {
    let n: Int, d: Int
    init(_ n: Int, _ d: Int = 1) {
        var a = abs(n), b = abs(d)
        while b != 0 {
            let r = a % b;
            a = b;
            b = r
        }
        let sign = d < 0 ? -1 : 1
        self.n = n / a * sign;
        self.d = d / a * sign
    }
    static func < (a: Self, b: Self) -> Bool {
        a.n * b.d < b.n * a.d
    }
    static func + (a: Self, b: Self) -> Self {
        Self(a.n * b.d + b.n * a.d, a.d * b.d)
    }
    static func - (a: Self, b: Self) -> Self {
        Self(a.n * b.d - b.n * a.d, a.d * b.d)
    }
    static func * (a: Self, b: Self) -> Self {
        Self(a.n * b.n, a.d * b.d)
    }
    static func / (a: Self, b: Self) -> Self {
        Self(a.n * b.d, a.d * b.n)
    }
    static prefix func - (a: Self) -> Self {
        Self(-a.n, a.d)
    }
    var floor: Int {
        n / d - (n % d < 0 ? 1 : 0)
    }
    var ceil: Int {
        n / d + (n % d > 0 ? 1 : 0)
    }
    var absolute: Self {
        Self(abs(n), d)
    }
    var description: String {
        d == 1 ? String(n) : "\(n)/\(d)"
    }
    var approximate: String {
        let t = (2 * abs(n) * 1_000_000 + d) / (2 * d), remainder = String(t % 1_000_000)
        return (n < 0 && t > 0 ? "-" : "") + String(t / 1_000_000) + "." + String(repeating: "0", count: 6 - remainder.count) + remainder
    }
    static func parse(_ original: String) -> Self? {
        let negative = original.first == "-", text = negative ? String(original.dropFirst()) : original
        func digits(_ text: String) -> Bool {
            !text.isEmpty && text.utf8.allSatisfy {
                (48...57).contains($0)
            }
        }
        let value: Self
        if digits(text), let number = Int(text) {
            value = Self(number)
        }
        else if text.contains(".") {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, digits(parts[0]), digits(parts[1]), let numerator = Int(parts[0] + parts[1]) else {
                return nil
            }
            var denominator = 1
            for _ in parts[1] {
                denominator *= 10
            }
            value = Self(numerator, denominator)
        } else {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, digits(parts[0]), digits(parts[1]), let numerator = Int(parts[0]), let denominator = Int(parts[1]), denominator != 0 else {
                return nil
            }
            value = Self(numerator, denominator)
        }
        return negative ? -value : value
    }
}
