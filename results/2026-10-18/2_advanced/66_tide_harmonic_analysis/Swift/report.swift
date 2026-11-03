import Foundation

func decimal(_ value: Double, _ places: Int) -> String { let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
func optional(_ value: Double?, _ places: Int) -> String { value.map { decimal($0, places) } ?? "none" }
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
func renderPlot(_ grid: [[String]], _ top: Int, _ step: Int) -> [String] {
    let rows = grid.count, width = grid[0].count
    let labels = (0..<rows).map { decimal(Double(top - $0 * step) / 100, 2) }, labelWidth = labels.map { $0.count }.max()!
    return (0..<rows).map { String(repeating: " ", count: labelWidth - labels[$0].count) + labels[$0] + " |" + grid[$0].joined() + "|" } + [String(repeating: " ", count: labelWidth + 1) + "+" + (0..<width).map { $0 % 6 == 0 ? "+" : "-" }.joined() + "+"]
}
