import Foundation

func real(_ value: Double) -> String {
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}

func reals(_ values: [Double]) -> String { values.map(real).joined(separator: " ") }
func fourDecimal(_ value: Double) -> Int64 { Int64((value * 10000).rounded()) }

func amount(_ cents: Int64) -> String {
    let sign = cents < 0 ? "-" : ""
    let magnitude = abs(cents)
    let remainder = magnitude % 100
    return "\(sign)\(magnitude / 100).\(remainder < 10 ? "0" : "")\(remainder)"
}

func writeLines(_ path: String, _ lines: [String]) throws {
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
