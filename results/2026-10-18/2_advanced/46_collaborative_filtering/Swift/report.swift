import Foundation

func real(_ value: Double?) -> String {
    guard let value else { return "-" }
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}

func optional(_ value: Int?) -> String { value.map(String.init) ?? "-" }

func writeLines(_ name: String, _ lines: [String]) throws {
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
