import Foundation

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    var a = numerator, b = denominator
    while b != 0 { let remainder = a % b; a = b; b = remainder }
    return "\(numerator / a)/\(denominator / a)"
}

func ids<S: Sequence>(_ values: S) -> String where S.Element == Int { let text = values.map(String.init).joined(separator: " "); return text.isEmpty ? "-" : text }
struct ObjectDistance: Equatable { let id: Int; let distance: Int }
func distances(_ values: [ObjectDistance]) -> String { let text = values.map { "\($0.id):\($0.distance)" }.joined(separator: " "); return text.isEmpty ? "-" : text }
func writeLines(_ name: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
