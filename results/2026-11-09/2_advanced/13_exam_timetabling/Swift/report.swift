import Foundation

func fixedWidthLine(_ label: String, _ cells: [String], _ labelWidth: Int, _ cellWidth: Int) -> String {
    label + String(repeating: " ", count: max(0, labelWidth - label.utf8.count))
        + cells.map { String(repeating: " ", count: max(0, cellWidth - $0.utf8.count)) + $0 }.joined()
}

func roundedPercent(_ part: Int, _ whole: Int) -> Int {
    (200 * part + whole) / (2 * whole)
}

func writeFiles(_ directory: String, _ files: [(String, [String])]) throws {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for (name, lines) in files {
        try (lines.joined(separator: "\n") + "\n").write(toFile: "\(directory)/\(name)", atomically: true, encoding: .utf8)
    }
}
