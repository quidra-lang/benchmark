func itemsBefore(_ first: [String], _ second: [String]) -> Bool { first.lexicographicallyPrecedes(second) }
func sizeBefore(_ first: [String], _ second: [String]) -> Bool { first.count == second.count ? itemsBefore(first, second) : first.count < second.count }
func smallerSubsets(_ items: [String]) -> [[String]] { items.indices.map { omitted in items.enumerated().filter { $0.offset != omitted }.map(\.element) } }
struct CandidateLevel {
    let joined: Int
    let excluded: Int
    let pruned: Int
    let items: [[String]]
}
func generateCandidates(_ previous: [[String]], _ size: Int, _ taxonomy: [String: String]?) -> CandidateLevel {
    let ordered = previous.sorted(by: itemsBefore)
    let known = Set(previous)
    var joined: [[String]] = []
    for first in ordered.indices {
        for second in (first + 1)..<ordered.count {
            if ordered[first].dropLast() != ordered[second].dropLast() { break }
            joined.append(ordered[first] + [ordered[second].last!])
        }
    }
    let remaining: [[String]]
    if size == 2, let taxonomy { remaining = joined.filter { taxonomy[$0[0]] != $0[1] && taxonomy[$0[1]] != $0[0] } }
    else { remaining = joined }
    let survivors = remaining.filter { candidate in smallerSubsets(candidate).allSatisfy { known.contains($0) } }
    return CandidateLevel(joined: joined.count, excluded: joined.count - remaining.count, pruned: remaining.count - survivors.count, items: survivors)
}
func countSupports(_ index: BasketIndex, _ candidates: [[String]]) -> [[String]: Int] { Dictionary(uniqueKeysWithValues: candidates.map { ($0, index.count($0)) }) }
