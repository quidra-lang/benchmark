import Foundation
struct Row { let label: String; let fields: [String: String] }
func rows(_ name: String) -> [Row] {
    try! String(contentsOfFile: "input/\(name).txt", encoding: .ascii).split(separator: "\n").map { line in
        let words = line.split(separator: " ").map(String.init)
        return Row(label: words[0], fields: Dictionary(uniqueKeysWithValues: words.dropFirst().map { word in let parts = word.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false); return (String(parts[0]), String(parts[1])) }))
    }
}
struct Rule { let name: String; let open: Bool; let red: Bool; let double: Bool; let kazoe: Bool; let kiriage: Bool; let honba: Int }
func wind(_ text: String) -> Int { Array("ESWN").firstIndex(of: text.first!)! }
struct Meld { let kind: Character; let tiles: [Tile] }
struct Situation {
    let hand: [Tile]; let melds: [Meld]; let win: Tile; let ron: Bool; let seat: Int; let from: Int?; let round: Int; let flags: Set<String>; let dora: [Tile]; let ura: [Tile]; let discards: [Tile]; let honba: Int; let sticks: Int
    var closed: Bool { melds.allSatisfy { $0.kind == "A" } }
    var all: [Tile] { hand + [win] + melds.flatMap(\.tiles) }
    var concealed: [Int] { var counts = Tiles.counts(hand); counts[win.kind] += 1; return counts }
}
enum InputError: Error { case message(String) }
func parseTiles(_ text: String, empty: Bool = false) throws -> [Tile] { guard let tiles = Tiles.parse(text, empty: empty) else { throw InputError.message("bad tile notation") }; return tiles }
func copyError(_ tiles: [Tile], rule: Rule) -> String? {
    if !rule.red && tiles.contains(where: \.red) { return "red five not allowed" }
    let counts = Tiles.counts(tiles)
    if let kind = counts.firstIndex(where: { $0 >= 5 }) { return "too many copies of " + Tiles.name(kind) }
    for suit in 0..<3 where tiles.filter({ $0.red && $0.kind / 9 == suit }).count >= 2 { return "too many copies of 0\(Tiles.suits[suit])" }
    return nil
}
func check(_ row: Row, rule: Rule) throws -> Situation {
    let f = row.fields
    let hand = try parseTiles(f["hand"]!), win = try parseTiles(f["win"]!), dora = try parseTiles(f["dora"]!), ura = try parseTiles(f["ura"]!, empty: true), discards = try parseTiles(f["discards"]!, empty: true)
    var melds: [Meld] = []
    if f["melds"]! != "-" { for text in f["melds"]!.split(separator: ",") { melds.append(Meld(kind: text.first!, tiles: try parseTiles(String(text.dropFirst())))) } }
    guard win.count == 1 else { throw InputError.message("bad tile notation") }
    let badMeld = melds.contains { meld in
        let kinds = meld.tiles.map(\.kind).sorted()
        switch meld.kind {
        case "C": return kinds.count != 3 || kinds[0] >= 27 || kinds[0] % 9 > 6 || kinds != [kinds[0], kinds[0] + 1, kinds[0] + 2]
        case "P": return kinds.count != 3 || kinds.contains { $0 != kinds[0] }
        case "K", "A": return kinds.count != 4 || kinds.contains { $0 != kinds[0] }
        default: return true
        }
    }
    guard melds.count < 5 && !badMeld else { throw InputError.message("bad meld") }
    guard hand.count == 13 - 3 * melds.count else { throw InputError.message("wrong tile count") }
    if let error = copyError(hand + win + melds.flatMap(\.tiles) + dora + ura + discards, rule: rule) { throw InputError.message(error) }
    let ron = f["by"]! == "ron", seat = wind(f["seat"]!), from = f["from"]! == "-" ? nil : wind(f["from"]!)
    if (!ron && from != nil) || (ron && (from == nil || from == seat)) { throw InputError.message("invalid discarder") }
    let flags: Set<String> = f["flags"]! == "-" ? [] : Set(f["flags"]!.split(separator: ",").map(String.init))
    let closed = melds.allSatisfy { $0.kind == "A" }, riichi = flags.contains("riichi") || flags.contains("double_riichi"), kans = melds.filter { $0.kind == "K" || $0.kind == "A" }.count
    for flag in Yaku.flags where flags.contains(flag) {
        let valid: Bool
        switch flag {
        case "riichi": valid = closed
        case "double_riichi": valid = closed && !flags.contains("riichi")
        case "ippatsu": valid = riichi && !flags.contains("rinshan")
        case "haitei": valid = !ron && !flags.contains("rinshan")
        case "houtei": valid = ron && !flags.contains("chankan")
        case "rinshan": valid = !ron && kans > 0
        case "chankan": valid = ron
        case "tenhou": valid = seat == 0 && !ron && melds.isEmpty && flags.count == 1
        default: valid = seat != 0 && !ron && melds.isEmpty && flags.count == 1
        }
        if !valid { throw InputError.message("invalid flag " + flag) }
    }
    guard dora.count == 1 + kans else { throw InputError.message("invalid dora indicators") }
    if (riichi && ura.count != dora.count) || (!riichi && !ura.isEmpty) { throw InputError.message("invalid ura indicators") }
    let sticks = Int(f["sticks"]!)!
    if riichi && sticks == 0 { throw InputError.message("invalid sticks") }
    let situation = Situation(hand: hand, melds: melds, win: win[0], ron: ron, seat: seat, from: from, round: wind(f["round"]!), flags: flags, dora: dora, ura: ura, discards: discards, honba: Int(f["honba"]!)!, sticks: sticks)
    guard Decomposition.winning(situation.concealed, melds: melds.count) else { throw InputError.message("not a winning hand") }
    return situation
}
struct Form { let kind: Int; let pair: Int; let sets: [TileSet]; let winning: Int; let notation: String; let wait: String }
func forms(_ s: Situation) -> [Form] {
    let counts = s.concealed
    var result: [Form] = []
    for split in Decomposition.standard(counts, melds: s.melds.count) {
        var winning = split.pair == s.win.kind ? [0] : [], seen: Set<TileSet> = []
        for (i, set) in split.sets.enumerated() where set.kinds.contains(s.win.kind) && seen.insert(set).inserted { winning.append(i + 1) }
        for winning in winning {
            var parts = ["standard", Tiles.block([split.pair, split.pair]) + (winning == 0 ? "*" : "")]
            for (i, set) in split.sets.enumerated() { parts.append(Tiles.block(set.kinds) + (winning == i + 1 ? "*" : "")) }
            for meld in s.melds { parts.append(String(meld.kind) + Tiles.block(meld.tiles.map(\.kind))) }
            result.append(Form(kind: 0, pair: split.pair, sets: split.sets, winning: winning, notation: parts.joined(separator: " "), wait: Decomposition.shape(winning == 0 ? nil : split.sets[winning - 1], winning: s.win.kind)))
        }
    }
    if Decomposition.chiitoitsu(counts, melds: s.melds.count) {
        let parts = (0..<34).filter { counts[$0] == 2 }.map { Tiles.block([$0, $0]) + ($0 == s.win.kind ? "*" : "") }
        result.append(Form(kind: 1, pair: 0, sets: [], winning: 0, notation: (["chiitoitsu"] + parts).joined(separator: " "), wait: "tanki"))
    }
    if Decomposition.kokushi(counts, melds: s.melds.count) {
        let parts = (0..<34).filter { counts[$0] > 0 }.map { Tiles.block(Array(repeating: $0, count: counts[$0])) + ($0 == s.win.kind ? "*" : "") }, hand = Tiles.counts(s.hand)
        let thirteen = (0..<34).allSatisfy { hand[$0] == (Tiles.yaochuu($0) ? 1 : 0) }
        result.append(Form(kind: 2, pair: 0, sets: [], winning: 0, notation: (["kokushi"] + parts).joined(separator: " "), wait: thirteen ? "thirteen" : "single"))
    }
    return result.sorted { $0.notation < $1.notation }
}
struct Candidate { let form: Form; let yakus: [(Int, Int)]; let yakuman: [(Int, Int)]; let fu: Fu; let dora: [Int]; let han: Int; let multiplier: Int; let category: Int; let base: Int }
func evaluate(_ form: Form, _ s: Situation, _ rule: Rule) -> Candidate {
    let all = s.all, counts = Tiles.counts(all), handCounts = Tiles.counts(s.hand), closed = s.closed
    var holds = Array(repeating: false, count: 30), yakuman = Array(repeating: false, count: 15), triplets: [ScoreBlock] = [], sequences: Set<Int> = [], sequenceCounts: [Int: Int] = [:]
    let numberSuits = Set(all.filter { $0.kind < 27 }.map { $0.kind / 9 }), honors = all.contains { $0.kind >= 27 }
    let pure = numberSuits.count == 1 && !honors
    for (i, flag) in [(0,"riichi"),(1,"double_riichi"),(2,"ippatsu"),(12,"haitei"),(13,"houtei"),(14,"rinshan"),(15,"chankan")] { holds[i] = s.flags.contains(flag) }
    holds[3] = closed && !s.ron
    holds[5] = all.allSatisfy { !Tiles.yaochuu($0.kind) } && (closed || rule.open)
    holds[25] = all.allSatisfy { Tiles.yaochuu($0.kind) }
    holds[26] = numberSuits.count == 1 && honors
    holds[29] = pure
    holds[16] = form.kind == 1
    yakuman[0] = s.flags.contains("tenhou"); yakuman[1] = s.flags.contains("chiihou")
    yakuman[9] = all.allSatisfy { $0.kind >= 27 }; yakuman[10] = all.allSatisfy { Tiles.terminal($0.kind) }; yakuman[11] = all.allSatisfy { Tiles.green($0.kind) }
    if form.kind == 2 { yakuman[form.wait == "thirteen" ? 3 : 2] = true }
    if s.melds.isEmpty && pure {
        let first = numberSuits.first! * 9
        if counts[first] >= 3 && counts[first + 8] >= 3 && (first + 1..<first + 8).allSatisfy({ counts[$0] >= 1 }) {
            let exact = (0..<9).allSatisfy { handCounts[first + $0] == ($0 == 0 || $0 == 8 ? 3 : 1) }
            yakuman[exact ? 13 : 12] = true
        }
    }
    if form.kind == 0 {
        for (i, set) in form.sets.enumerated() {
            if set.sequence { sequences.insert(set.start); sequenceCounts[set.start, default: 0] += 1 }
            else { triplets.append(ScoreBlock(kind: set.start, notation: Tiles.block(set.kinds), kan: false, concealed: !s.ron || form.winning != i + 1)) }
        }
        for meld in s.melds {
            let first = meld.tiles.map(\.kind).min()!
            if meld.kind == "C" { sequences.insert(first) }
            else { triplets.append(ScoreBlock(kind: first, notation: Tiles.block(meld.tiles.map(\.kind)), kan: meld.kind == "K" || meld.kind == "A", concealed: meld.kind == "A")) }
        }
        let pairYakuhai = form.pair >= 31 || form.pair == 27 + s.seat || form.pair == 27 + s.round
        holds[4] = closed && s.melds.isEmpty && form.sets.allSatisfy(\.sequence) && !pairYakuhai && form.wait == "ryanmen"
        holds[28] = closed && form.sets.count == 4 && form.sets.allSatisfy(\.sequence) && sequenceCounts.values.allSatisfy { $0 % 2 == 0 }
        holds[6] = closed && !holds[28] && sequenceCounts.values.contains { $0 >= 2 }
        func has(_ kind: Int) -> Bool { triplets.contains { $0.kind == kind } }
        for i in 0..<3 { holds[7 + i] = has(31 + i) }
        holds[10] = has(27 + s.seat); holds[11] = has(27 + s.round); holds[17] = triplets.count == 4
        let concealed = triplets.filter(\.concealed).count
        holds[18] = concealed == 3
        holds[19] = (0..<7).contains { start in (0..<3).allSatisfy { sequences.contains(9 * $0 + start) } }
        holds[20] = (0..<9).contains { number in (0..<3).allSatisfy { has(9 * $0 + number) } }
        holds[21] = (0..<3).contains { suit in [0,3,6].allSatisfy { sequences.contains(9 * suit + $0) } }
        let outer = !sequences.isEmpty && Tiles.yaochuu(form.pair) && triplets.allSatisfy { Tiles.yaochuu($0.kind) } && sequences.allSatisfy { $0 % 9 == 0 || $0 % 9 == 6 }
        holds[honors ? 22 : 27] = outer
        let kans = triplets.filter(\.kan).count, dragons = triplets.filter { $0.kind >= 31 }.count, winds = triplets.filter { (27..<31).contains($0.kind) }.count
        holds[23] = kans == 3; holds[24] = dragons == 2 && form.pair >= 31
        if concealed == 4 { yakuman[form.wait == "tanki" ? 5 : 4] = true }
        yakuman[6] = dragons == 3; yakuman[7] = winds == 3 && (27..<31).contains(form.pair); yakuman[8] = winds == 4; yakuman[14] = kans == 4
    }
    let yakumans = Yaku.multipliers(yakuman, double: rule.double), multiplier = yakumans.reduce(0) { $0 + $1.1 }
    if !yakumans.isEmpty { return Candidate(form: form, yakus: [], yakuman: yakumans, fu: Fu(items: [], total: 0, rounded: 0), dora: [0,0,0], han: 0, multiplier: multiplier, category: 6, base: 8000 * multiplier) }
    let yakus = Yaku.ordinary(holds, closed: closed)
    func count(_ indicators: [Tile]) -> Int { indicators.reduce(0) { $0 + counts[Tiles.next($1.kind)] } }
    let dora = [count(s.dora), all.filter(\.red).count, count(s.ura)], han = yakus.reduce(0) { $0 + $1.1 } + dora.reduce(0, +)
    let fu = Scoring.fu(chiitoitsu: form.kind == 1, closed: closed, ron: s.ron, pinfu: holds[4], pair: form.pair, seat: s.seat, round: s.round, blocks: triplets, wait: form.wait)
    let (category, base) = yakus.isEmpty ? (0, 0) : Scoring.base(han: han, fu: fu.rounded, kazoe: rule.kazoe, kiriage: rule.kiriage)
    return Candidate(form: form, yakus: yakus, yakuman: [], fu: fu, dora: dora, han: han, multiplier: 0, category: category, base: base)
}
func candidates(_ situation: Situation, _ rule: Rule) -> [Candidate] { forms(situation).map { evaluate($0, situation, rule) } }
func best(_ candidates: [Candidate]) -> Int? {
    var chosen: Int?
    for i in candidates.indices where candidates[i].base > 0 {
        if let j = chosen {
            let a = candidates[i], b = candidates[j]
            let ka = [a.base, a.yakuman.isEmpty ? 0 : 1, a.yakuman.isEmpty ? a.han : 0, a.yakuman.isEmpty ? a.fu.rounded : 0]
            let kb = [b.base, b.yakuman.isEmpty ? 0 : 1, b.yakuman.isEmpty ? b.han : 0, b.yakuman.isEmpty ? b.fu.rounded : 0]
            if kb.lexicographicallyPrecedes(ka) { chosen = i }
        } else { chosen = i }
    }
    return chosen
}
func names(_ candidate: Candidate, _ separator: String) -> String { (candidate.yakuman.isEmpty ? candidate.yakus.map { Yaku.names[$0.0] } : candidate.yakuman.map { Yaku.yakuman[$0.0] }).joined(separator: separator) }
func waiting(_ s: Situation) -> [Int] { Decomposition.waiting(Tiles.counts(s.hand), meldCounts: Tiles.counts(s.melds.flatMap(\.tiles)), melds: s.melds.count) }
func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : String(value) }
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func run() {
    let rules = rows("rules").map { row in Rule(name: row.label, open: row.fields["open_tanyao"]! == "yes", red: row.fields["red_fives"]! == "yes", double: row.fields["double_yakuman"]! == "yes", kazoe: row.fields["kazoe_yakuman"]! == "yes", kiriage: row.fields["kiriage"]! == "yes", honba: Int(row.fields["honba"]!)!) }
    let situations = rows("hands"), waitHands = rows("waits")
    var scores: [String] = [], summary = ["hand,han,fu,points,yaku"], statuses = Array(repeating: 0, count: 4), winTypes = statuses, waitCount = Array(repeating: 0, count: 7), hanCount: [Int: Int] = [:], fuCount: [Int: Int] = [:], limits = waitCount, yakuCount = Array(repeating: 0, count: 45), pointsTotal = 0, maximum = (0, "-"), ruleCounts = Array(repeating: [0,0,0], count: rules.count)
    for row in situations {
        let ruleIndex = rules.firstIndex { $0.name == row.fields["rules"]! }!, rule = rules[ruleIndex]
        ruleCounts[ruleIndex][0] += 1; scores.append("HAND " + row.label)
        let s: Situation
        do { s = try check(row, rule: rule) }
        catch InputError.message(let message) { statuses[3] += 1; scores.append("ERROR " + message); summary.append("\(row.label),-,-,0,ERROR"); continue }
        catch { fatalError() }
        let waits = waiting(s), options = candidates(s, rule)
        scores.append("WAITS " + waits.map(Tiles.name).joined(separator: " "))
        for c in options {
            let evaluation: String
            if !c.yakuman.isEmpty { evaluation = "yakuman \(c.multiplier) base \(c.base) yaku \(names(c, ","))" }
            else if c.base == 0 { evaluation = "no_yaku" }
            else { evaluation = "han \(c.han) fu \(c.fu.rounded) base \(c.base) yaku \(names(c, ","))" }
            scores.append("CANDIDATE \(c.form.notation) = \(c.form.wait) \(evaluation)")
        }
        if s.ron && s.discards.contains(where: { waits.contains($0.kind) }) { statuses[1] += 1; scores.append("RESULT furiten"); summary.append("\(row.label),-,-,0,FURITEN"); continue }
        guard let chosen = best(options) else { statuses[2] += 1; scores.append("RESULT no_yaku"); summary.append("\(row.label),-,-,0,NO_YAKU"); continue }
        let c = options[chosen]
        statuses[0] += 1; winTypes[2 * (s.seat != 0 ? 1 : 0) + (s.ron ? 0 : 1)] += 1
        waitCount[Yaku.waits.firstIndex(of: c.form.wait)!] += 1; limits[c.category] += 1
        scores.append("FORM " + c.form.notation); scores.append("WAIT " + c.form.wait)
        if !c.yakuman.isEmpty {
            for (i, multiplier) in c.yakuman { yakuCount[30 + i] += 1; scores.append("YAKUMAN \(Yaku.yakuman[i]) \(multiplier)") }
            scores.append("SCORE yakuman \(c.multiplier) base \(c.base)")
        } else {
            hanCount[c.han, default: 0] += 1; fuCount[c.fu.rounded, default: 0] += 1
            for (i, han) in c.yakus { yakuCount[i] += 1; scores.append("YAKU \(Yaku.names[i]) \(han)") }
            scores.append("DORA dora \(c.dora[0]) aka \(c.dora[1]) ura \(c.dora[2])")
            for (item, value) in c.fu.items { scores.append("FU \(item) \(value)") }
            scores.append("FU total \(c.fu.total) \(c.fu.rounded)"); scores.append("SCORE han \(c.han) fu \(c.fu.rounded) limit \(Yaku.categories[c.category]) base \(c.base)")
        }
        let payment = Scoring.payments(base: c.base, dealer: s.seat == 0, ron: s.ron)
        if s.ron { scores.append("PAY ron \(payment.first)") }
        else if s.seat == 0 { scores.append("PAY tsumo all \(payment.first)") }
        else { scores.append("PAY tsumo dealer \(payment.first) nondealer \(payment.second)") }
        let honba = s.honba * rule.honba, sticks = 1000 * s.sticks, gain = payment.total + honba + sticks
        var delta = Array(repeating: 0, count: 4); delta[s.seat] = gain
        if s.ron { delta[s.from!] = -(payment.first + honba) }
        else { for payer in 0..<4 where payer != s.seat { delta[payer] = -(s.seat == 0 || payer == 0 ? payment.first : payment.second) - honba / 3 } }
        scores.append("BONUS honba \(honba) sticks \(sticks)"); scores.append("TOTAL points \(payment.total) gain \(gain)")
        scores.append("DELTA E \(signed(delta[0])) S \(signed(delta[1])) W \(signed(delta[2])) N \(signed(delta[3]))")
        pointsTotal += payment.total
        if payment.total > maximum.0 { maximum = (payment.total, row.label) }
        ruleCounts[ruleIndex][1] += 1; ruleCounts[ruleIndex][2] += payment.total
        summary.append(c.yakuman.isEmpty ? "\(row.label),\(c.han),\(c.fu.rounded),\(payment.total),\(names(c, ";"))" : "\(row.label),Y\(c.multiplier),-,\(payment.total),\(names(c, ";"))")
    }
    scores.append("STATS hands \(situations.count) wins \(statuses[0]) furiten \(statuses[1]) no_yaku \(statuses[2]) errors \(statuses[3])")
    scores.append("WINS dealer_ron \(winTypes[0]) dealer_tsumo \(winTypes[1]) nondealer_ron \(winTypes[2]) nondealer_tsumo \(winTypes[3])")
    scores.append("WAIT_COUNT " + zip(Yaku.waits, waitCount).map { "\($0.0) \($0.1)" }.joined(separator: " "))
    for han in hanCount.keys.sorted() { scores.append("HAN_COUNT \(han) \(hanCount[han]!)") }
    for fu in fuCount.keys.sorted() { scores.append("FU_COUNT \(fu) \(fuCount[fu]!)") }
    for i in 0..<7 { scores.append("LIMIT \(Yaku.categories[i]) \(limits[i])") }
    for i in 0..<45 where yakuCount[i] > 0 { scores.append("YAKU_COUNT \(i < 30 ? Yaku.names[i] : Yaku.yakuman[i - 30]) \(yakuCount[i])") }
    scores.append("POINTS total \(pointsTotal) max \(maximum.0) hand \(maximum.1)")
    for i in rules.indices { scores.append("RULE \(rules[i].name) hands \(ruleCounts[i][0]) wins \(ruleCounts[i][1]) points \(ruleCounts[i][2])") }
    var waitLines: [String] = [], waitErrors = 0, tenpai = 0, furitenCount = 0, shantenCounts = Array(repeating: 0, count: 7)
    for row in waitHands {
        waitLines.append("HAND " + row.label)
        let f = row.fields, rule = rules.first { $0.name == f["rules"]! }!
        let hand: [Tile], dora: [Tile], discards: [Tile], visible: [Tile]
        do {
            hand = try parseTiles(f["hand"]!); dora = try parseTiles(f["dora"]!); discards = try parseTiles(f["discards"]!, empty: true); visible = try parseTiles(f["visible"]!, empty: true)
            if hand.count != 13 { throw InputError.message("wrong tile count") }
            if let error = copyError(hand + dora + discards + visible, rule: rule) { throw InputError.message(error) }
        } catch InputError.message(let message) { waitErrors += 1; waitLines.append("ERROR " + message); continue }
        catch { fatalError() }
        let counts = Tiles.counts(hand), used = Tiles.counts(hand + dora + discards + visible), shanten = Shanten.calculate(counts), minimum = shanten.min()!
        shantenCounts[minimum] += 1
        waitLines.append("SHANTEN standard \(shanten[0]) chiitoitsu \(shanten[1]) kokushi \(shanten[2])")
        var acceptance: [(Int, Int)] = []
        for kind in 0..<34 where counts[kind] <= 3 { var trial = counts; trial[kind] += 1; if Shanten.calculate(trial).min()! < minimum { acceptance.append((kind, 4 - used[kind])) } }
        let remaining = acceptance.reduce(0) { $0 + $1.1 }
        if minimum > 0 {
            let tiles = acceptance.map { "\(Tiles.name($0.0)):\($0.1)" }.joined(separator: " ")
            waitLines.append("ACCEPT kinds \(acceptance.count) tiles \(remaining)" + (tiles.isEmpty ? "" : " " + tiles)); continue
        }
        tenpai += 1
        let furiten = discards.contains { tile in acceptance.contains { $0.0 == tile.kind } }
        if furiten { furitenCount += 1 }
        waitLines.append("TENPAI kinds \(acceptance.count) tiles \(remaining) furiten \(furiten ? "yes" : "no")")
        var bestWaits: [(Int, Int)?] = [nil, nil]
        for (kind, left) in acceptance {
            var values: [String] = []
            for method in 0..<2 {
                if method == 0 && furiten { values.append("furiten"); continue }
                let flags: Set<String> = f["riichi"]! == "yes" ? ["riichi"] : []
                let situation = Situation(hand: hand, melds: [], win: Tile(kind: kind, red: false), ron: method == 0, seat: wind(f["seat"]!), from: nil, round: wind(f["round"]!), flags: flags, dora: dora, ura: [], discards: [], honba: 0, sticks: 0)
                let options = candidates(situation, rule)
                if let chosen = best(options) {
                    let points = Scoring.payments(base: options[chosen].base, dealer: situation.seat == 0, ron: situation.ron).total
                    values.append(String(points))
                    if bestWaits[method] == nil || points > bestWaits[method]!.1 { bestWaits[method] = (kind, points) }
                } else { values.append("no_yaku") }
            }
            waitLines.append("WAIT \(Tiles.name(kind)) left \(left) ron \(values[0]) tsumo \(values[1])")
        }
        func bestText(_ value: (Int, Int)?) -> String { value.map { "\(Tiles.name($0.0)) \($0.1)" } ?? "none" }
        waitLines.append("BEST ron \(bestText(bestWaits[0])) tsumo \(bestText(bestWaits[1]))")
    }
    waitLines.append("STATS hands \(waitHands.count) errors \(waitErrors) tenpai \(tenpai) furiten \(furitenCount)")
    for k in 0..<7 { waitLines.append("SHANTEN_COUNT \(k) \(shantenCounts[k])") }
    write("scores.txt", scores); write("waits.txt", waitLines); write("summary.csv", summary)
}
run()
