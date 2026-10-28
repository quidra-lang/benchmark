import Foundation

struct NamePair: Hashable, Comparable {
    let first: String
    let second: String
    init(_ first: String, _ second: String) { self.first = first; self.second = second }
    static func < (_ first: NamePair, _ second: NamePair) -> Bool { first.first == second.first ? first.second < second.second : first.first < second.first }
}
struct WeightedTrace { let trace: [String]; let weight: Int }
typealias Log = [WeightedTrace]
typealias Counts = [NamePair: Int]
typealias Relation = (String, String) -> String
func directlyFollows(_ log: Log) -> Counts { var counts: Counts = [:]; for entry in log { if entry.trace.count >= 2 { for index in 1..<entry.trace.count { counts[NamePair(entry.trace[index - 1], entry.trace[index]), default: 0] += entry.weight } } }; return counts }
func basicRelation(_ counts: Counts, _ first: String, _ second: String) -> String { let forward = counts[NamePair(first, second), default: 0] > 0, backward = counts[NamePair(second, first), default: 0] > 0; if forward && !backward { return "->" }; if backward && !forward { return "<-" }; return forward ? "||" : "#" }
func table(_ rows: [[String]], _ width: Int) -> [String] { func padded(_ text: String, _ length: Int) -> String { String(repeating: " ", count: max(0, length - text.count)) + text }; return ["    " + (1...rows.count).map { padded(String($0), width) }.joined()] + rows.enumerated().map { padded(String($0.offset + 1), 4) + $0.element.map { padded($0, width) }.joined() } }
func footprint(_ activities: [String], _ relation: Relation) -> [String] { activities.enumerated().map { "ACTIVITY \($0.offset + 1) \($0.element)" } + table(activities.map { first in activities.map { relation(first, $0) } }, 4) }
