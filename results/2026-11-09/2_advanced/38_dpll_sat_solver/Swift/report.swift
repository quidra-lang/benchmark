import Foundation

func named(_ items: [(String, String)]) -> String { items.map { $0.0 + "=" + $0.1 }.joined(separator: " ") }

func numberList(_ values: [Int]) -> String { values.isEmpty ? "-" : values.map(String.init).joined(separator: ",") }

func frequency(_ values: [Int]) -> String {
    var counts: [Int: Int] = [:]
    for value in values { counts[value, default: 0] += 1 }
    return counts.isEmpty ? "-" : counts.keys.sorted().map { "\($0):\(counts[$0]!)" }.joined(separator: ",")
}

func queensBoard(_ columns: [Int]) -> [String] {
    columns.map { String(repeating: ".", count: $0 - 1) + "Q" + String(repeating: ".", count: columns.count - $0) }
}

func saveLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}

func saveParagraphs(_ filename: String, _ paragraphs: [[String]]) throws {
    let content = paragraphs.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (content.isEmpty ? "" : content + "\n").write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}
