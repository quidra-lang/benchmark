import Foundation

func fixed(_ value: Double, _ places: Int = 6) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
}

func scaled(_ value: Double, _ places: Int = 6) -> Int {
    var scale = 1.0
    for _ in 0..<places { scale *= 10 }
    return Int((value * scale).rounded())
}

private func gcd(_ first: Int, _ second: Int) -> Int {
    var a = first
    var b = second
    while b != 0 { let remainder = a % b; a = b; b = remainder }
    return a
}

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    let divisor = gcd(abs(numerator), denominator)
    let a = numerator / divisor
    let b = denominator / divisor
    return "\(a)/\(b) \(fixed(Double(a) / Double(b), 4))"
}

func writeLines(_ path: String, _ lines: [String]) throws {
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
