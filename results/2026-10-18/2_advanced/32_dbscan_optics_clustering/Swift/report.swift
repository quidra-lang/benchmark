import Foundation

func fraction(_ a: Int, _ b: Int) -> String {
    var x = abs(a)
    var y = b
    while y != 0 {
        let remainder = x % y
        x = y
        y = remainder
    }
    return "\(a / x)/\(b / x)"
}

func root(_ value: Int) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), sqrt(Double(value)))
}

func ari(_ a: Int, _ b: Int) -> String {
    let value = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), Double(a) / Double(b))
    return fraction(a, b) + " " + (value == "-0.0000" ? "0.0000" : value)
}

func framed(_ rows: [String], _ width: Int) -> [String] {
    let border = "+" + String(repeating: "-", count: width) + "+"
    return [border] + rows.map { "|" + $0 + "|" } + [border]
}

func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n")
        .write(toFile: "output/" + name, atomically: true, encoding: .ascii)
}
