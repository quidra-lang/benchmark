import Foundation

enum SafetyProperty: String, CaseIterable {
    case election = "ELECTION_SAFETY", completeness = "LEADER_COMPLETENESS", matching = "LOG_MATCHING", stateMachine = "STATE_MACHINE_SAFETY", kept = "COMMITTED_KEPT"
}
struct Committed { let term: Int; let time: Int }
struct Applied { let entry: Entry; let result: String? }
final class Checker {
    var violations: [SafetyProperty: Int] = [:]
    var leaders: [Int: Int] = [:]
    var committed: [Int: Committed] = [:]
    var applied: [Int: Applied] = [:]
    var elected = 0, logChecks = 0, pairChecks = 0, applies = 0, truncations = 0, removed = 0
    func leader(_ node: RaftNode) {
        elected += 1
        if let previous = leaders[node.term] { if previous != node.number { violations[.election, default: 0] += 1 } } else { leaders[node.term] = node.number }
        if committed.contains(where: { $0.key > node.lastIndex || node.termAt($0.key) != $0.value.term }) { violations[.completeness, default: 0] += 1 }
    }
    func commit(_ index: Int, _ term: Int, _ time: Int) { if committed[index] == nil { committed[index] = Committed(term: term, time: time) } }
    func apply(_ index: Int, _ entry: Entry, _ result: String?) { applies += 1; if let previous = applied[index] { if previous.entry != entry { violations[.stateMachine, default: 0] += 1 } } else { applied[index] = Applied(entry: entry, result: result) } }
    func truncate(_ first: Int, _ entries: [Entry]) {
        truncations += 1; removed += entries.count
        for (offset, entry) in entries.enumerated() { if committed[first + offset]?.term == entry.term { violations[.kept, default: 0] += 1 } }
    }
    func checkLogs(_ nodes: [RaftNode]) {
        logChecks += 1
        for first in nodes.indices { for second in nodes.indices.dropFirst(first + 1) {
            pairChecks += 1
            let a = nodes[first], b = nodes[second], limit = min(a.lastIndex, b.lastIndex)
            if (0..<limit).allSatisfy({ a.log[$0] == b.log[$0] }) { continue }
            var greatest = 0
            if limit > 0 { for index in stride(from: limit, through: 1, by: -1) { if a.termAt(index) == b.termAt(index) { greatest = index; break } } }
            if (0..<greatest).contains(where: { a.log[$0] != b.log[$0] }) { violations[.matching, default: 0] += 1 }
        } }
    }
    func lines(_ maximumTerm: Int) -> [String] {
        let details: [SafetyProperty: String] = [.election: "terms \(maximumTerm) leaders \(leaders.count) elected \(elected)", .completeness: "checks \(elected) committed \(committed.count)", .matching: "checks \(logChecks) pairs \(pairChecks)", .stateMachine: "applies \(applies) indices \(applied.count)", .kept: "truncations \(truncations) removed \(removed)"]
        return SafetyProperty.allCases.map { property in let count = violations[property, default: 0]; return "\(property.rawValue) \(count == 0 ? "OK" : "FAIL") violations \(count) \(details[property]!)" }
    }
}
