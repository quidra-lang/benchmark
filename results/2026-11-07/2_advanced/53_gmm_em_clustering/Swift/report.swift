import Foundation

let levelCharacters = Array(" .:-=+*#%@").map(String.init)
func decimal(_ value: Double, _ places: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text
}
func writtenValue(_ value: Double) -> Double { Double(decimal(value))! }
func optionalDecimal(_ value: Double?) -> String { value.map { decimal($0) } ?? "-" }
func integers(_ values: [Int]) -> String { values.map(String.init).joined(separator: " ") }
func reals(_ values: [Double]) -> String { values.map { decimal($0) }.joined(separator: " ") }
func vectorText(_ value: Vector2) -> String { reals([value.x, value.y]) }
func covarianceText(_ value: Covariance) -> String { reals([value.a, value.b, value.c]) }
func framed(_ grid: [[String]]) -> [String] { let border = "+" + String(repeating: "-", count: grid[0].count) + "+"; return [border] + grid.map { "|" + $0.joined() + "|" } + [border] }
func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + filename, atomically: false, encoding: .ascii)
}
func writeBlocks(_ filename: String, _ blocks: [[String]]) throws { var lines: [String] = []; for (index, block) in blocks.enumerated() { if index > 0 { lines.append("") }; lines += block }; try writeLines(filename, lines) }
