import Foundation

func padded(_ value: Int, _ width: Int) -> String { let text = String(value); return String(repeating: "0", count: max(0, width - text.count)) + text }
func localText(_ time: Int) -> String {
    let (year, month, day, hour, minute, second) = splitTime(time)
    return "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))T\(padded(hour, 2)):\(padded(minute, 2)):\(padded(second, 2))"
}
func utText(_ time: Int) -> String { localText(time) + "Z" }
func offsetText(_ value: Int) -> String {
    let absolute = abs(value)
    var text = (value < 0 ? "-" : "+") + padded(absolute / 3600, 2) + ":" + padded(absolute / 60 % 60, 2)
    if absolute % 60 != 0 { text += ":" + padded(absolute % 60, 2) }
    return text
}
func durationText(_ value: Int) -> String {
    let absolute = abs(value)
    return (value < 0 ? "-" : "") + String(absolute / 3600) + ":" + padded(absolute / 60 % 60, 2) + ":" + padded(absolute % 60, 2)
}
func clockText(_ value: Int) -> String { var text = String(value / 3600) + ":" + padded(value / 60 % 60, 2); if value % 60 != 0 { text += ":" + padded(value % 60, 2) }; return text }
func stateText(_ period: Period) -> String { "\(offsetText(period.offset)) \(period.dst ? "DST" : "STD") \(period.abbreviation)" }
func changeText(_ time: Int, _ before: Period, _ after: Period) -> String { "\(utText(time)) \(stateText(before)) -> \(stateText(after))" }
func writeLines(_ path: String, _ lines: [String]) throws { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8) }
func writeBlocks(_ path: String, _ blocks: [[String]]) throws {
    var lines: [String] = []
    for (index, block) in blocks.enumerated() { if index > 0 { lines.append("") }; lines += block }
    try writeLines(path, lines)
}
