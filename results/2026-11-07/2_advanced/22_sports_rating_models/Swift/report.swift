import Foundation

struct Fraction: Comparable {
    let numerator: Int
    let denominator: Int
    init(_ numerator: Int, _ denominator: Int = 1) {
        let sign = denominator < 0 ? -1 : 1
        let n = numerator * sign, d = denominator * sign
        var a = abs(n), b = d
        while b != 0 { (a, b) = (b, a % b) }
        self.numerator = n / a; self.denominator = d / a
    }
    var real: Double { Double(numerator) / Double(denominator) }
    var text: String { "\(numerator)/\(denominator)" }
    func fixed(_ places: Int = 4) -> String {
        var scale = 1
        for _ in 0..<places { scale *= 10 }
        var whole = abs(numerator) / denominator, remainder = abs(numerator) % denominator, digits = 0
        for _ in 0..<places {
            remainder *= 10; digits = digits * 10 + remainder / denominator; remainder %= denominator
        }
        if 2 * remainder >= denominator { digits += 1 }
        if digits == scale { whole += 1; digits = 0 }
        let fraction = String(digits)
        return (numerator < 0 && (whole > 0 || digits > 0) ? "-" : "") + String(whole) + "." + String(repeating: "0", count: places - fraction.count) + fraction
    }
    var withReal: String { text + " " + fixed() }
    static func < (first: Fraction, second: Fraction) -> Bool { first.numerator * second.denominator < second.numerator * first.denominator }
    static func + (first: Fraction, second: Fraction) -> Fraction { Fraction(first.numerator * second.denominator + second.numerator * first.denominator, first.denominator * second.denominator) }
    static func - (first: Fraction, second: Fraction) -> Fraction { Fraction(first.numerator * second.denominator - second.numerator * first.denominator, first.denominator * second.denominator) }
    static func * (first: Fraction, second: Fraction) -> Fraction { Fraction(first.numerator * second.numerator, first.denominator * second.denominator) }
    static func / (first: Fraction, second: Fraction) -> Fraction { Fraction(first.numerator * second.denominator, first.denominator * second.numerator) }
}
func decimalValue(_ value: Double, _ places: Int) -> Int { Int((value * pow(10.0, Double(places))).rounded()) }
func fixed(_ value: Double, _ places: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
}
func writeLines(_ path: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8) }
