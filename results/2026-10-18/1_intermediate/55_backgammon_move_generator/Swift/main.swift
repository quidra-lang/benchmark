import Foundation

typealias Position = [[Int]]
struct Move: Hashable {
    let from: Int
    let to: Int
}
struct State {
    var pos: Position
    var side = 0
    var cube = 1
    var owner: Int? = nil
    var pending = false
    var over = false
    var score: [Int]

    static func initial(score: [Int] = [0, 0]) -> State {
        var own = Array(repeating: 0, count: 26)
        own[24] = 2
        own[13] = 5
        own[8] = 3
        own[6] = 5
        return State(pos: [own, own], score: score)
    }
}
struct Play {
    let pos: Position
    let key: [Move]
    let text: String
    let count: Int
    let firstDie: Int
}
struct Plays {
    let all: [Play]
    let legal: [Play]
    let maximum: Int
}
struct Entry {
    let record: String
    let before: State
    let after: State
}
struct Outcome {
    let winner: Int
    let kind: String
    let points: Int
}
struct Simulation {
    let outcome: Outcome
    let turns: Int
    let first: Int
}
final class RandomStream {
    private var value: Int64
    init(_ seed: Int64) {
        value = seed
    }
    func next() -> Int64 {
        value = value * 48271 % 2147483647
        return value
    }
    func die() -> Int {
        Int(next() % 6) + 1
    }
}
enum EngineError: Error { case message(String) }
func require(_ valid: Bool, _ message: String) throws {
    if !valid {
        throw EngineError.message(message)
    }
}
func color(_ side: Int) -> String {
    side == 0 ? "W" : "B"
}
func pairLess(_ a: Move, _ b: Move) -> Bool {
    a.from != b.from ? a.from > b.from : a.to > b.to
}
func keyLess(_ a: [Move], _ b: [Move]) -> Bool {
    for i in 0..<min(a.count, b.count) {
        if a[i] != b[i] {
            return pairLess(a[i], b[i])
        }
    }
    return a.count > b.count
}
func notation(_ moves: [Move], _ hits: Set<Int>) -> ([Move], String) {
    var key = moves.sorted(by: pairLess)
    while true {
        var pair: (Int, Int)?
        for i in key.indices {
            let t = key[i].to
            if t == 0 || hits.contains(t) {
                continue
            }
            if let j = key.firstIndex(where: { $0.from == t }) {
                pair = (i, j)
                break
            }
        }
        guard let (ai, bi) = pair else {
            break
        }
        let merged = Move(from: key[ai].from, to: key[bi].to)
        key.remove(at: max(ai, bi))
        key.remove(at: min(ai, bi))
        key.append(merged)
        key.sort(by: pairLess)
    }
    var parts: [String] = []
    var marked = Set<Int>()
    var i = 0
    while i < key.count {
        let move = key[i]
        var j = i + 1
        while j < key.count && key[j] == move {
            j += 1
        }
        let from = move.from == 25 ? "bar" : String(move.from)
        let to = move.to == 0 ? "off" : String(move.to)
        var text = "\(from)/\(to)"
        if hits.contains(move.to) && marked.insert(move.to).inserted {
            text += "*"
        }
        if j - i > 1 {
            text += "(\(j - i))"
        }
        parts.append(text)
        i = j
    }
    return (key, parts.isEmpty ? "none" : parts.joined(separator: " "))
}
func enumerate(_ pos: Position, _ side: Int, _ d1: Int, _ d2: Int) -> Plays {
    var all: [Play] = []
    let dice = d1 == d2 ? Array(repeating: d1, count: 4) : [d1, d2]
    func visit(_ board: Position, _ remaining: [Int], _ moves: [Move], _ hits: Set<Int>, _ firstDie: Int) {
        let (key, text) = notation(moves, hits)
        all.append(Play(pos: board, key: key, text: text, count: moves.count, firstDie: firstDie))
        var tried = Set<Int>()
        for (di, die) in remaining.enumerated() {
            if !tried.insert(die).inserted {
                continue
            }
            for s in 1...25 {
                if board[side][s] == 0 || (board[side][25] > 0 && s != 25) {
                    continue
                }
                let t = max(0, s - die)
                if t > 0 {
                    if board[1 - side][25 - t] >= 2 {
                        continue
                    }
                } else {
                    if board[side][25] > 0 || (7...24).contains(where: { board[side][$0] > 0 }) {
                        continue
                    }
                    if s < die && (s + 1...6).contains(where: { board[side][$0] > 0 }) {
                        continue
                    }
                }
                var next = board
                next[side][s] -= 1
                next[side][t] += 1
                var nextHits = hits
                if t > 0 && board[1 - side][25 - t] == 1 {
                    next[1 - side][25 - t] = 0
                    next[1 - side][25] += 1
                    nextHits.insert(t)
                }
                var rest = remaining
                rest.remove(at: di)
                visit(next, rest, moves + [Move(from: s, to: t)], nextHits, moves.isEmpty ? die : firstDie)
            }
        }
    }
    visit(pos, dice, [], [], 0)
    let maximum = all.map(\.count).max()!
    let larger = maximum == 1 && d1 != d2 && all.contains(where: { $0.count == 1 && $0.firstDie == max(d1, d2) })
    var seen = Set<Position>()
    let legal = all.filter { play in
        play.count == maximum && (!larger || play.firstDie == max(d1, d2)) && seen.insert(play.pos).inserted
    }.sorted { keyLess($0.key, $1.key) }
    return Plays(all: all, legal: legal, maximum: maximum)
}
func pips(_ own: [Int]) -> Int {
    (1...25).reduce(0) { $0 + $1 * own[$1] }
}
func evaluation(_ pos: Position, _ side: Int) -> [Int] {
    let own = pos[side], opponent = pos[1 - side]
    let p = pips(opponent) - pips(own)
    var s = 0, home = 0, prime = 0, anchors = 0, run = 0
    for point in 1...24 {
        if own[point] == 1 {
            var distances = Set<Int>()
            for q in 0..<point where opponent[25 - q] > 0 {
                distances.insert(point - q)
            }
            for a in 1...6 {
                for b in 1...6 {
                    if distances.contains(a) || distances.contains(b) || distances
                        .contains(a + b) || (a == b && (distances.contains(3 * a) || distances.contains(4 * a)))
                    {
                        s += 1
                    }
                }
            }
        }
        if own[point] >= 2 {
            if point <= 6 {
                home += 1
            }
            if point >= 19 {
                anchors += 1
            }
            run += 1
            prime = max(prime, run)
        } else {
            run = 0
        }
    }
    let bar = opponent[25] - own[25]
    return [2 * p - s + 4 * home + 3 * prime + 3 * anchors + 6 * bar, p, s, home, prime, anchors, bar]
}
func keith(_ own: [Int]) -> Int {
    pips(own) + 2 * max(own[1] - 1, 0) + max(own[2] - 1, 0) + max(own[3] - 3, 0)
        + (4...6).filter { own[$0] == 0 }.count
}
func contact(_ pos: Position) -> Bool {
    let w = pos[0][25] > 0 ? 25 : ((1...24).filter { pos[0][$0] > 0 }.max() ?? 0)
    let b = pos[1][25] > 0 ? 0 : 25 - ((1...24).filter { pos[1][$0] > 0 }.max() ?? 0)
    return w > b
}
func cubeDecision(_ state: State, forbidden: Bool = false) -> String {
    let x = state.side
    if state.owner == 1 - x || state.cube == 64 || forbidden {
        return "unavailable"
    }
    if contact(state.pos) {
        let value = evaluation(state.pos, x)[0]
        if value < 60 {
            return "no double"
        }
        return value <= 100 ? "double take" : "double drop"
    }
    let value = 8 * keith(state.pos[x]) - 7 * keith(state.pos[1 - x])
    let limit = state.owner == nil ? 28 : 21
    if value > limit {
        return "no double"
    }
    return value >= 14 ? "double take" : "double drop"
}
func endGame(_ state: inout State, winner: Int, kind suppliedKind: String? = nil) -> Outcome {
    let kind: String
    if let suppliedKind {
        kind = suppliedKind
    } else {
        let opponent = state.pos[1 - winner]
        if opponent[0] > 0 {
            kind = "single"
        } else if opponent[25] > 0 || (19...24).contains(where: { opponent[$0] > 0 }) {
            kind = "backgammon"
        } else {
            kind = "gammon"
        }
    }
    let multiplier = kind == "gammon" ? 2 : (kind == "backgammon" ? 3 : 1)
    let points = state.cube * multiplier
    state.pending = false
    state.over = true
    state.score[winner] += points
    return Outcome(winner: winner, kind: kind, points: points)
}
func applyPlay(_ state: inout State, _ play: Play) -> Outcome? {
    state.pos = play.pos
    if state.pos[state.side][0] == 15 {
        let winner = state.side
        return endGame(&state, winner: winner)
    }
    state.side = 1 - state.side
    return nil
}
func ranked(_ legal: [Play], _ side: Int) -> [(value: Int, index: Int)] {
    legal.enumerated().map { (value: evaluation($0.element.pos, side)[0], index: $0.offset) }
        .sorted { $0.value != $1.value ? $0.value > $1.value : $0.index < $1.index }
}
func parsePoint(_ original: String, first: Bool) throws -> Int {
    if first && original == "bar" {
        return 25
    }
    if !first && original == "off" {
        return 0
    }
    var word = original
    if !first && word.hasSuffix("*") {
        word.removeLast()
    }
    guard !word.isEmpty, word.first != "0", word.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let point = Int(word), (1...24).contains(point)
    else {
        throw EngineError.message("ILLEGAL syntax")
    }
    return point
}
func parsePlay(_ tokens: [String]) throws -> [Move] {
    if tokens == ["none"] {
        return []
    }
    var moves: [Move] = []
    for token in tokens {
        var path = token, repeatCount = 1
        if token.hasSuffix(")") {
            let chars = Array(token)
            try require(chars.count >= 3, "ILLEGAL syntax")
            try require(
                chars[chars.count - 3] == "(" && ["2", "3", "4"].contains(String(chars[chars.count - 2])),
                "ILLEGAL syntax"
            )
            repeatCount = Int(String(chars[chars.count - 2]))!
            path = String(chars.dropLast(3))
        }
        let fields = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        try require(fields.count >= 2, "ILLEGAL syntax")
        var previous = try parsePoint(fields[0], first: true)
        for field in fields.dropFirst() {
            let point = try parsePoint(field, first: false)
            try require(previous > point, "ILLEGAL syntax")
            for _ in 0..<repeatCount {
                moves.append(Move(from: previous, to: point))
            }
            previous = point
        }
    }
    return moves
}
func choosePlay(_ state: State, tokens: [String], plays: Plays) throws -> Play {
    let moves = try parsePlay(tokens)
    let side = state.side
    var final = state.pos
    var destinations = Set<Int>()
    for move in moves {
        final[side][move.from] -= 1
        final[side][move.to] += 1
        if move.to > 0 {
            destinations.insert(move.to)
        }
    }
    for t in destinations where state.pos[1 - side][25 - t] == 1 {
        final[1 - side][25 - t] = 0
        final[1 - side][25] += 1
    }
    try require((1...25).allSatisfy { final[side][$0] >= 0 }, "ILLEGAL no checker")
    try require(final[side][25] == 0 || moves.allSatisfy { $0.from == 25 }, "ILLEGAL bar")
    try require(destinations.allSatisfy { state.pos[1 - side][25 - $0] < 2 }, "ILLEGAL blocked")
    if moves.contains(where: { $0.to == 0 }) {
        try require(final[side][25] == 0 && (7...24).allSatisfy { final[side][$0] == 0 }, "ILLEGAL bear-off")
    }
    if let legal = plays.legal.first(where: { $0.pos == final }) {
        return legal
    }
    let possible = plays.all.filter { $0.pos == final }
    try require(!possible.isEmpty, "ILLEGAL impossible")
    throw EngineError
        .message(possible
            .contains(where: { $0.count < plays.maximum }) ? "ILLEGAL too few dice" : "ILLEGAL larger die required")
}
func resultLine(_ result: Outcome) -> String {
    "result \(color(result.winner)) \(result.kind) \(result.points)"
}
func simulate(_ original: State, rng: RandomStream, strategies: [String], opening: Bool = false,
              target: Int = 0, scores: [Int] = [0, 0], crawford: Bool = false, verbose: Bool = false) -> Simulation
{
    var state = original
    var d1 = 0, d2 = 0
    if opening {
        repeat {
            d1 = rng.die()
            d2 = rng.die()
        } while d1 == d2
        state.side = d1 > d2 ? 0 : 1
    }
    let first = state.side
    var turn = 1, plays = 0
    while true {
        let x = state.side
        if !opening || turn != 1 {
            let forbidden = target > 0 && (crawford || scores[x] + state.cube >= target)
            let decision = cubeDecision(state, forbidden: forbidden)
            if decision.hasPrefix("double") {
                if verbose {
                    print("\(turn) \(color(x)) doubles \(state.cube * 2)")
                }
                if decision == "double drop" {
                    if verbose {
                        print("\(turn) \(color(1 - x)) drops")
                    }
                    return Simulation(outcome: endGame(&state, winner: x, kind: "drop"), turns: plays, first: first)
                }
                if verbose {
                    print("\(turn) \(color(1 - x)) takes")
                }
                state.cube *= 2
                state.owner = 1 - x
            }
            d1 = rng.die()
            d2 = rng.die()
        }
        let legal = enumerate(state.pos, x, d1, d2).legal
        let index: Int
        switch strategies[x] {
        case "FIRST":
            index = 0
        case "RANDOM":
            index = Int(rng.next() % Int64(legal.count))
        default:
            index = ranked(legal, x)[0].index
        }
        let play = legal[index]
        if verbose {
            print("\(turn) \(color(x)) \(d1)-\(d2) \(play.text)")
        }
        let outcome = applyPlay(&state, play)
        plays += 1
        if let outcome {
            return Simulation(outcome: outcome, turns: plays, first: first)
        }
        turn += 1
    }
}
func numeric(_ word: String?, _ low: Int, _ high: Int) -> Bool {
    guard let word, !word.isEmpty, word.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
          let value = Int(word)
    else {
        return false
    }
    return value >= low && value <= high
}
func parsePosition(_ args: [String]) -> Position? {
    guard args.count == 4, numeric(args[1], 0, 15), numeric(args[2], 0, 15),
          ["W", "B"].contains(args[3])
    else {
        return nil
    }
    let points = args[0].split(separator: ",", omittingEmptySubsequences: false)
    guard points.count == 24 else {
        return nil
    }
    var pos = Array(repeating: Array(repeating: 0, count: 26), count: 2)
    for (i, word) in points.enumerated() {
        guard let n = Int(word), (-15...15).contains(n) else {
            return nil
        }
        if n > 0 {
            pos[0][i + 1] = n
        } else {
            pos[1][24 - i] = -n
        }
    }
    pos[0][25] = Int(args[1])!
    pos[1][25] = Int(args[2])!
    for x in 0..<2 {
        pos[x][0] = 15 - pos[x].reduce(0, +)
        if !(0...14).contains(pos[x][0]) {
            return nil
        }
    }
    return pos
}
let noArguments = Set("NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY".split(separator: " ")
    .map(String.init))
let known = noArguments
    .union("POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS".split(separator: " ").map(String.init))
let limited = Set("RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME".split(separator: " ")
    .map(String.init))
let pendingLimited = Set("PLAY AUTO CUBE DOUBLE RESIGN GAME".split(separator: " ").map(String.init))
func argumentsValid(_ command: String, _ a: [String]) -> Bool {
    if noArguments.contains(command) {
        return a.isEmpty
    }
    func at(_ i: Int) -> String? {
        i < a.count ? a[i] : nil
    }
    switch command {
    case "POS":
        return parsePosition(a) != nil
    case "MOVES", "PLAY", "AUTO", "HINT":
        guard numeric(at(0), 1, 6), numeric(at(1), 1, 6) else {
            return false
        }
        if command == "PLAY" {
            return a.count >= 3
        }
        if command == "HINT" {
            return a.count == 3 && numeric(at(2), 1, 1000)
        }
        return a.count == 2
    case "RESIGN":
        return a.count == 1 && ["single", "gammon", "backgammon"].contains(a[0])
    case "UNDO", "REDO":
        return a.count == 1 && numeric(at(0), 1, 1000)
    case "GAME":
        return a.count == 3 && numeric(at(0), 1, 2147483646) && a.dropFirst().allSatisfy { [
            "BEST",
            "FIRST",
            "RANDOM"
        ].contains($0) }
    case "MATCH", "STATS":
        return a.count == 2 && numeric(at(0), 1, command == "MATCH" ? 15 : 50) && numeric(
            at(1),
            1,
            2147483646
        )
    default:
        return false
    }
}
func boardLine(_ pos: Position, top: Bool, row: Int = 0) {
    var line = ""
    for i in 1...12 {
        let p = top ? i + 12 : 13 - i
        let value: String
        if row == 0 {
            value = String(p)
        } else {
            let w = pos[0][p], b = pos[1][25 - p], n = max(w, b)
            value = row == 5 && n > 5 ? String(n) : (n >= row ? (w > 0 ? "W" : "B") : ".")
        }
        line += String(repeating: " ", count: max(0, 3 - value.count)) + value
        if i == 6 {
            line += " |"
        }
    }
    print(line)
}
struct Engine {
    var state = State.initial()
    var history: [Entry] = []
    var redo: [Entry] = []

    mutating func run(_ line: String) throws {
        let words = line.split(separator: " ").map(String.init)
        let command = words[0]
        let a = Array(words.dropFirst())
        try require(known.contains(command), "ERROR unknown command")
        try require(argumentsValid(command, a), command == "POS" ? "ERROR bad position" : "ERROR bad arguments")
        try require(!state.over || !limited.contains(command), "ERROR game over")
        try require(!state.pending || !pendingLimited.contains(command), "ERROR double pending")
        let side = state.side
        switch command {
        case "NEW", "POS":
            state = State.initial(score: state.score)
            if command == "POS" {
                state.pos = parsePosition(a)!
                state.side = a[3] == "W" ? 0 : 1
            }
            history.removeAll()
            redo.removeAll()
            print("OK")
        case "SHOW":
            let points = (1...24).map { String(state.pos[0][$0] - state.pos[1][25 - $0]) }
            print("POS \(points.joined(separator: ",")) \(state.pos[0][25]) \(state.pos[1][25]) \(color(side))")
        case "BOARD":
            boardLine(state.pos, top: true)
            for row in 1...5 {
                boardLine(state.pos, top: true, row: row)
            }
            let owner = state.owner.map(color) ?? "center"
            let status = state.over ? "game over" : color(side) + (state.pending ? " doubles" : " to move")
            print(
                "bar W\(state.pos[0][25]) B\(state.pos[1][25]) | off W\(state.pos[0][0]) B\(state.pos[1][0]) | cube \(state.cube) \(owner) | \(status)"
            )
            for row in stride(from: 5, through: 1, by: -1) {
                boardLine(state.pos, top: false, row: row)
            }
            boardLine(state.pos, top: false)
        case "PIPS":
            print("pips W \(pips(state.pos[0])) B \(pips(state.pos[1]))")
        case "RACE":
            print(contact(state.pos) ? "contact" : "race W \(keith(state.pos[0])) B \(keith(state.pos[1]))")
        case "EVAL":
            let labels = ["eval", "pips", "blots", "home", "prime", "anchors", "bar"]
            print(zip(labels, evaluation(state.pos, side)).map { "\($0.0) \($0.1)" }.joined(separator: " "))
        case "MOVES", "PLAY", "AUTO", "HINT":
            let d1 = Int(a[0])!, d2 = Int(a[1])!
            let plays = enumerate(state.pos, side, d1, d2)
            if command == "MOVES" {
                for play in plays.legal {
                    print(play.text)
                }
                print("total \(plays.legal.count)")
            } else if command == "HINT" {
                for item in ranked(plays.legal, side)
                    .prefix(Int(a[2])!)
                {
                    print("\(item.value) \(plays.legal[item.index].text)")
                }
            } else {
                let play: Play
                if command == "AUTO" {
                    play = plays.legal[ranked(plays.legal, side)[0].index]
                } else {
                    play = try choosePlay(state, tokens: Array(a.dropFirst(2)), plays: plays)
                }
                let value = evaluation(play.pos, side)[0]
                let before = state
                let outcome = applyPlay(&state, play)
                print("OK " + play.text + (command == "AUTO" ? " eval \(value)" : ""))
                if let outcome {
                    print(resultLine(outcome))
                }
                history.append(Entry(record: "\(color(side)) \(d1)-\(d2) \(play.text)", before: before, after: state))
                redo.removeAll()
            }
        case "SHOTS":
            let blots = (1...24).reversed().filter { state.pos[side][$0] == 1 }
            var counts = Array(repeating: 0, count: 25)
            var total = 0
            var rolls: [String] = []
            for d1 in stride(from: 6, through: 1, by: -1) {
                for d2 in stride(from: d1, through: 1, by: -1) {
                    let legal = enumerate(state.pos, 1 - side, d1, d2).legal
                    let hit = blots.filter { p in legal.contains { $0.pos[side][p] == 0 } }
                    if !hit.isEmpty {
                        let weight = d1 == d2 ? 1 : 2
                        total += weight
                        rolls.append("\(d1)-\(d2)")
                        for p in hit {
                            counts[p] += weight
                        }
                    }
                }
            }
            print("shots \(total)/36" + (rolls.isEmpty ? "" : " " + rolls.joined(separator: " ")))
            for p in blots {
                print("blot \(p) \(counts[p])/36")
            }
        case "CUBE":
            print("cube " + cubeDecision(state))
        case "DOUBLE":
            try require(state.owner != 1 - side && state.cube != 64, "ERROR cube unavailable")
            state.pending = true
            redo.removeAll()
            print("OK double \(state.cube * 2)")
        case "TAKE", "DROP":
            try require(state.pending, "ERROR no double")
            state.pending = false
            redo.removeAll()
            if command == "TAKE" {
                state.cube *= 2
                state.owner = 1 - side
                print("OK take \(state.cube) \(color(1 - side))")
            } else {
                print("OK drop")
                print(resultLine(endGame(&state, winner: side, kind: "drop")))
            }
        case "RESIGN":
            redo.removeAll()
            print("OK resign")
            print(resultLine(endGame(&state, winner: 1 - side, kind: a[0])))
        case "SCORE":
            print("score W \(state.score[0]) B \(state.score[1])")
        case "HISTORY":
            print("history \(history.count)")
            for (i, entry) in history.enumerated() {
                print("\(i + 1) \(entry.record)")
            }
        case "UNDO", "REDO":
            let count = Int(a[0])!
            if command == "UNDO" {
                try require(count <= history.count, "ERROR cannot undo")
                let entries = Array(history.suffix(count))
                state = entries[0].before
                history.removeLast(count)
                redo.insert(contentsOf: entries, at: 0)
            } else {
                try require(count <= redo.count, "ERROR cannot redo")
                let entries = Array(redo.prefix(count))
                state = entries[count - 1].after
                redo.removeFirst(count)
                history.append(contentsOf: entries)
            }
            print("OK")
        case "GAME":
            let simulation = simulate(
                state,
                rng: RandomStream(Int64(a[0])!),
                strategies: Array(a.dropFirst()),
                verbose: true
            )
            print(resultLine(simulation.outcome))
        case "MATCH", "STATS":
            let n = Int(a[0])!, rng = RandomStream(Int64(a[1])!)
            var points = [0, 0], turns = 0, game = 0
            var crawfordUsed = false
            let kinds = ["single", "gammon", "backgammon", "drop"]
            var outcomes = Dictionary(uniqueKeysWithValues: kinds.map { ($0, [0, 0]) })
            while command == "STATS" ? game < n : points.max()! < n {
                game += 1
                let crawford = command == "MATCH" && !crawfordUsed && points.max()! == n - 1
                crawfordUsed = crawfordUsed || crawford
                let simulation = simulate(State.initial(), rng: rng, strategies: ["BEST", "BEST"], opening: true,
                                          target: command == "MATCH" ? n : 0, scores: points, crawford: crawford)
                let result = simulation.outcome
                points[result.winner] += result.points
                outcomes[result.kind]![result.winner] += 1
                turns += simulation.turns
                if command == "MATCH" {
                    print(
                        "game \(game)\(crawford ? " crawford" : "") start \(color(simulation.first)) turns \(simulation.turns) \(resultLine(result)) score \(points[0])-\(points[1])"
                    )
                }
            }
            if command == "MATCH" {
                print("match \(color(points[0] >= n ? 0 : 1)) \(points[0])-\(points[1])")
            } else {
                for kind in kinds {
                    print("\(kind) W \(outcomes[kind]![0]) B \(outcomes[kind]![1])")
                }
                print("points W \(points[0]) B \(points[1])")
                print("turns \(turns)")
            }
        default:
            break
        }
    }
}
var engine = Engine()
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    do { try engine.run(readLine()!) }
    catch EngineError.message(let message) { print(message) }
    catch { fatalError("Unexpected error") }
}
