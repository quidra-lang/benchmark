import Foundation

enum CardNames {
    static let seats = Array("NESW")
    static let suits = Array("CDSH")
    static let ranks = Array("23456789TJQKA")
    static let strategies = ["BASIC", "LOW", "HIGH", "SMART", "MOON"]
}
struct CommandError: Error { let reason: String }
func fail(_ reason: String) throws -> Never {
    throw CommandError(reason: reason)
}
func cardText(_ c: Int) -> String {
    String(CardNames.ranks[c % 13]) + String(CardNames.suits[c / 13])
}
func cardsText(_ cards: Set<Int>) -> String {
    cards.isEmpty ? "-" : cards.sorted().map(cardText).joined(separator: " ")
}
func penalty(_ c: Int) -> Bool {
    c == 36 || c / 13 == 3
}
func ordered(_ cards: Set<Int>, high: Bool = false) -> [Int] {
    cards.sorted { a, b in a % 13 == b % 13 ? a / 13 < b / 13 : (high ? a % 13 > b % 13 : a % 13 < b % 13) }
}
func extreme(_ cards: Set<Int>, high: Bool = false) -> Int {
    ordered(cards, high: high)[0]
}
func direction(_ c: Character) -> String {
    c == "L" ? "LEFT" : c == "R" ? "RIGHT" : c == "A" ? "ACROSS" : "HOLD"
}
func pairs<T>(_ label: String, _ values: [T]) -> String {
    label + " " + values.enumerated().map { "\(CardNames.seats[$0.offset]) \($0.element)" }.joined(separator: " ")
}
func parseSeat(_ s: String) throws -> Int {
    guard s.count == 1, let c = s.first, let seat = CardNames.seats.firstIndex(of: c) else {
        try fail("bad seat " + s)
    }
    return seat
}
func parseCard(_ s: String) throws -> Int {
    let c = Array(s)
    guard c.count == 2, let rank = CardNames.ranks.firstIndex(of: c[0]),
          let suit = CardNames.suits.firstIndex(of: c[1])
    else {
        try fail("bad card " + s)
    }
    return suit * 13 + rank
}
func bounded(_ s: String, _ low: Int, _ high: Int) throws -> Int {
    guard let n = Int(s), n >= low && n <= high else {
        try fail("bad value " + s)
    }
    return n
}
func checkedSet(_ cards: [Int]) throws -> Set<Int> {
    var seen = Set<Int>()
    for c in cards {
        if !seen.insert(c).inserted {
            try fail("duplicate card " + cardText(c))
        }
    }
    return seen
}
struct Rules {
    var target = 100, limit = 100
    var moon = "ADD", pass = "LRAH"
    var jack = false, qsBreak = false, blood = false
    func validate(_ name: String, _ value: String) throws {
        let valid: Bool
        switch name {
        case "TARGET":
            _ = try bounded(value, 1, 1000)
            return
        case "LIMIT":
            _ = try bounded(value, 1, 100)
            return
        case "MOON":
            valid = ["ADD", "SUB", "AUTO"].contains(value)
        case "JACK", "QSBREAK", "BLOOD":
            valid = ["ON", "OFF"].contains(value)
        case "PASS":
            valid = (1...8).contains(value.count) && value.allSatisfy { "LRAH".contains($0) }
        default:
            try fail("unknown rule " + name)
        }
        if !valid {
            try fail("bad value " + value)
        }
    }
    mutating func set(_ name: String, _ value: String) {
        switch name {
        case "TARGET":
            target = Int(value)!
        case "LIMIT":
            limit = Int(value)!
        case "MOON":
            moon = value
        case "PASS":
            pass = value
        case "JACK":
            jack = value == "ON"
        case "QSBREAK":
            qsBreak = value == "ON"
        case "BLOOD":
            blood = value == "ON"
        default:
            break
        }
    }
    var text: String {
        "rules TARGET \(target) LIMIT \(limit) MOON \(moon) JACK \(jack ? "ON" : "OFF") QSBREAK \(qsBreak ? "ON" : "OFF") BLOOD \(blood ? "ON" : "OFF") PASS \(pass)"
    }
}
enum TableState { case none, between, passing, playing }
struct Play { let seat: Int, card: Int }
struct LiveHand {
    var hands = Array(repeating: Set<Int>(), count: 4)
    var taken = Array(repeating: Set<Int>(), count: 4)
    var tricks: [[Play]] = []
    var current: [Play] = []
    var counts = [0, 0, 0, 0]
    var leader = 0, broken = false
}
struct Snapshot { let hand: LiveHand, logLength: Int, seat: Int, card: Int }
struct History { let number: Int, pass: Character, points: [Int], shooter: Int?, begin: Int, end: Int }
struct RecordLine { let level: Int, text: String }
struct Game {
    let rules: Rules
    var bots: [Int]
    var random: Int64
    var state = TableState.between
    var number = 0
    var scores = [0, 0, 0, 0]
    var stats = Array(repeating: [0, 0, 0, 0], count: 4)
    var stacked: [Int: Set<Int>] = [:]
    var passes: [Int: Set<Int>] = [:]
    var pass: Character = "L"
    var hand = LiveHand()
    var undo: [Snapshot] = []
    var history: [History] = []
    var log: [RecordLine] = []
    var handBegin = 0
    init(_ rules: Rules, _ bots: [Int], _ seed: Int64) {
        self.rules = rules
        self.bots = bots
        random = seed
    }
    func point(_ c: Int) -> Int {
        c == 36 ? 13 : c / 13 == 3 ? 1 : c == 22 && rules.jack ? -10 : 0
    }
    func points(_ cards: Set<Int>) -> Int {
        cards.reduce(0) { $0 + point($1) }
    }
    mutating func write(_ level: Int, _ text: String) {
        log.append(RecordLine(level: level, text: text))
    }
    mutating func deal() {
        number += 1
        let cycle = Array(rules.pass)
        pass = cycle[(number - 1) % cycle.count]
        hand = LiveHand()
        var used = Set<Int>(), free: [Int] = []
        for s in 0..<4 {
            if let cards = stacked[s] {
                hand.hands[s] = cards
                used.formUnion(cards)
            } else {
                free.append(s)
            }
        }
        var deck = (0..<52).filter { !used.contains($0) }
        if deck.count >= 2 {
            for i in stride(from: deck.count - 1, through: 1, by: -1) {
                random = random * 48271 % 2147483647
                deck.swapAt(i, Int(random % Int64(i + 1)))
            }
        }
        for (i, c) in deck.enumerated() {
            hand.hands[free[i % free.count]].insert(c)
        }
        stacked = [:]
        passes = [:]
        undo = []
        handBegin = log.count
        write(1, "hand \(number) pass \(direction(pass))")
        for s in 0..<4 {
            write(2, "\(CardNames.seats[s]): \(cardsText(hand.hands[s]))")
        }
        if pass == "H" {
            beginPlay()
        } else {
            state = .passing
        }
    }
    mutating func beginPlay() {
        state = .playing
        hand.leader = (0..<4).first { hand.hands[$0].contains(0) }!
        write(2, "lead \(CardNames.seats[hand.leader])")
    }
    mutating func passCards(_ seat: Int, _ cards: Set<Int>) {
        hand.hands[seat].subtract(cards)
        passes[seat] = cards
        write(2, "\(CardNames.seats[seat]) passes \(cardsText(cards))")
        if passes.count == 4 {
            let offset = pass == "L" ? 1 : pass == "R" ? 3 : 2
            for s in 0..<4 {
                hand.hands[(s + offset) % 4].formUnion(passes[s]!)
            }
            beginPlay()
        }
    }
    var actor: Int {
        (hand.leader + hand.current.count) % 4
    }
    func legal() -> Set<Int> {
        let cards = hand.hands[actor]
        if hand.current.isEmpty {
            if hand.tricks.isEmpty {
                return [0]
            }
            let safe = cards.filter { $0 / 13 != 3 }
            return !hand.broken && !safe.isEmpty ? safe : cards
        }
        let follow = cards.filter { $0 / 13 == hand.current[0].card / 13 }
        if !follow.isEmpty {
            return follow
        }
        if hand.tricks.isEmpty && !rules.blood {
            let safe = cards.filter { !penalty($0) }
            if !safe.isEmpty {
                return safe
            }
        }
        return cards
    }
    func choosePass(_ seat: Int) -> Set<Int> {
        let cards = hand.hands[seat], strategy = bots[seat]
        let low = ordered(cards), high = ordered(cards, high: true)
        var order: [Int] = []
        switch strategy {
        case 1:
            order = high
        case 2:
            order = low
        case 4:
            order = low.filter { $0 / 13 != 3 } + low.filter { $0 / 13 == 3 }
        default:
            let protect = strategy == 3 && cards.contains(36) && cards.filter { $0 / 13 == 2 }.count >= 5
            if !protect {
                order += [36, 37, 38].filter { cards.contains($0) }
            }
            if strategy == 3 {
                let suits = [0, 1].filter { s in cards.contains { $0 / 13 == s } }.sorted { a, b in
                    let ca = cards.filter { $0 / 13 == a }.count, cb = cards.filter { $0 / 13 == b }.count
                    return ca == cb ? a < b : ca < cb
                }
                if let suit = suits.first {
                    order += high.filter { $0 / 13 == suit }
                }
            }
            order += high.filter { $0 / 13 == 3 }
            order += high
        }
        var out = Set<Int>()
        for c in order {
            out.insert(c)
            if out.count == 3 {
                break
            }
        }
        return out
    }
    func queenPlayed() -> Bool {
        hand.taken.contains { $0.contains(36) } || hand.current.contains { $0.card == 36 }
    }
    func choosePlay() -> Int {
        let seat = actor, cards = hand.hands[seat], choices = legal()
        var strategy = bots[seat]
        if strategy == 1 || strategy == 2 {
            return extreme(choices, high: strategy == 2)
        }
        if strategy == 4 && (0..<4)
            .contains(where: { $0 != seat && hand.taken[$0].contains(where: penalty) })
        {
            strategy = 0
        }
        if hand.current.isEmpty {
            let spades = choices.filter { $0 / 13 == 2 && $0 % 13 < 10 }
            if strategy == 3 && !queenPlayed() && !cards.contains(36) && !spades.isEmpty {
                return extreme(spades)
            }
            let suits = (0..<4).filter { s in choices.contains { $0 / 13 == s } }.sorted { a, b in
                let ca = choices.filter { $0 / 13 == a }.count, cb = choices.filter { $0 / 13 == b }.count
                return ca == cb ? a < b : (strategy == 4 ? ca > cb : ca < cb)
            }
            return extreme(choices.filter { $0 / 13 == suits[0] }, high: strategy == 4)
        }
        let led = hand.current[0].card / 13
        if cards.contains(where: { $0 / 13 == led }) {
            let winning = hand.current.filter { $0.card / 13 == led }.map { $0.card % 13 }.max()!
            let lower = choices.filter { $0 % 13 < winning }
            if strategy == 4 {
                let high = extreme(choices, high: true)
                return high % 13 > winning ? high : extreme(choices)
            }
            if !lower.isEmpty {
                return extreme(lower, high: true)
            }
            if strategy == 3 && hand.current.count == 3 {
                let safe = choices.subtracting([36])
                return safe.isEmpty ? 36 : extreme(safe, high: true)
            }
            return extreme(choices)
        }
        if strategy == 4 {
            let safe = choices.filter { !penalty($0) }
            return extreme(safe.isEmpty ? choices : safe)
        }
        if choices.contains(36) {
            return 36
        }
        if strategy == 3 && !queenPlayed() {
            if choices.contains(38) {
                return 38
            }
            if choices.contains(37) {
                return 37
            }
        }
        let hearts = choices.filter { $0 / 13 == 3 }
        return extreme(hearts.isEmpty ? choices : hearts, high: true)
    }
    func winner(_ plays: [Play]) -> Int {
        plays.filter { $0.card / 13 == plays[0].card / 13 }
            .max { $0.card % 13 < $1.card % 13 }!.seat
    }
    func trickLine(_ plays: [Play], _ number: Int) -> String {
        let sequence = plays.map { "\(CardNames.seats[$0.seat]) \(cardText($0.card))" }.joined(separator: " ")
        return "trick \(number): \(sequence) -> \(CardNames.seats[winner(plays)]) \(plays.reduce(0) { $0 + point($1.card) })"
    }
    mutating func play(_ card: Int) {
        let seat = actor
        undo.append(Snapshot(hand: hand, logLength: log.count, seat: seat, card: card))
        hand.hands[seat].remove(card)
        hand.current.append(Play(seat: seat, card: card))
        if card / 13 == 3 || (card == 36 && rules.qsBreak) {
            hand.broken = true
        }
        if hand.current.count == 4 {
            let seat = winner(hand.current)
            hand.taken[seat].formUnion(hand.current.map(\.card))
            hand.counts[seat] += 1
            hand.tricks.append(hand.current)
            write(2, trickLine(hand.current, hand.tricks.count))
            hand.current = []
            hand.leader = seat
            if hand.tricks.count == 13 {
                finishHand()
            }
        }
    }
    mutating func undoCard() -> Play {
        let s = undo.removeLast()
        hand = s.hand
        log.removeSubrange(s.logLength..<log.count)
        return Play(seat: s.seat, card: s.card)
    }
    mutating func claim(_ seat: Int) {
        let all = hand.hands.reduce(Set<Int>()) { $0.union($1) }, count = 13 - hand.tricks.count
        hand.taken[seat].formUnion(all)
        hand.counts[seat] += count
        hand.hands = Array(repeating: [], count: 4)
        write(2, "claim \(CardNames.seats[seat]) tricks \(count) points \(points(all))")
        finishHand()
    }
    func ranking(_ values: [Int]) -> [Int] {
        (0..<4).sorted { a, b in
            values[a] == values[b] ? a < b : values[a] < values[b]
        }
    }
    func ended(_ values: [Int]) -> Bool {
        number >= rules.limit || values.contains { $0 >= rules.target }
    }
    mutating func finishHand() {
        var points = hand.taken.map { self.points($0) }
        let shooter = (0..<4).first { hand.taken[$0].filter(penalty).count == 14 }
        if let shooter {
            points[shooter] -= 26
            var method = rules.moon
            if method == "AUTO" {
                let add = (0..<4).map { scores[$0] + points[$0] + ($0 == shooter ? 0 : 26) }
                method = ended(add) && ranking(add)[0] != shooter ? "SUB" : "ADD"
            }
            if method == "SUB" {
                points[shooter] -= 26
            } else {
                for s in 0..<4 where s != shooter {
                    points[s] += 26
                }
            }
            write(1, "moon \(CardNames.seats[shooter]) \(method)")
        }
        for s in 0..<4 {
            scores[s] += points[s]
            stats[s][0] += hand.counts[s]
            stats[s][1] += hand.taken[s].filter { $0 / 13 == 3 }.count
            stats[s][2] += hand.taken[s].contains(36) ? 1 : 0
            stats[s][3] += shooter == s ? 1 : 0
        }
        write(1, pairs("points", points))
        write(1, pairs("scores", scores))
        history.append(History(
            number: number,
            pass: pass,
            points: points,
            shooter: shooter,
            begin: handBegin,
            end: log.count
        ))
        state = ended(scores) ? .none : .between
        if state == .none {
            write(0, "game over hands \(number)")
            for (rank, seat) in ranking(scores).enumerated() {
                write(
                    0,
                    "rank \(rank + 1) \(CardNames.seats[seat]) \(scores[seat])"
                )
            }
            for s in statsLines() {
                write(0, s)
            }
        }
    }
    func statsLines() -> [String] {
        (0..<4)
            .map { s in
                "stats \(CardNames.seats[s]) tricks \(stats[s][0]) hearts \(stats[s][1]) queens \(stats[s][2]) moons \(stats[s][3])"
            }
    }
    mutating func autoPass() {
        for s in 0..<4 where passes[s] == nil {
            let cards = choosePass(s)
            passCards(s, cards)
        }
    }
    mutating func autoHand() {
        if state == .passing {
            autoPass()
        }
        while state == .playing {
            let c = choosePlay()
            play(c)
        }
    }
    mutating func autoGame() {
        if state == .passing || state == .playing {
            autoHand()
        }
        while state != .none {
            deal()
            autoHand()
        }
    }
}
final class Table {
    var rules = Rules(), bots = [0, 0, 0, 0]
    var game: Game?
    var active: Bool {
        game != nil && game!.state != .none
    }
    func simulate(_ command: String, _ seed: Int, _ count: Int) -> [String] {
        var random = Int64(seed)
        if command == "GAME" {
            var g = Game(rules, bots, random)
            g.autoGame()
            return ["game seed \(seed)"] + g.log.filter { $0.level <= count }.map(\.text)
        }
        let rounds = command == "ROTATE" ? 4 : 1, games = (command == "ROTATE" ? 4 : 1) * count
        var hands = 0, places = Array(repeating: [0, 0, 0, 0], count: 4), totals = [0, 0, 0, 0], stats = Array(
            repeating: [0, 0, 0, 0],
            count: 4
        )
        for r in 0..<rounds {
            var strategies = [0, 0, 0, 0]
            for s in 0..<4 {
                strategies[(s + r) % 4] = bots[s]
            }
            for _ in 0..<count {
                var g = Game(rules, strategies, random)
                g.autoGame()
                random = g.random
                hands += g.number
                let ranks = g.ranking(g.scores)
                for s in 0..<4 {
                    let actual = (s + r) % 4
                    places[s][ranks.firstIndex(of: actual)!] += 1
                    totals[s] += g.scores[actual]
                    for k in 0..<4 {
                        stats[s][k] += g.stats[actual][k]
                    }
                }
            }
        }
        var output = ["\(command.lowercased()) seed \(seed) games \(games) hands \(hands)"]
        for s in 0..<4 {
            let numerator = 100 * totals[s]
            var cents = numerator / games
            if numerator < 0 && numerator % games != 0 {
                cents -= 1
            }
            let magnitude = abs(cents), average = "\(cents < 0 ? "-" : "")\(magnitude / 100)." + String(
                format: "%02d",
                magnitude % 100
            )
            let name = String(CardNames.seats[s]) + (command == "ROTATE" ? " " + CardNames.strategies[bots[s]] : "")
            output
                .append(
                    "\(name) places \(places[s].map(String.init).joined(separator: " ")) total \(totals[s]) average \(average) tricks \(stats[s][0]) hearts \(stats[s][1]) queens \(stats[s][2]) moons \(stats[s][3])"
                )
        }
        return output
    }
    func command(_ line: String) throws -> [String] {
        let words = line.split(separator: " ").map(String.init)
        let command = words[0]
        let a = Array(words.dropFirst())
        let known = [
            "RULE",
            "BOT",
            "SETTINGS",
            "GAME",
            "MATCH",
            "ROTATE",
            "NEW",
            "ABANDON",
            "STACK",
            "DEAL",
            "SHOW",
            "PASS",
            "PLAY",
            "AUTO",
            "UNDO",
            "CLAIM",
            "LEGAL",
            "PREVIEW",
            "SCORE",
            "TAKEN",
            "TRICKS",
            "VOIDS",
            "UNSEEN",
            "STATS",
            "HISTORY",
            "REPLAY"
        ]
        if !known.contains(command) {
            try fail("unknown command " + command)
        }
        switch command {
        case "RULE":
            try rules.validate(a[0], a[1])
            if active {
                try fail("game in progress")
            }
            rules.set(a[0], a[1])
            return ["rule \(a[0]) \(a[1])"]
        case "BOT":
            let seat = try parseSeat(a[0])
            guard let strategy = CardNames.strategies.firstIndex(of: a[1]) else {
                try fail("bad value " + a[1])
            }
            bots[seat] = strategy
            game?.bots[seat] = strategy
            return ["bot \(a[0]) \(a[1])"]
        case "SETTINGS":
            return [rules.text, pairs("bots", bots.map { CardNames.strategies[$0] })]
        case "GAME", "MATCH", "ROTATE":
            let seed = try bounded(a[0], 1, 2147483646), count = try bounded(
                a[1],
                command == "GAME" ? 0 : 1,
                command == "GAME" ? 2 : command == "MATCH" ? 50 : 10
            )
            return simulate(command, seed, count)
        case "NEW":
            let seed = try bounded(a[0], 1, 2147483646)
            if active {
                try fail("game in progress")
            }
            game = Game(rules, bots, Int64(seed))
            return ["new game seed \(seed)"]
        case "ABANDON":
            if !active {
                try fail("no game")
            }
            game = nil
            return ["game abandoned"]
        default:
            break
        }
        var seat = 0, cards: [Int] = []
        if ["STACK", "PASS", "PLAY", "CLAIM"].contains(command) {
            seat = try parseSeat(a[0])
        }
        if ["STACK", "PASS", "PLAY"]
            .contains(command)
        {
            for word in a.dropFirst() {
                cards.append(try parseCard(word))
            }
        }
        if command == "STACK" && cards.count != 13 {
            try fail("need 13 cards")
        }
        let mode = command == "AUTO" ? a[0] : ""
        if command == "AUTO" && !["PASS", "CARD", "TRICK", "HAND", "GAME"]
            .contains(mode)
        {
            try fail("bad value " + mode)
        }
        let state = game?.state ?? .none
        if command == "STACK" || command == "DEAL" {
            if state == .none {
                try fail("no game")
            }
            if state != .between {
                try fail("hand in progress")
            }
        } else if command == "SHOW" || mode == "HAND" {
            if state != .passing && state != .playing {
                try fail("no hand")
            }
        } else if command == "PASS" || mode == "PASS" {
            if state != .passing {
                try fail("not passing")
            }
        } else if ["PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS", "UNSEEN"]
            .contains(command) || mode == "CARD" || mode == "TRICK"
        {
            if state != .playing {
                try fail("not playing")
            }
        } else if state == .none {
            try fail("no game")
        }
        var g = game!, output: [String] = []
        let before = g.log.count
        switch command {
        case "STACK":
            let set = try checkedSet(cards)
            for c in cards {
                for other in 0..<4 where other != seat {
                    if g.stacked[other]?
                        .contains(c) == true
                    {
                        try fail("\(cardText(c)) stacked for \(CardNames.seats[other])")
                    }
                }
            }
            g.stacked[seat] = set
            game = g
            return ["stacked \(CardNames.seats[seat])"]
        case "DEAL":
            g.deal()
        case "SHOW":
            return (0..<4).map { "\(CardNames.seats[$0]): \(cardsText(g.hand.hands[$0]))" }
        case "PASS":
            if g.passes[seat] != nil {
                try fail("\(CardNames.seats[seat]) already passed")
            }
            let set = try checkedSet(cards)
            for c in cards
                where !g.hand.hands[seat]
                .contains(c)
            {
                try fail("\(CardNames.seats[seat]) does not hold \(cardText(c))")
            }
            g.passCards(seat, set)
        case "PLAY":
            let card = cards[0]
            if seat != g.actor {
                try fail("waiting for \(CardNames.seats[g.actor])")
            }
            if !g.hand.hands[seat]
                .contains(card)
            {
                try fail("\(CardNames.seats[seat]) does not hold \(cardText(card))")
            }
            if !g.legal().contains(card) {
                if g.hand.current.isEmpty {
                    try fail(g.hand.tricks.isEmpty ? "must lead 2C" : "hearts not broken")
                }
                let led = g.hand.current[0].card / 13
                if g.hand.hands[seat]
                    .contains(where: { $0 / 13 == led })
                {
                    try fail("must follow \(CardNames.suits[led])")
                }
                try fail("no points on first trick")
            }
            output.append("\(CardNames.seats[seat]) plays \(cardText(card))")
            g.play(card)
        case "AUTO":
            switch mode {
            case "PASS":
                g.autoPass()
            case "CARD":
                let seat = g.actor, card = g.choosePlay()
                output.append("\(CardNames.seats[seat]) plays \(cardText(card))")
                g.play(card)
            case "TRICK":
                let count = g.hand.tricks.count
                while g.state == .playing && g.hand.tricks.count == count {
                    let c = g.choosePlay()
                    g.play(c)
                }
            case "HAND":
                g.autoHand()
            default:
                g.autoGame()
            }
        case "UNDO":
            if g.undo.isEmpty {
                try fail("nothing to undo")
            }
            let p = g.undoCard()
            game = g
            return ["undo \(CardNames.seats[p.seat]) \(cardText(p.card))"]
        case "CLAIM":
            if seat != g.actor {
                try fail("waiting for \(CardNames.seats[g.actor])")
            }
            if !g.hand.current.isEmpty {
                try fail("trick in progress")
            }
            for c in g.hand.hands[seat] {
                for other in 0..<4 where other != seat {
                    if g.hand.hands[other]
                        .contains(where: { $0 / 13 == c / 13 && $0 % 13 > c % 13 })
                    {
                        try fail("claim rejected")
                    }
                }
            }
            g.claim(seat)
        case "LEGAL":
            return [
                "legal \(CardNames.seats[g.actor]): \(cardsText(g.legal())) bot \(cardText(g.choosePlay()))"
            ]
        case "PREVIEW":
            for c in g.legal().sorted() {
                var copy = g
                let count = copy.hand.tricks.count
                copy.play(c)
                while copy.state == .playing && copy.hand.tricks.count == count {
                    let c = copy.choosePlay()
                    copy.play(c)
                }
                let trick = copy.hand.tricks.last!
                output
                    .append(
                        "preview \(cardText(c)) -> \(CardNames.seats[copy.winner(trick)]) \(trick.reduce(0) { $0 + copy.point($1.card) })"
                    )
            }
            return output
        case "SCORE":
            output.append(pairs("scores", g.scores))
            if g.state == .playing {
                output.append(pairs("taken", g.hand.taken.map { g.points($0) }))
            }
            return output
        case "TAKEN":
            return (0..<4)
                .map { s in "\(CardNames.seats[s]): \(cardsText(g.hand.taken[s].filter { g.point($0) != 0 }))" }
        case "TRICKS":
            for (i, trick) in g.hand.tricks.enumerated() {
                output.append(g.trickLine(trick, i + 1))
            }
            if !g.hand.current
                .isEmpty
            {
                output
                    .append("current: " + g.hand.current.map { "\(CardNames.seats[$0.seat]) \(cardText($0.card))" }
                        .joined(separator: " "))
            }
            return output.isEmpty ? ["no tricks"] : output
        case "VOIDS":
            var missing = Array(repeating: Set<Int>(), count: 4)
            for trick in g.hand.tricks + [g.hand.current] where !trick.isEmpty {
                let led = trick[0].card / 13
                for p in trick where p.card / 13 != led {
                    missing[p.seat].insert(led)
                }
            }
            return [pairs("voids", missing.map { $0.isEmpty ? "-" : String($0.sorted().map { CardNames.suits[$0] }) })]
        case "UNSEEN":
            let seen = g.hand.taken.reduce(g.hand.hands[g.actor]) { $0.union($1) }.union(g.hand.current.map(\.card))
            return ["unseen \(CardNames.seats[g.actor]): \(cardsText(Set(0..<52).subtracting(seen)))"]
        case "STATS":
            return g.statsLines()
        case "HISTORY":
            return g.history.isEmpty ? ["no hands"] : g.history.map { h in
                "hand \(h.number) pass \(direction(h.pass)) \(pairs("points", h.points))" +
                    (h.shooter.map { " moon \(CardNames.seats[$0])" } ?? "")
            }
        case "REPLAY":
            let number = try bounded(a[0], 1, g.history.count), h = g.history[number - 1]
            return g.log[h.begin..<h.end].map(\.text)
        default:
            break
        }
        output += g.log.dropFirst(before).map(\.text)
        game = g
        return output
    }
}
let table = Table()
let count = Int(readLine()!)!
for _ in 0..<count {
    let line = readLine()!
    do { for s in try table.command(line) {
        print(s)
    } } catch let error as CommandError { print("error: " + error.reason) }
    catch { fatalError("Unexpected error") }
}
