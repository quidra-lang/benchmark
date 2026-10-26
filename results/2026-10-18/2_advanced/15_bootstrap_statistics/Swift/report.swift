import Foundation

func real(_ value: Double) -> String {
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}

func pValue(_ numerator: Int, _ denominator: Int) -> String {
    let (first, second) = reducedFraction(Int64(numerator), Int64(denominator))
    return "\(first)/\(second) \(real(Double(first) / Double(second)))"
}

func numberList(_ numbers: [Int]) -> String {
    numbers.isEmpty ? "none" : numbers.sorted().map(String.init).joined(separator: " ")
}

func binNumber(_ value: Double, _ low: Double, _ high: Double, _ bins: Int) -> Int {
    min(Int(floor(Double(bins) * (value - low) / (high - low))), bins - 1)
}

func bar(_ count: Int, _ top: Int) -> String {
    String(repeating: "#", count: (40 * count + top - 1) / top)
}

func writeLines(_ path: String, _ lines: [String]) throws {
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
