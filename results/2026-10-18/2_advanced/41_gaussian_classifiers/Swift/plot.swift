import Foundation

func real(_ value: Double) -> String {
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}

func reals(_ values: [Double]) -> String { values.map(real).joined(separator: " ") }

func fractionText(_ value: Fraction?) -> String {
    guard let value else { return "-" }
    return "\(value.numerator)/\(value.denominator) \(real(Double(value.numerator) / Double(value.denominator)))"
}

func ratioText(_ numerator: Int, _ denominator: Int) -> String { fractionText(reducedFraction(numerator, denominator)) }

func frame(_ grid: [[String]]) -> [String] {
    let border = "+" + String(repeating: "-", count: grid[0].count) + "+"
    return [border] + grid.map { "|" + $0.joined() + "|" } + [border]
}

func cell(_ value: Double, _ low: Double, _ high: Double, _ size: Int) -> Int {
    Int(floor((value - low) / (high - low) * Double(size - 1) + 0.5))
}

func joinSections(_ sections: [[String]]) -> [String] {
    var lines: [String] = []
    for section in sections {
        if !lines.isEmpty { lines.append("") }
        lines += section
    }
    return lines
}

func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}
