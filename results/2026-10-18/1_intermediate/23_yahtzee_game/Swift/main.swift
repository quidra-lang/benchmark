typealias Counts = [Int]
typealias Holds = [Bool]

enum CommandError: Error {
    case reason(String)
}

enum Category: Int, CaseIterable {
    case ones, twos, threes, fours, fives, sixes, threeKind, fourKind
    case fullHouse, small, large, yahtzee, chance

    var name: String {
        ["ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
         "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"][rawValue]
    }
    var isUpper: Bool { rawValue < 6 }
}

enum Strategy: String {
    case kind = "KIND", straight = "STRAIGHT", high = "HIGH", upper = "UPPER"
}
enum Joker: String {
    case forced = "FORCED", free = "FREE", off = "OFF"
}

struct Rules {
    var rolls = 3
    var joker = Joker.forced
}

let powersOfSix: [Int64] = [1, 6, 36, 216, 1296, 7776]
let factorial = [1, 1, 2, 6, 24, 120]

func integerWord(_ word: String, minimum: Int64, maximum: Int64) throws -> Int64 {
    let bytes = Array(word.utf8)
    let first = bytes[0] == 45 ? 1 : 0
    guard first < bytes.count, word != "-0",
          bytes.count - first == 1 || bytes[first] != 48 else {
        throw CommandError.reason("bad value \(word)")
    }
    var value: Int64 = 0
    for byte in bytes[first...] {
        guard byte >= 48 && byte <= 57 else { throw CommandError.reason("bad value \(word)") }
        value = value * 10 + Int64(byte - 48)
    }
    if first == 1 { value = -value }
    guard value >= minimum && value <= maximum else { throw CommandError.reason("bad value \(word)") }
    return value
}

func playerName(_ word: String) throws {
    guard word.utf8.count <= 8, word.utf8.allSatisfy({ $0 >= 65 && $0 <= 90 }) else {
        throw CommandError.reason("bad name \(word)")
    }
}

func holdPattern(_ word: String) throws -> Holds {
    let bytes = Array(word.utf8)
    guard bytes.count == 5, bytes.allSatisfy({ $0 == 48 || $0 == 49 }) else {
        throw CommandError.reason("bad pattern \(word)")
    }
    return bytes.map { $0 == 49 }
}

func categoryWord(_ word: String) throws -> Category {
    guard let category = Category.allCases.first(where: { $0.name == word }) else {
        throw CommandError.reason("bad category \(word)")
    }
    return category
}

func strategyWord(_ word: String) throws -> Strategy {
    guard let strategy = Strategy(rawValue: word) else { throw CommandError.reason("bad strategy \(word)") }
    return strategy
}

func fraction(_ numerator: Int64, _ denominator: Int64) -> String {
    var a = numerator
    var b = denominator
    while b != 0 { (a, b) = (b, a % b) }
    let top = numerator / a
    let bottom = denominator / a
    return bottom == 1 ? "\(top)" : "\(top)/\(bottom)"
}

func average(_ sum: Int64, _ count: Int64) -> String {
    let value = count == 0 ? 0 : 100 * sum / count
    let cents = String(value % 100)
    return "\(value / 100)." + (cents.count == 1 ? "0" : "") + cents
}

func patternText(_ holds: Holds) -> String { holds.map { $0 ? "1" : "0" }.joined() }

func facesText(_ dice: [Int], selected: Holds = [true, true, true, true, true]) -> String {
    let faces = dice.indices.filter { selected[$0] }.map { String(dice[$0]) }
    return faces.isEmpty ? "-" : faces.joined(separator: " ")
}

func faceCounts(_ dice: [Int], selected: Holds = [true, true, true, true, true]) -> Counts {
    var counts = Array(repeating: 0, count: 6)
    for i in dice.indices where selected[i] { counts[dice[i] - 1] += 1 }
    return counts
}

func mostFrequent(_ counts: Counts) -> Int {
    var best = 0
    for face in 1..<6 where counts[face] >= counts[best] { best = face }
    return best
}

func isYahtzee(_ counts: Counts) -> Bool { counts.contains(5) }

func normalScore(_ category: Category, _ counts: Counts) -> Int {
    if category.isUpper { return (category.rawValue + 1) * counts[category.rawValue] }
    let sum = counts.enumerated().reduce(0) { $0 + ($1.offset + 1) * $1.element }
    let largest = counts.max()!
    switch category {
    case .threeKind: return largest >= 3 ? sum : 0
    case .fourKind: return largest >= 4 ? sum : 0
    case .fullHouse: return counts.contains(3) && counts.contains(2) ? 25 : 0
    case .small, .large:
        let length = category == .small ? 4 : 5
        for start in 0...(6 - length) {
            if (start..<(start + length)).allSatisfy({ counts[$0] > 0 }) {
                return category == .small ? 30 : 40
            }
        }
        return 0
    case .yahtzee: return largest == 5 ? 50 : 0
    default: return sum
    }
}

final class Player {
    let name: String
    var strategy = Strategy.kind
    var boxes = Array<Int?>(repeating: nil, count: 13)
    var yahtzeeBonus = 0

    init(_ name: String) { self.name = name }
    var upper: Int { boxes.prefix(6).compactMap { $0 }.reduce(0, +) }
    var upperBonus: Int { upper >= 63 ? 35 : 0 }
    var total: Int { boxes.compactMap { $0 }.reduce(0, +) + upperBonus + yahtzeeBonus }
    var round: Int { boxes.filter { $0 != nil }.count + 1 }
}

struct Candidates {
    var allowed = Array(repeating: false, count: 13)
    var points = Array(repeating: 0, count: 13)
    var best = Category.ones
    var joker = false
    var requirement = ""
}

func candidates(_ player: Player, _ counts: Counts, joker: Joker) -> Candidates {
    var result = Candidates()
    result.allowed = player.boxes.map { $0 == nil }
    result.joker = joker != .off && isYahtzee(counts) && player.boxes[Category.yahtzee.rawValue] != nil
    if result.joker && joker == .forced {
        let face = mostFrequent(counts)
        if player.boxes[face] == nil {
            result.allowed = Array(repeating: false, count: 13)
            result.allowed[face] = true
            result.requirement = Category(rawValue: face)!.name
        } else if result.allowed[6...].contains(true) {
            for index in 0..<6 { result.allowed[index] = false }
            result.requirement = "lower box"
        }
    }
    var bestScore = -1
    for category in Category.allCases where result.allowed[category.rawValue] {
        var points = normalScore(category, counts)
        if result.joker {
            if category == .fullHouse { points = 25 }
            if category == .small { points = 30 }
            if category == .large { points = 40 }
        }
        result.points[category.rawValue] = points
        if points > bestScore { bestScore = points; result.best = category }
    }
    return result
}

func botHolds(_ strategy: Strategy, _ dice: [Int]) -> Holds {
    if strategy == .high { return dice.map { $0 >= 5 } }
    let counts = faceCounts(dice)
    if strategy == .straight {
        var bestStart = 0
        var bestLength = 0
        for start in 0..<6 {
            var length = 0
            while start + length < 6 && counts[start + length] > 0 { length += 1 }
            if length >= bestLength { bestStart = start; bestLength = length }
        }
        if bestLength >= 3 {
            var holds = Array(repeating: false, count: 5)
            for face in (bestStart + 1)...(bestStart + bestLength) {
                holds[dice.firstIndex(of: face)!] = true
            }
            return holds
        }
    }
    let target = mostFrequent(counts) + 1
    return dice.map { $0 == target }
}

struct Outcome {
    let counts: Counts
    let weight: Int64
}

struct Rerolls {
    let outcomes: [[Outcome]]

    private static func distribution(_ total: Int) -> [Outcome] {
        var outcomes: [Outcome] = []
        var counts = Array(repeating: 0, count: 6)
        func visit(_ remaining: Int, face: Int) {
            if face == 5 {
                counts[face] = remaining
                let divisor = counts.reduce(1) { $0 * factorial[$1] }
                outcomes.append(Outcome(counts: counts, weight: Int64(factorial[total] / divisor)))
                return
            }
            for count in 0...remaining {
                counts[face] = count
                visit(remaining - count, face: face + 1)
            }
        }
        visit(total, face: 0)
        return outcomes
    }

    init() { outcomes = (0...5).map(Self.distribution) }
}

func combined(_ held: Counts, _ rolled: Counts) -> Counts {
    zip(held, rolled).map { $0.0 + $0.1 }
}

struct Advice {
    let holds: Holds
    let numerator: Int64
    let denominator: Int64
}

func advise(_ player: Player, dice: [Int], rollsLeft: Int, joker: Joker, rerolls: Rerolls) -> Advice {
    var values: [Counts: Int64] = [:]
    for outcome in rerolls.outcomes[5] {
        let scores = candidates(player, outcome.counts, joker: joker)
        values[outcome.counts] = Int64(scores.points[scores.best.rawValue])
    }
    var denominator: Int64 = 1
    var expectations: [Counts: Int64] = [:]
    for depth in 1...rollsLeft {
        expectations.removeAll(keepingCapacity: true)
        for kept in 0...5 {
            let rolled = 5 - kept
            for held in rerolls.outcomes[kept] {
                var sum: Int64 = 0
                for outcome in rerolls.outcomes[rolled] {
                    sum += outcome.weight * values[combined(held.counts, outcome.counts)]!
                }
                expectations[held.counts] = sum * (powersOfSix[5] / powersOfSix[rolled])
            }
        }
        denominator *= powersOfSix[5]
        if depth == rollsLeft { break }
        var next: [Counts: Int64] = [:]
        for outcome in rerolls.outcomes[5] {
            var best: Int64 = 0
            for (held, expected) in expectations {
                if zip(held, outcome.counts).allSatisfy({ $0.0 <= $0.1 }) { best = max(best, expected) }
            }
            next[outcome.counts] = best
        }
        values = next
    }
    var best = Advice(holds: Array(repeating: false, count: 5), numerator: -1, denominator: denominator)
    for mask in 0..<32 {
        let holds = (0..<5).map { mask & (1 << (4 - $0)) != 0 }
        let expected = expectations[faceCounts(dice, selected: holds)]!
        if expected > best.numerator { best = Advice(holds: holds, numerator: expected, denominator: denominator) }
    }
    return best
}

struct Turn {
    var player: Int
    var rolls = 0
    var dice = Array(repeating: 0, count: 5)
    var holds = Array(repeating: false, count: 5)
}

struct ScoreEntry {
    let turn: Turn
    let category: Category
    let points: Int
    let yahtzeeBonus: Int
    let joker: Bool
}

struct RedoEntry {
    let resume: Turn?
    let score: ScoreEntry
}

final class Game {
    let rules: Rules
    let players: [Player]
    private let output: ((String) -> Void)?
    var state: Int64
    var loaded: [Int] = []
    var loadedHead = 0
    var faceTotals = Array<Int64>(repeating: 0, count: 6)
    var turn: Turn? = Turn(player: 0)
    var entries: [ScoreEntry] = []
    var redo: [RedoEntry] = []

    init(seed: Int64, names: [String], rules: Rules, output: ((String) -> Void)? = nil) {
        self.state = seed
        self.players = names.map(Player.init)
        self.rules = rules
        self.output = output
    }

    var loadedCount: Int { loaded.count - loadedHead }
    private func emit(_ line: String) { output?(line) }

    private func rollDie() -> Int {
        let face: Int
        if loadedHead < loaded.count {
            face = loaded[loadedHead]
            loadedHead += 1
        } else {
            state = 48271 * state % 2147483647
            face = Int(state % 6) + 1
        }
        faceTotals[face - 1] += 1
        return face
    }

    func turnCheck() throws {
        guard turn != nil else { throw CommandError.reason("game over") }
    }
    func rolledCheck() throws {
        try turnCheck()
        guard turn!.rolls != 0 else { throw CommandError.reason("not rolled") }
    }
    func rollsLeftCheck() throws {
        try rolledCheck()
        guard turn!.rolls != rules.rolls else { throw CommandError.reason("no rolls left") }
    }
    func ranking() -> [Int] {
        players.indices.sorted {
            players[$0].total != players[$1].total ? players[$0].total > players[$1].total : $0 < $1
        }
    }
    var nextTurnText: String {
        guard let turn else { return "game over" }
        let player = players[turn.player]
        return "turn \(player.round) \(player.name)"
    }

    func roll() {
        redo.removeAll()
        var current = turn!
        for die in 0..<5 where current.rolls == 0 || !current.holds[die] { current.dice[die] = rollDie() }
        current.rolls += 1
        turn = current
        emit("\(players[current.player].name) roll \(current.rolls): \(facesText(current.dice))")
    }

    func hold(_ holds: Holds) {
        redo.removeAll()
        var current = turn!
        current.holds = holds
        turn = current
        emit("\(players[current.player].name) holds \(patternText(holds)): \(facesText(current.dice, selected: holds))")
    }

    func scoreDetails(_ category: Category) -> ScoreEntry {
        let current = turn!
        let player = players[current.player]
        let counts = faceCounts(current.dice)
        let scores = candidates(player, counts, joker: rules.joker)
        let bonus = isYahtzee(counts) && player.boxes[Category.yahtzee.rawValue] == 50 ? 100 : 0
        return ScoreEntry(turn: current, category: category, points: scores.points[category.rawValue],
                          yahtzeeBonus: bonus, joker: scores.joker)
    }

    func checkedScore(_ category: Category) throws -> ScoreEntry {
        try rolledCheck()
        let current = turn!
        let player = players[current.player]
        guard player.boxes[category.rawValue] == nil else { throw CommandError.reason("\(category.name) already used") }
        let scores = candidates(player, faceCounts(current.dice), joker: rules.joker)
        guard scores.allowed[category.rawValue] else { throw CommandError.reason("joker requires \(scores.requirement)") }
        return scoreDetails(category)
    }

    func scoreText(_ entry: ScoreEntry, hypothetical: Bool) -> String {
        let player = players[entry.turn.player]
        let upperAfter = player.upper + (entry.category.isUpper ? entry.points : 0)
        let addedUpper = upperAfter >= 63 && player.upperBonus == 0 ? 35 : 0
        var line = "\(player.name) \(hypothetical ? "would score" : "scores") \(entry.points) in \(entry.category.name)"
        if entry.joker { line += " joker" }
        if entry.yahtzeeBonus != 0 { line += " ybonus 100" }
        if addedUpper != 0 { line += " ubonus 35" }
        return line + " total \(player.total + entry.points + entry.yahtzeeBonus + addedUpper)"
    }

    func score(_ category: Category) {
        let entry = scoreDetails(category)
        let line = scoreText(entry, hypothetical: false)
        let player = players[entry.turn.player]
        player.boxes[category.rawValue] = entry.points
        player.yahtzeeBonus += entry.yahtzeeBonus
        entries.append(entry)
        redo.removeAll()
        turn = entries.count == 13 * players.count ? nil : Turn(player: (entry.turn.player + 1) % players.count)
        emit(line)
        emit(nextTurnText)
    }

    func botTurn() {
        if turn!.rolls == 0 { roll() }
        let strategy = players[turn!.player].strategy
        while turn!.rolls < rules.rolls {
            let holds = botHolds(strategy, turn!.dice)
            if holds.allSatisfy({ $0 }) { break }
            hold(holds)
            roll()
        }
        let counts = faceCounts(turn!.dice)
        let scores = candidates(players[turn!.player], counts, joker: rules.joker)
        let face = mostFrequent(counts)
        let category = strategy == .upper && counts[face] >= 3 && scores.allowed[face] ? Category(rawValue: face)! : scores.best
        score(category)
    }

    func undoScore() throws {
        guard let entry = entries.popLast() else { throw CommandError.reason("nothing to undo") }
        players[entry.turn.player].boxes[entry.category.rawValue] = nil
        players[entry.turn.player].yahtzeeBonus -= entry.yahtzeeBonus
        redo.append(RedoEntry(resume: turn, score: entry))
        turn = entry.turn
        emit("undo \(players[entry.turn.player].name) \(entry.category.name) \(entry.points)")
    }

    func redoScore() throws {
        guard let saved = redo.popLast() else { throw CommandError.reason("nothing to redo") }
        let entry = saved.score
        players[entry.turn.player].boxes[entry.category.rawValue] = entry.points
        players[entry.turn.player].yahtzeeBonus += entry.yahtzeeBonus
        entries.append(entry)
        turn = saved.resume
        emit("redo \(players[entry.turn.player].name) \(entry.category.name) \(entry.points)")
    }
}

struct Record {
    var games: Int64 = 0
    var wins: Int64 = 0
    var sum: Int64 = 0
    var best = 0
}

struct SimulationTotal {
    var wins: Int64 = 0
    var sum: Int64 = 0
    var bonus: Int64 = 0
    var yahtzee: Int64 = 0
    var best = 0
}

final class Program {
    private var rules = Rules()
    private let rerolls = Rerolls()
    private var game: Game?
    private var records: [String: Record] = [:]
    private var output: [String] = []

    private func emit(_ parts: Any...) {
        output.append(parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func requireGame() throws -> Game {
        guard let game else { throw CommandError.reason("no game") }
        return game
    }

    private func odds(_ table: Game, holds: Holds) {
        let turn = table.turn!
        let player = table.players[turn.player]
        let held = faceCounts(turn.dice, selected: holds)
        let rolled = 5 - held.reduce(0, +)
        let outcomes = powersOfSix[rolled]
        var sums = Array<Int64>(repeating: 0, count: 13)
        var positive = Array<Int64>(repeating: 0, count: 13)
        var bestSum: Int64 = 0
        for outcome in rerolls.outcomes[rolled] {
            let scores = candidates(player, combined(held, outcome.counts), joker: rules.joker)
            for index in 0..<13 {
                sums[index] += outcome.weight * Int64(scores.points[index])
                if scores.points[index] > 0 { positive[index] += outcome.weight }
            }
            bestSum += outcome.weight * Int64(scores.points[scores.best.rawValue])
        }
        emit("odds", patternText(holds), "outcomes", outcomes)
        for category in Category.allCases where player.boxes[category.rawValue] == nil {
            let index = category.rawValue
            emit(category.name, "expect", fraction(sums[index], outcomes), "chance", fraction(positive[index], outcomes))
        }
        emit("best expect", fraction(bestSum, outcomes))
    }

    private func card(_ table: Game) {
        let totals = ["UPPER", "BONUS", "YBONUS", "TOTAL"]
        for row in -1..<17 {
            let heading = row == -1 ? "CATEGORY" : row < 13 ? Category(rawValue: row)!.name : totals[row - 13]
            var line = heading + String(repeating: " ", count: 9 - heading.count)
            for player in table.players {
                let cell: String
                if row == -1 { cell = player.name }
                else if row < 13 { cell = player.boxes[row].map(String.init) ?? "-" }
                else { cell = String([player.upper, player.upperBonus, player.yahtzeeBonus, player.total][row - 13]) }
                let width = max(4, player.name.count)
                line += " " + String(repeating: " ", count: max(0, width - cell.count)) + cell
            }
            emit(line)
        }
    }

    private func statistics(_ table: Game) {
        for seat in table.players.indices {
            let entries = table.entries.filter { $0.turn.player == seat }
            let turns = Int64(entries.count)
            let rolls = entries.reduce(Int64(0)) { $0 + Int64($1.turn.rolls) }
            let zeros = entries.filter { $0.points == 0 }.count
            let yahtzees = entries.filter { isYahtzee(faceCounts($0.turn.dice)) }.count
            let sum = entries.reduce(Int64(0)) { $0 + Int64($1.points) }
            emit("stats", table.players[seat].name, "turns", turns, "rolls", rolls, "zeros", zeros,
                 "yahtzees", yahtzees, "average", average(sum, turns))
        }
    }

    private func simulate(seed: Int64, count: Int, strategies: [Strategy]) {
        var totals = Array(repeating: SimulationTotal(), count: strategies.count)
        let names = Array(["A", "B", "C", "D", "E", "F"].prefix(strategies.count))
        var state = seed
        for _ in 0..<count {
            let simulation = Game(seed: state, names: names, rules: rules)
            for seat in strategies.indices { simulation.players[seat].strategy = strategies[seat] }
            while simulation.turn != nil { simulation.botTurn() }
            state = simulation.state
            totals[simulation.ranking()[0]].wins += 1
            for seat in strategies.indices {
                let player = simulation.players[seat]
                totals[seat].sum += Int64(player.total)
                totals[seat].best = max(totals[seat].best, player.total)
                if player.upperBonus == 35 { totals[seat].bonus += 1 }
                if player.boxes[Category.yahtzee.rawValue] == 50 { totals[seat].yahtzee += 1 }
            }
        }
        emit("sim seed", seed, "games", count, "players", strategies.count)
        for seat in strategies.indices {
            let total = totals[seat]
            emit("seat", seat + 1, strategies[seat].rawValue, "wins", total.wins,
                 "average", average(total.sum, Int64(count)), "best", total.best, "bonus", total.bonus, "yahtzee", total.yahtzee)
        }
    }

    private func execute(_ words: [String]) throws {
        switch words[0] {
        case "RULE":
            guard words[1] == "ROLLS" || words[1] == "JOKER" else { throw CommandError.reason("unknown rule \(words[1])") }
            var changed = rules
            if words[1] == "ROLLS" {
                changed.rolls = Int(try integerWord(words[2], minimum: 1, maximum: 4))
            } else {
                guard let joker = Joker(rawValue: words[2]) else { throw CommandError.reason("bad value \(words[2])") }
                changed.joker = joker
            }
            guard game == nil else { throw CommandError.reason("game in progress") }
            rules = changed
            emit("rule", words[1], words[2])
        case "GAME":
            let seed = try integerWord(words[1], minimum: 1, maximum: 2147483646)
            let names = Array(words.dropFirst(2))
            for name in names { try playerName(name) }
            guard names.count <= 6 else { throw CommandError.reason("too many players") }
            guard game == nil else { throw CommandError.reason("game in progress") }
            var seen: Set<String> = []
            for name in names {
                guard seen.insert(name).inserted else { throw CommandError.reason("duplicate name \(name)") }
            }
            game = Game(seed: seed, names: names, rules: rules, output: { [unowned self] line in self.output.append(line) })
            emit("game seed", seed, "players", names.joined(separator: " "))
            emit(game!.nextTurnText)
        case "BOT":
            try playerName(words[1])
            let strategy = try strategyWord(words[2])
            let table = try requireGame()
            guard let player = table.players.first(where: { $0.name == words[1] }) else {
                throw CommandError.reason("no player \(words[1])")
            }
            player.strategy = strategy
            emit("bot", words[1], words[2])
        case "LOAD", "KEEP":
            let faces = try words.dropFirst().map { Int(try integerWord($0, minimum: 1, maximum: 6)) }
            let table = try requireGame()
            if words[0] == "LOAD" {
                table.loaded.append(contentsOf: faces)
                emit("loaded", table.loadedCount)
            } else {
                try table.rollsLeftCheck()
                var holds = Array(repeating: false, count: 5)
                for face in faces {
                    guard let die = (0..<5).first(where: { !holds[$0] && table.turn!.dice[$0] == face }) else {
                        throw CommandError.reason("not showing \(face)")
                    }
                    holds[die] = true
                }
                table.hold(holds)
            }
        case "ROLL":
            let table = try requireGame()
            try table.turnCheck()
            guard table.turn!.rolls != rules.rolls else { throw CommandError.reason("no rolls left") }
            guard !table.turn!.holds.allSatisfy({ $0 }) else { throw CommandError.reason("all dice held") }
            table.roll()
        case "HOLD", "ODDS":
            let holds = try holdPattern(words[1])
            let table = try requireGame()
            try table.rollsLeftCheck()
            if words[0] == "HOLD" { table.hold(holds) }
            else { odds(table, holds: holds) }
        case "SCORE", "WHATIF":
            let category = try categoryWord(words[1])
            let table = try requireGame()
            let entry = try table.checkedScore(category)
            if words[0] == "SCORE" { table.score(category) }
            else { emit(table.scoreText(entry, hypothetical: true)) }
        case "UNDO":
            try requireGame().undoScore()
        case "REDO":
            try requireGame().redoScore()
        case "SUGGEST":
            let table = try requireGame()
            try table.rolledCheck()
            let player = table.players[table.turn!.player]
            let scores = candidates(player, faceCounts(table.turn!.dice), joker: rules.joker)
            var line = "suggest"
            for category in Category.allCases where player.boxes[category.rawValue] == nil {
                line += " \(category.name) \(scores.points[category.rawValue])"
            }
            emit(line, "best", scores.best.name, scores.points[scores.best.rawValue])
        case "ADVISE":
            let table = try requireGame()
            try table.rollsLeftCheck()
            let turn = table.turn!
            let best = advise(table.players[turn.player], dice: turn.dice, rollsLeft: rules.rolls - turn.rolls,
                              joker: rules.joker, rerolls: rerolls)
            emit("advise", patternText(best.holds) + ":", facesText(turn.dice, selected: best.holds),
                 "expect", fraction(best.numerator, best.denominator))
        case "AUTO":
            let count = Int(try integerWord(words[1], minimum: 1, maximum: 100))
            let table = try requireGame()
            try table.turnCheck()
            table.redo.removeAll()
            for _ in 0..<count {
                if table.turn == nil { break }
                table.botTurn()
            }
        case "STATUS":
            let table = try requireGame()
            if let turn = table.turn {
                let player = table.players[turn.player]
                emit("status round", player.round, "player", player.name, "rolls", turn.rolls,
                     "dice", turn.rolls == 0 ? "-" : facesText(turn.dice), "holds", patternText(turn.holds))
            } else { emit("status game over") }
        case "CARD":
            card(try requireGame())
        case "BONUS":
            let table = try requireGame()
            for player in table.players {
                let upper = player.upper
                let maximum = upper + (0..<6).filter { player.boxes[$0] == nil }.reduce(0) { $0 + 5 * ($1 + 1) }
                let status = upper >= 63 ? "made" : maximum < 63 ? "lost" : "open"
                emit("bonus", player.name, "upper", upper, "need", max(63 - upper, 0), "max", maximum, status)
            }
        case "STATS":
            statistics(try requireGame())
        case "LOG":
            let table = try requireGame()
            if table.entries.isEmpty { emit("no scores") }
            for (index, entry) in table.entries.enumerated() {
                var suffix = ""
                if entry.joker { suffix += " joker" }
                if entry.yahtzeeBonus != 0 { suffix += " ybonus 100" }
                emit("log", index + 1, table.players[entry.turn.player].name, facesText(entry.turn.dice),
                     entry.category.name, "\(entry.points)" + suffix)
            }
        case "FACES":
            let table = try requireGame()
            let total = table.faceTotals.reduce(0, +)
            let squares = table.faceTotals.reduce(0) { $0 + $1 * $1 }
            emit("faces", table.faceTotals.map(String.init).joined(separator: " "), "total", total,
                 "chi2", total == 0 ? "0" : fraction(6 * squares - total * total, total))
        case "STANDINGS", "END":
            let table = try requireGame()
            let ranking = table.ranking()
            let finished = table.turn == nil
            if words[0] == "END" { emit("end", finished ? "final" : "abandoned") }
            let best = table.players[ranking[0]].total
            for (rank, seat) in ranking.enumerated() {
                let player = table.players[seat]
                if words[0] == "STANDINGS" {
                    emit("standing", rank + 1, player.name, player.total, "behind", best - player.total)
                } else {
                    emit("rank", rank + 1, player.name, player.total)
                    if finished {
                        var record = records[player.name, default: Record()]
                        record.games += 1
                        if rank == 0 { record.wins += 1 }
                        record.sum += Int64(player.total)
                        record.best = max(record.best, player.total)
                        records[player.name] = record
                    }
                }
            }
            if words[0] == "END" { game = nil }
        case "RECORDS":
            let names = records.keys.sorted {
                let first = records[$0]!
                let second = records[$1]!
                if first.wins != second.wins { return first.wins > second.wins }
                if first.best != second.best { return first.best > second.best }
                return $0 < $1
            }
            if names.isEmpty { emit("no records") }
            for name in names {
                let record = records[name]!
                emit("record", name, "games", record.games, "wins", record.wins, "best", record.best, "average", average(record.sum, record.games))
            }
        case "SIM":
            let seed = try integerWord(words[1], minimum: 1, maximum: 2147483646)
            let count = Int(try integerWord(words[2], minimum: 1, maximum: 50))
            let strategies = try words.dropFirst(3).map(strategyWord)
            guard strategies.count <= 6 else { throw CommandError.reason("too many players") }
            simulate(seed: seed, count: count, strategies: strategies)
        default:
            throw CommandError.reason("unknown command \(words[0])")
        }
    }

    func process(_ line: String) {
        do { try execute(line.split(separator: " ").map(String.init)) }
        catch CommandError.reason(let reason) { emit("error:", reason) }
        catch { fatalError("Unexpected command error: \(error)") }
    }

    func printOutput() {
        if !output.isEmpty { print(output.joined(separator: "\n")) }
    }
}

let count = Int(readLine()!)!
let program = Program()
for _ in 0..<count { program.process(readLine()!) }
program.printOutput()
