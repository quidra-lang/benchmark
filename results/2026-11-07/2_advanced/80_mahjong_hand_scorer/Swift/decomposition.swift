struct TileSet: Hashable, Comparable {
    let start: Int
    let sequence: Bool
    var kinds: [Int] { sequence ? [start, start + 1, start + 2] : Array(repeating: start, count: 3) }
    static func < (a: Self, b: Self) -> Bool { a.start == b.start ? !a.sequence && b.sequence : a.start < b.start }
}
struct SplitHand: Hashable { let pair: Int; let sets: [TileSet] }
enum Decomposition {
    static func standard(_ counts: [Int], melds: Int) -> [SplitHand] {
        var result: Set<SplitHand> = []
        func visit(_ counts: [Int], _ sets: [TileSet], _ pair: Int) {
            guard let first = counts.firstIndex(where: { $0 > 0 }) else {
                if sets.count == 4 - melds { result.insert(SplitHand(pair: pair, sets: sets.sorted())) }
                return
            }
            if sets.count == 4 - melds { return }
            if counts[first] >= 3 {
                var trial = counts; trial[first] -= 3
                visit(trial, sets + [TileSet(start: first, sequence: false)], pair)
            }
            if first < 27 && first % 9 <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0 {
                var trial = counts; for k in first...first + 2 { trial[k] -= 1 }
                visit(trial, sets + [TileSet(start: first, sequence: true)], pair)
            }
        }
        for pair in 0..<34 where counts[pair] >= 2 { var trial = counts; trial[pair] -= 2; visit(trial, [], pair) }
        return result.sorted { $0.pair == $1.pair ? $0.sets.lexicographicallyPrecedes($1.sets) : $0.pair < $1.pair }
    }
    static func chiitoitsu(_ counts: [Int], melds: Int) -> Bool { melds == 0 && counts.filter { $0 == 2 }.count == 7 && counts.reduce(0, +) == 14 }
    static func kokushi(_ counts: [Int], melds: Int) -> Bool { melds == 0 && counts.reduce(0, +) == 14 && (0..<34).allSatisfy { Tiles.yaochuu($0) ? counts[$0] > 0 : counts[$0] == 0 } }
    static func winning(_ counts: [Int], melds: Int) -> Bool { chiitoitsu(counts, melds: melds) || kokushi(counts, melds: melds) || !standard(counts, melds: melds).isEmpty }
    static func waiting(_ hand: [Int], meldCounts: [Int], melds: Int) -> [Int] {
        (0..<34).filter { kind in
            if hand[kind] + meldCounts[kind] > 3 { return false }
            var trial = hand; trial[kind] += 1
            return winning(trial, melds: melds)
        }
    }
    static func shape(_ set: TileSet?, winning: Int) -> String {
        guard let set else { return "tanki" }
        if !set.sequence { return "shanpon" }
        if winning == set.start + 1 { return "kanchan" }
        if (set.start % 9 == 0 && winning == set.start + 2) || (set.start % 9 == 6 && winning == set.start) { return "penchan" }
        return "ryanmen"
    }
}
