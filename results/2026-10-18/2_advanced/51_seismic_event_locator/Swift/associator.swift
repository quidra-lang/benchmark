import Foundation

final class Candidate {
    let number: Int
    let first: Pick
    let picks: [Pick]
    var passes: [(picks: [Pick], run: LocationRun)] = []
    var event: Int?
    var rejected = false
    var dropped: [(pick: Pick, error: Double)] = []
    init(_ number: Int, _ first: Pick, _ picks: [Pick]) { self.number = number; self.first = first; self.picks = picks }
}

func associate(_ picks: [Pick], _ window: Int, _ minimum: Int) -> [Candidate] {
    var candidates: [Candidate] = []
    for (index, first) in picks.enumerated() {
        if first.assigned { continue }
        var chosen: [Pick] = [], seen = Set<Int>()
        for pick in picks.dropFirst(index) {
            if pick.sample > first.sample + window { break }
            if pick.assigned || seen.contains(pick.station.order) { continue }
            chosen.append(pick); seen.insert(pick.station.order)
        }
        if chosen.count < minimum { continue }
        for pick in chosen { pick.assigned = true }
        candidates.append(Candidate(candidates.count + 1, first, chosen))
    }
    return candidates
}
