import Foundation

func money(_ cents: Int) -> String {
    let fraction = String(cents % 100)
    return "\(cents / 100)." + String(repeating: "0", count: 2 - fraction.count) + fraction
}
func percent(_ part: Int, _ whole: Int) -> Int { (200 * part + whole) / (2 * whole) }
func tableRow(_ label: String, values: [Int], width: Int) -> String {
    label + String(repeating: " ", count: 10 - label.count) + values.map {
        let text = String($0)
        return String(repeating: " ", count: max(0, width - text.count)) + text
    }.joined()
}
func writeReport(_ name: String, lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}
