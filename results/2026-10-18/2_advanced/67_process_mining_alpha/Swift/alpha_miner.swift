import Foundation

struct CandidatePair: Hashable { let first: Set<String>; let second: Set<String> }
func extendPair(_ pair: CandidatePair, _ activity: String, _ side: Int, _ relation: Relation) -> CandidatePair? {
    let group = side == 0 ? pair.first : pair.second
    if group.contains(activity) || relation(activity, activity) != "#" || group.contains(where: { relation(activity, $0) != "#" }) { return nil }
    if side == 0 { if pair.second.contains(where: { relation(activity, $0) != "->" }) { return nil }; return CandidatePair(first: pair.first.union([activity]), second: pair.second) }
    if pair.first.contains(where: { relation($0, activity) != "->" }) { return nil }
    return CandidatePair(first: pair.first, second: pair.second.union([activity]))
}
func pairBefore(_ first: CandidatePair, _ second: CandidatePair) -> Bool { let a = first.first.sorted(), b = second.first.sorted(); return a == b ? first.second.sorted().lexicographicallyPrecedes(second.second.sorted()) : a.lexicographicallyPrecedes(b) }
func triangleCounts(_ log: Log) -> Counts { var counts: Counts = [:]; for entry in log where entry.trace.count >= 3 { for index in 0..<(entry.trace.count - 2) { let first = entry.trace[index], second = entry.trace[index + 1]; if first == entry.trace[index + 2] && first != second { counts[NamePair(first, second), default: 0] += entry.weight } } }; return counts }
func plusRelation(_ counts: Counts, _ triangles: Counts, _ first: String, _ second: String) -> String { let forward = counts[NamePair(first, second), default: 0] > 0, backward = counts[NamePair(second, first), default: 0] > 0, loop = first != second && triangles[NamePair(first, second), default: 0] > 0 && triangles[NamePair(second, first), default: 0] > 0; if forward && (!backward || loop) { return "->" }; if backward && (!forward || loop) { return "<-" }; return forward && backward ? "||" : "#" }
