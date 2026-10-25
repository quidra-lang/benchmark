import Foundation

func fixed(_ value: Double, _ places: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
}
func fourDecimal(_ value: Double) -> Double { Double(fixed(value))! }
func ratio(_ numerator: Int, _ denominator: Int) -> String { "\(numerator)/\(denominator) \(fixed(Double(numerator) / Double(denominator)))" }
func fraction(_ numerator: Int, _ denominator: Int) -> String {
    if denominator == 0 { return "- -" }
    var first = numerator, second = denominator
    while second != 0 { let remainder = first % second; first = second; second = remainder }
    return "\(numerator / first)/\(denominator / first) \(fixed(Double(numerator) / Double(denominator)))"
}
func joinParts(_ parts: [[String]]) -> [String] { parts.enumerated().flatMap { $0.offset == 0 ? $0.element : [""] + $0.element } }
func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}
