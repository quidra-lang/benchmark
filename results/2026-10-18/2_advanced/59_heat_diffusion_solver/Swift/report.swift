import Foundation

func real(_ value: Double, _ places: Int) -> String { let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
func timeText(_ milliseconds: Int) -> String { let remainder = String(milliseconds % 1000); return "\(milliseconds / 1000)." + String(repeating: "0", count: 3 - remainder.count) + remainder }
func temperatureLines(_ mesh: Mesh, _ field: [Double]) -> [String] { (0..<mesh.height).map { row in (0..<mesh.width).map { real(field[mesh.cell(row, $0)], 2) }.joined(separator: " ") } }
func isothermLines(_ mesh: Mesh, _ field: [Double], _ bands: [Double]) -> (counts: [Int], lines: [String]) {
    let hottest = hottestCell(field)
    var counts = Array(repeating: 0, count: bands.count + 1), characters: [String] = []
    for (point, temperature) in field.enumerated() { let digit = bands.filter { $0 <= temperature }.count; counts[digit] += 1; characters.append(point == hottest ? "*" : String(digit)) }
    return (counts, (0..<mesh.height).map { characters[($0 * mesh.width)..<(($0 + 1) * mesh.width)].joined() })
}
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
