struct ScoreBlock { let kind: Int; let notation: String; let kan: Bool; let concealed: Bool }
struct Fu { let items: [(String, Int)]; let total: Int; let rounded: Int }
struct Payment { let first: Int; let second: Int; let total: Int }
enum Scoring {
    static func blockFu(_ block: ScoreBlock) -> Int { (block.kan ? (block.concealed ? 16 : 8) : (block.concealed ? 4 : 2)) * (Tiles.yaochuu(block.kind) ? 2 : 1) }
    static func fu(chiitoitsu: Bool, closed: Bool, ron: Bool, pinfu: Bool, pair: Int, seat: Int, round: Int, blocks: [ScoreBlock], wait: String) -> Fu {
        if chiitoitsu { return Fu(items: [("chiitoitsu", 25)], total: 25, rounded: 25) }
        var items = [("base", 20)]
        if closed && ron { items.append(("closed_ron", 10)) }
        if !ron && !pinfu { items.append(("tsumo", 2)) }
        let pairFu = (pair >= 31 ? 2 : 0) + (pair == 27 + seat ? 2 : 0) + (pair == 27 + round ? 2 : 0)
        if pairFu > 0 { items.append(("pair " + Tiles.block([pair, pair]), pairFu)) }
        for block in blocks {
            let name = block.kan ? (block.concealed ? "closed_kan" : "open_kan") : (block.concealed ? "closed_triplet" : "open_triplet")
            items.append((name + " " + block.notation, blockFu(block)))
        }
        if ["kanchan", "penchan", "tanki"].contains(wait) { items.append(("wait " + wait, 2)) }
        var total = items.reduce(0) { $0 + $1.1 }
        if !closed && total == 20 { items.append(("open_pinfu", 10)); total += 10 }
        return Fu(items: items, total: total, rounded: (total + 9) / 10 * 10)
    }
    static func base(han: Int, fu: Int, kazoe: Bool, kiriage: Bool) -> (Int, Int) {
        if han >= 13 && kazoe { return (5, 8000) }
        if han >= 11 { return (4, 6000) }
        if han >= 8 { return (3, 4000) }
        if han >= 6 { return (2, 3000) }
        let base = fu * (1 << (han + 2))
        return han == 5 || base >= 2000 || (kiriage && base == 1920) ? (1, 2000) : (0, base)
    }
    static func hundred(_ value: Int) -> Int { (value + 99) / 100 * 100 }
    static func payments(base: Int, dealer: Bool, ron: Bool) -> Payment {
        if ron { let p = hundred((dealer ? 6 : 4) * base); return Payment(first: p, second: 0, total: p) }
        let first = hundred(2 * base)
        if dealer { return Payment(first: first, second: 0, total: 3 * first) }
        let second = hundred(base)
        return Payment(first: first, second: second, total: first + 2 * second)
    }
}
