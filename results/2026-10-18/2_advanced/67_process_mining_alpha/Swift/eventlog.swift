import Foundation

let monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
struct RawRow { let line: Int; let caseID: String; let activity: String; let timestamp: String; let resource: String }
struct RawInputs { let rows: [RawRow]; let parameters: [String: String] }
struct Event { let line: Int; let caseID: String; let activity: String; let timestamp: String; let resource: String; let time: Int }
struct CaseRecord {
    let identifier: String
    let events: [Event]
    let trace: [String]
    let duration: Int
    init(_ identifier: String, _ events: [Event]) { let sorted = events.sorted { $0.time == $1.time ? $0.line < $1.line : $0.time < $1.time }; self.identifier = identifier; self.events = sorted; trace = sorted.map { $0.activity }; duration = sorted.last!.time - sorted.first!.time }
}
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func readInputs() throws -> RawInputs { let lines = try inputLines("eventlog.csv"), rows = lines.dropFirst().enumerated().map { index, line -> RawRow in let fields = line.components(separatedBy: ","); return RawRow(line: index + 2, caseID: fields[0], activity: fields[1], timestamp: fields[2], resource: fields[3]) }; var parameters: [String: String] = [:]; for line in try inputLines("params.txt") { let fields = line.split(separator: " ").map(String.init); parameters[fields[0]] = fields[1] }; return RawInputs(rows: rows, parameters: parameters) }
func timestampMinutes(_ text: String) -> Int? { let bytes = Array(text.utf8); func number(_ index: Int) -> Int { Int(bytes[index] - 48) * 10 + Int(bytes[index + 1] - 48) }; let month = number(5), day = number(8), hour = number(11), minute = number(14); if month < 1 || month > 12 { return nil }; if day < 1 || day > monthDays[month - 1] || hour > 23 || minute > 59 { return nil }; return ((monthDays.prefix(month - 1).reduce(0, +) + day - 1) * 24 + hour) * 60 + minute }
func groupCases(_ events: [Event]) -> [CaseRecord] { let grouped = Dictionary(grouping: events, by: { $0.caseID }); return grouped.keys.sorted().map { CaseRecord($0, grouped[$0]!) } }
func median(_ values: [Int]) -> Rational { let ordered = values.sorted(), middle = values.count / 2; return values.count % 2 == 1 ? Rational(ordered[middle]) : Rational(ordered[middle - 1] + ordered[middle], 2) }
