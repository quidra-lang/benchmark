import Foundation

func real(_ value: Double) -> String { let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value); return text == "-0.0000" ? "0.0000" : text }
func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func writeCSV(_ name: String, _ header: String, _ rows: [[String]]) throws { try writeLines(name, [header] + rows.map { $0.joined(separator: ",") }) }
func shadeLines(_ grid: [[Double]], _ sampleRate: Double, _ length: Int, _ bandDB: Int) -> [String] {
    let maximum = grid.flatMap { $0 }.max()!, shades = Array(" .:-=+*#%@").map(String.init)
    return (0...(length / 2)).reversed().map { k in
        let label = real(Double(k) * sampleRate / Double(length)), padded = String(repeating: " ", count: max(0, 9 - label.count)) + label
        let pixels = grid.map { row -> String in let d = 20 * log10(row[k] / maximum), level = max(0, 9 - Int(floor(-d / Double(bandDB)))); return shades[level] }.joined()
        return padded + " |" + pixels + "|"
    }
}
