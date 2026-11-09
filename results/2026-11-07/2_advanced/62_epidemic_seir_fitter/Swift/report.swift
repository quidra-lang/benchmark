import Foundation

func fmt(_ value: Double, _ places: Int = 4) -> String { let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
func curvePlot(_ observed: [Int], _ fitted: [Double]) -> [String] {
    let days = observed.count, maximum = observed.max()!, width = String(maximum).count
    var grid = Array(repeating: Array(repeating: ".", count: 70), count: 20)
    for column in 0..<70 { let day = column * (days - 1) / 69, observedRow = min(19, 20 * observed[day] / maximum), fittedRow = min(19, Int(floor(20 * fitted[day] / Double(maximum)))); grid[observedRow][column] = "o"; grid[fittedRow][column] = observedRow == fittedRow ? "#" : "*" }
    var lines = ["plot observed o fitted * both # days 1 \(days) max \(maximum)"]
    for row in stride(from: 19, through: 0, by: -1) { let text = String(maximum * row / 20); lines.append(String(repeating: " ", count: width - text.count) + text + " |" + grid[row].joined()) }
    lines.append(String(repeating: " ", count: width + 1) + "+" + (0..<70).map { $0 % 10 == 0 ? "+" : "-" }.joined())
    var labels = Array(repeating: " ", count: 70)
    for column in stride(from: 0, to: 70, by: 10) { for (offset, character) in String(1 + column * (days - 1) / 69).enumerated() { labels[column + offset] = String(character) } }
    while labels.last == " " { labels.removeLast() }
    lines.append(String(repeating: " ", count: width + 2) + labels.joined())
    return lines
}
