enum Shanten {
    struct Key: Hashable { let counts: [Int]; let sets: Int; let partials: Int; let pair: Bool }
    static func calculate(_ counts: [Int]) -> [Int] {
        var memo: [Key: Int] = [:]
        func standard(_ counts: [Int], _ sets: Int, _ partials: Int, _ pair: Bool) -> Int {
            let key = Key(counts: counts, sets: sets, partials: partials, pair: pair)
            if let value = memo[key] { return value }
            var best = 8 - 2 * sets - min(partials, 4 - sets) - (pair ? 1 : 0)
            guard let first = counts.firstIndex(where: { $0 > 0 }) else { return best }
            var trial = counts; trial[first] -= 1
            best = min(best, standard(trial, sets, partials, pair))
            if sets < 4 && counts[first] >= 3 { trial = counts; trial[first] -= 3; best = min(best, standard(trial, sets + 1, partials, pair)) }
            if sets < 4 && first < 27 && first % 9 <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0 {
                trial = counts; for k in first...first + 2 { trial[k] -= 1 }; best = min(best, standard(trial, sets + 1, partials, pair))
            }
            if counts[first] >= 2 {
                trial = counts; trial[first] -= 2
                if !pair { best = min(best, standard(trial, sets, partials, true)) }
                if partials < 4 { best = min(best, standard(trial, sets, partials + 1, pair)) }
            }
            if partials < 4 && first < 27 {
                for gap in 1...2 where first % 9 + gap < 9 && counts[first + gap] > 0 { trial = counts; trial[first] -= 1; trial[first + gap] -= 1; best = min(best, standard(trial, sets, partials + 1, pair)) }
            }
            memo[key] = best; return best
        }
        let distinct = counts.filter { $0 > 0 }.count, pairs = counts.filter { $0 >= 2 }.count
        let outer = (0..<34).filter { Tiles.yaochuu($0) && counts[$0] > 0 }.count
        let pair = (0..<34).contains { Tiles.yaochuu($0) && counts[$0] >= 2 }
        return [standard(counts, 0, 0, false), 6 - pairs + max(0, 7 - distinct), 13 - outer - (pair ? 1 : 0)]
    }
}
