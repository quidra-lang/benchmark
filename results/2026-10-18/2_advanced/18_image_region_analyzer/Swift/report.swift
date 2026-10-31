import Foundation

private func gcd(_ first: Int64, _ second: Int64) -> Int64 {
    var a = first
    var b = second
    while b != 0 { let remainder = a % b; a = b; b = remainder }
    return a
}
struct Rational: Equatable, Comparable {
    let numerator: Int64
    let denominator: Int64
    init(_ numerator: Int64, _ denominator: Int64 = 1) {
        let divisor = gcd(abs(numerator), denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }
    static func < (first: Rational, second: Rational) -> Bool {
        first.numerator * second.denominator < second.numerator * first.denominator
    }
}
func decimal(_ value: Rational, _ digits: Int) -> String {
    var scale: Int64 = 1
    for _ in 0..<digits { scale *= 10 }
    let rounded = (2 * scale * abs(value.numerator) + value.denominator) / (2 * value.denominator)
    let sign = value.numerator < 0 && rounded > 0 ? "-" : ""
    let remainder = String(rounded % scale)
    return "\(sign)\(rounded / scale)." + String(repeating: "0", count: digits - remainder.count) + remainder
}
func hullAreaText(_ doubled: Int64) -> String { "\(doubled / 2).\(doubled % 2 == 0 ? 0 : 5)" }
func writeFiles(_ directory: String, _ files: [(String, [String])]) throws {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for (name, lines) in files {
        try (lines.joined(separator: "\n") + "\n").write(toFile: directory + "/" + name, atomically: true, encoding: .utf8)
    }
}
