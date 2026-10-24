import Foundation

let shipNames = ["CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"]
let shipLengths = [5, 4, 3, 3, 2]
let symbols = ["C", "B", "R", "S", "D"]
enum Strategy: String { case hunt = "HUNT", prob = "PROB", random = "RANDOM", human = "HUMAN" }
let strategies: [Strategy] = [.hunt, .prob, .random]
enum Phase: String { case setup = "SETUP", battle = "BATTLE", over = "OVER" }
enum View: String { case reef = "~", unattacked = ".", miss = "o", hit = "x", sunk = "#" }
enum OutputMode { case normal, match, quiet }

struct CommandError: Error { let message: String }
func fail(_ message: String) throws -> Never { throw CommandError(message: message) }
func advance(_ state: Int64) -> Int64 { 48271 * state % 2147483647 }
func rowName(_ row: Int) -> String { String(UnicodeScalar(65 + row)!) }
func coordinate(_ cell: Int) -> String { "\(rowName(cell / 10))\(cell % 10 + 1)" }
func parseCell(_ word: String) -> Int { (Int(word.utf8.first!) - 65) * 10 + Int(word.dropFirst())! - 1 }
func shipRange(_ cells: [Int]) -> String { "\(coordinate(cells[0]))-\(coordinate(cells[cells.count - 1]))" }
func switchName(_ value: Bool) -> String { value ? "ON" : "OFF" }
func touching(_ a: Int, _ b: Int) -> Bool { abs(a / 10 - b / 10) <= 1 && abs(a % 10 - b % 10) <= 1 }

func step(_ cell: Int, _ dr: Int, _ dc: Int) -> Int {
    let row = cell / 10 + dr, column = cell % 10 + dc
    return row >= 0 && row < 10 && column >= 0 && column < 10 ? row * 10 + column : -1
}

func footprint(_ start: Int, _ direction: String, _ length: Int) -> [Int]? {
    if (direction == "H" ? start % 10 : start / 10) + length > 10 { return nil }
    return (0..<length).map { start + $0 * (direction == "H" ? 1 : 10) }
}

struct Player {
    var fleet = Array(repeating: [Int](), count: 5)
    var attacked = Array(repeating: false, count: 100)
    var candidates: [Int] = []
    var random: Int64
    var wins: Int
    var controller: Strategy = .human
    var torpedo = false, sonar = false
    var shots = 0, hits = 0, sinks = 0, turns = 0, streak = 0, bestStreak = 0

    init(seed: Int64, wins: Int = 0) { random = seed; self.wins = wins }
    func shipAt(_ cell: Int) -> Int? { fleet.firstIndex { $0.contains(cell) } }
    func sunk(_ ship: Int) -> Bool { !fleet[ship].isEmpty && fleet[ship].allSatisfy { attacked[$0] } }
    var placed: Int { fleet.filter { !$0.isEmpty }.count }
    var afloat: Int { fleet.indices.filter { !fleet[$0].isEmpty && !sunk($0) }.count }
    var defeated: Bool { fleet.indices.allSatisfy { sunk($0) } }
}

struct Choice { let cell: Int; let info: String }
struct Shot { var text = "ALREADY"; var hit = false; var sunk: Int? }

struct Game {
    var phase: Phase = .setup
    var current = 0
    var winner: Int?
    var salvo = false, chain = false, touch = false
    var reefs: Set<Int> = []
    var players: [Player]

    init(wins: [Int] = [0, 0]) { players = [Player(seed: 1, wins: wins[0]), Player(seed: 2, wins: wins[1])] }

    func placementProblem(_ player: Player, _ cells: [Int]?) -> String? {
        guard let cells else { return "out of bounds" }
        if cells.contains(where: { reefs.contains($0) }) { return "on reef" }
        for ship in 0..<5 {
            if cells.contains(where: { player.fleet[ship].contains($0) }) { return "overlaps \(shipNames[ship])" }
        }
        if !touch {
            for ship in 0..<5 {
                if cells.contains(where: { cell in player.fleet[ship].contains { touching(cell, $0) } }) { return "touches \(shipNames[ship])" }
            }
        }
        return nil
    }

    func placementOutput(_ p: Int) -> [String] {
        (0..<5).map { "PLACED \(p + 1) \(shipNames[$0]) \(shipRange(players[p].fleet[$0]))" }
    }

    mutating func autoPlace(_ p: Int, seed: Int64) -> Int64 {
        players[p].random = seed
        players[p].fleet = Array(repeating: [], count: 5)
        var attempts: Int64 = 0
        for ship in 0..<5 {
            while players[p].fleet[ship].isEmpty {
                attempts += 1
                players[p].random = advance(players[p].random)
                let direction = players[p].random % 2 == 0 ? "H" : "V"
                players[p].random = advance(players[p].random)
                let span = 11 - shipLengths[ship]
                let index = Int(players[p].random % Int64(10 * span))
                let start = direction == "H" ? index / span * 10 + index % span : index
                let cells = footprint(start, direction, shipLengths[ship])
                if placementProblem(players[p], cells) == nil { players[p].fleet[ship] = cells! }
            }
        }
        return attempts
    }

    func view(_ p: Int) -> [View] {
        let opponent = players[1 - p]
        return (0..<100).map { cell in
            if reefs.contains(cell) { return .reef }
            if !opponent.attacked[cell] { return .unattacked }
            guard let ship = opponent.shipAt(cell) else { return .miss }
            return opponent.sunk(ship) ? .sunk : .hit
        }
    }

    func excluded(_ view: [View]) -> [Bool] {
        var result = Array(repeating: false, count: 100)
        if touch { return result }
        for cell in 0..<100 where view[cell] == .sunk {
            for dr in -1...1 {
                for dc in -1...1 {
                    if dr == 0 && dc == 0 { continue }
                    let next = step(cell, dr, dc)
                    if next != -1 { result[next] = true }
                }
            }
        }
        return result
    }

    func density(_ p: Int, view: [View], excluded: [Bool]) -> [Int] {
        var scores = Array(repeating: 0, count: 100)
        for ship in 0..<5 where !players[1 - p].sunk(ship) {
            for start in 0..<100 {
                for direction in ["H", "V"] {
                    guard let cells = footprint(start, direction, shipLengths[ship]) else { continue }
                    if cells.contains(where: { excluded[$0] || (view[$0] != .unattacked && view[$0] != .hit) }) { continue }
                    let weight = 1 + 10 * cells.filter { view[$0] == .hit }.count
                    for cell in cells { scores[cell] += weight }
                }
            }
        }
        return scores
    }

    mutating func choose(_ p: Int, strategy: Strategy, mutate: Bool = true) -> Choice {
        let cells = view(p)
        let blocked = excluded(cells)
        func candidate(_ cell: Int) -> Bool { cell >= 0 && cell < 100 && cells[cell] == .unattacked && !blocked[cell] }
        if strategy == .prob {
            let scores = density(p, view: cells, excluded: blocked)
            var chosen: Int?
            for cell in 0..<100 where cells[cell] == .unattacked {
                if chosen == nil || scores[cell] > scores[chosen!] { chosen = cell }
            }
            return Choice(cell: chosen!, info: String(scores[chosen!]))
        }
        if strategy == .random {
            let choices = (0..<100).filter { candidate($0) }
            let random = advance(players[p].random)
            if mutate { players[p].random = random }
            return Choice(cell: choices[Int(random % Int64(choices.count))], info: String(choices.count))
        }
        for cell in 0..<100 where cells[cell] == .hit {
            for (dr, dc) in [(0, 1), (1, 0)] {
                let neighbor = step(cell, dr, dc)
                if neighbor == -1 || cells[neighbor] != .hit { continue }
                var front = neighbor
                while front != -1 && cells[front] == .hit { front = step(front, dr, dc) }
                let back = step(cell, -dr, -dc)
                if candidate(front) { return Choice(cell: front, info: "LINE") }
                if candidate(back) { return Choice(cell: back, info: "LINE") }
            }
        }
        for cell in players[p].candidates.reversed() where candidate(cell) { return Choice(cell: cell, info: "STACK") }
        let shortest = (0..<5).filter { !players[1 - p].sunk($0) }.map { shipLengths[$0] }.min()!
        for cell in 0..<100 where candidate(cell) && (cell / 10 + cell % 10) % shortest == 0 { return Choice(cell: cell, info: "PARITY") }
        preconditionFailure("No strategy candidate")
    }

    mutating func shoot(_ p: Int, cell: Int) -> Shot {
        let opponent = 1 - p
        var result = Shot()
        if !players[opponent].attacked[cell] {
            players[opponent].attacked[cell] = true
            if let ship = players[opponent].shipAt(cell) {
                result.hit = true
                if players[opponent].sunk(ship) {
                    result.text = "SUNK \(shipNames[ship])"
                    result.sunk = ship
                } else {
                    result.text = "HIT"
                    for (dr, dc) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                        let next = step(cell, dr, dc)
                        if next != -1 { players[p].candidates.append(next) }
                    }
                }
            } else { result.text = "MISS" }
        }
        players[p].shots += 1
        if result.hit {
            players[p].hits += 1
            players[p].streak += 1
            players[p].bestStreak = max(players[p].bestStreak, players[p].streak)
        } else { players[p].streak = 0 }
        if result.sunk != nil { players[p].sinks += 1 }
        return result
    }

    func allowance(_ p: Int) -> Int { salvo ? players[p].afloat : 1 }

    mutating func finishTurn(_ p: Int, hit: Bool, output: inout [String], mode: OutputMode) {
        players[p].turns += 1
        if players[1 - p].defeated {
            phase = .over
            winner = p
            players[p].wins += 1
            if mode == .normal { output.append("WINNER \(p + 1)") }
        } else { current = chain && hit ? p : 1 - p }
    }

    mutating func shootingTurn(_ p: Int, strategy: Strategy?, cells: [Int], output: inout [String], mode: OutputMode = .normal) {
        phase = .battle
        let count = allowance(p)
        var hit = false
        for index in 0..<count {
            let cell: Int
            if let strategy { cell = choose(p, strategy: strategy).cell }
            else { cell = cells[index] }
            let result = shoot(p, cell: cell)
            hit = hit || result.hit
            if mode == .normal { output.append("SHOT \(p + 1) \(coordinate(cell)) \(result.text)") }
            if mode == .match, let ship = result.sunk { output.append("SINK \(p + 1) \(shipNames[ship]) \(players[p].shots)") }
            if players[1 - p].defeated { break }
        }
        finishTurn(p, hit: hit, output: &output, mode: mode)
    }

    func checkTurn(_ p: Int) throws {
        if phase == .over { try fail("game over") }
        if phase == .setup && players.contains(where: { $0.placed != 5 }) { try fail("fleets not ready") }
        if p != current { try fail("not your turn") }
    }

    mutating func specialTurn(_ p: Int, command: String, args: [String], output: inout [String]) {
        phase = .battle
        let opponent = 1 - p
        var hit = false
        if command == "SONAR" {
            players[p].sonar = true
            let center = parseCell(args[0])
            var count = 0
            for dr in -1...1 {
                for dc in -1...1 {
                    let cell = step(center, dr, dc)
                    if cell != -1 && !players[opponent].attacked[cell] && players[opponent].shipAt(cell) != nil { count += 1 }
                }
            }
            output.append("SONAR \(p + 1) \(args[0]) \(count)")
        } else {
            players[p].torpedo = true
            let row = Int(args[0].utf8.first!) - 65
            var result = "MISS"
            var shotAtShip = false
            for index in 0..<10 {
                let cell = row * 10 + (args[1] == "W" ? index : 9 - index)
                if reefs.contains(cell) {
                    result = "REEF \(coordinate(cell))"
                    break
                }
                if players[opponent].shipAt(cell) != nil {
                    let shot = shoot(p, cell: cell)
                    result = "\(shot.text) \(coordinate(cell))"
                    hit = shot.hit
                    shotAtShip = true
                    break
                }
                players[opponent].attacked[cell] = true
            }
            if !shotAtShip { players[p].shots += 1; players[p].streak = 0 }
            output.append("TORPEDO \(p + 1) \(args[0]) \(args[1]) \(result)")
        }
        finishTurn(p, hit: hit, output: &output, mode: .normal)
    }

    mutating func automatic(output: inout [String]) {
        while phase == .battle && players[current].controller != .human {
            let p = current
            let strategy = players[p].controller
            shootingTurn(p, strategy: strategy, cells: [], output: &output)
        }
    }

    func match(seed1: Int64, seed2: Int64, first: Strategy, second: Strategy, output: inout [String], mode: OutputMode = .quiet) -> Game {
        var game = Game()
        game.salvo = salvo; game.chain = chain; game.touch = touch; game.reefs = reefs
        _ = game.autoPlace(0, seed: seed1)
        _ = game.autoPlace(1, seed: seed2)
        game.phase = .battle
        let choices = [first, second]
        while game.phase != .over {
            let p = game.current
            game.shootingTurn(p, strategy: choices[p], cells: [], output: &output, mode: mode)
        }
        return game
    }

    mutating func layout(_ p: Int, text: String) throws -> [String] {
        let grid = text.filter { $0 != "/" }.map(String.init)
        let fleet = symbols.map { symbol in (0..<100).filter { grid[$0] == symbol } }
        for ship in 0..<5 {
            let cells = fleet[ship]
            if cells.count != shipLengths[ship] { try fail("\(shipNames[ship]) has \(cells.count) cells") }
            let horizontal = cells.indices.allSatisfy { cells[$0] == cells[0] + $0 && cells[$0] / 10 == cells[0] / 10 }
            let vertical = cells.indices.allSatisfy { cells[$0] == cells[0] + 10 * $0 }
            if !horizontal && !vertical { try fail("\(shipNames[ship]) not straight") }
            if cells.contains(where: { reefs.contains($0) }) { try fail("\(shipNames[ship]) on reef") }
        }
        if !touch {
            for first in 0..<5 {
                for second in (first + 1)..<5 {
                    if fleet[first].contains(where: { cell in fleet[second].contains { touching(cell, $0) } }) {
                        try fail("\(shipNames[first]) touches \(shipNames[second])")
                    }
                }
            }
        }
        players[p].fleet = fleet
        return ["LAYOUT \(p + 1)"] + placementOutput(p)
    }

    func boardOutput(_ p: Int, radar: Bool) -> [String] {
        let player = players[p]
        let cells: [String]
        if radar { cells = view(p).map(\.rawValue) }
        else {
            cells = (0..<100).map { cell in
                if reefs.contains(cell) { return "~" }
                if let ship = player.shipAt(cell) { return player.attacked[cell] ? symbols[ship].lowercased() : symbols[ship] }
                return player.attacked[cell] ? "o" : "."
            }
        }
        var output = ["\(radar ? "RADAR" : "BOARD") \(p + 1)", "  1 2 3 4 5 6 7 8 9 10"]
        for row in 0..<10 { output.append(rowName(row) + " " + cells[(row * 10)..<(row * 10 + 10)].joined(separator: " ")) }
        return output
    }

    func densityOutput(_ p: Int) -> [String] {
        let cells = view(p)
        let scores = density(p, view: cells, excluded: excluded(cells))
        func padded(_ text: String) -> String { String(repeating: " ", count: max(0, 5 - text.count)) + text }
        var output = ["DENSITY \(p + 1)", " " + (1...10).map { padded(String($0)) }.joined()]
        var best: Int?
        for row in 0..<10 {
            var text = rowName(row)
            for column in 0..<10 {
                let cell = row * 10 + column
                let value = cells[cell] == .unattacked ? String(scores[cell]) : cells[cell] == .reef ? "~" : "-"
                text += padded(value)
                if cells[cell] == .unattacked && (best == nil || scores[cell] > scores[best!]) { best = cell }
            }
            output.append(text)
        }
        output.append("BEST \(coordinate(best!)) \(scores[best!])")
        return output
    }

    func exportFleet(_ p: Int) -> String {
        var grid = Array(repeating: ".", count: 100)
        for ship in 0..<5 { for cell in players[p].fleet[ship] { grid[cell] = symbols[ship] } }
        return (0..<10).map { grid[($0 * 10)..<($0 * 10 + 10)].joined() }.joined(separator: "/")
    }

    func fleetOutput(_ p: Int) -> [String] {
        let player = players[p]
        var output = ["FLEET \(p + 1) afloat \(player.afloat)"]
        for ship in 0..<5 {
            let cells = player.fleet[ship]
            if cells.isEmpty { output.append("\(shipNames[ship]) unplaced") }
            else {
                let attacked = cells.filter { player.attacked[$0] }.count
                let state = player.sunk(ship) ? "SUNK" : "AFLOAT"
                output.append("\(shipNames[ship]) \(shipRange(cells)) \(attacked)/\(shipLengths[ship]) \(state)")
            }
        }
        return output
    }

    func status() -> String {
        let prefix = "STATUS \(phase.rawValue) salvo \(switchName(salvo)) chain \(switchName(chain)) touch \(switchName(touch)) reefs \(reefs.count)"
        if phase == .setup { return "\(prefix) placed \(players[0].placed) \(players[1].placed)" }
        let turn = phase == .battle ? "turn \(current + 1) shots \(allowance(current))" : "winner \(winner! + 1)"
        return "\(prefix) \(turn) afloat \(players[0].afloat) \(players[1].afloat)"
    }

    func statistics() -> [String] {
        players.enumerated().map { p, player in
            let accuracy = player.shots == 0 ? "-" : "\(player.hits * 100 / player.shots)%"
            return "STATS \(p + 1) shots \(player.shots) hits \(player.hits) sunk \(player.sinks) turns \(player.turns) streak \(player.bestStreak) accuracy \(accuracy) wins \(player.wins)"
        }
    }
}

let setupCommands: Set<String> = ["PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH"]
let turnCommands: Set<String> = ["FIRE", "AI", "TORPEDO", "SONAR"]

struct Program {
    var game = Game()

    mutating func execute(_ words: [String]) throws -> [String] {
        let command = words[0]
        if command == "NEW" {
            game = Game(wins: game.players.map(\.wins))
            return ["NEW"]
        }
        if setupCommands.contains(command) {
            if game.phase != .setup { try fail("setup closed") }
            if ["SALVO", "CHAIN", "TOUCH"].contains(command) {
                let enabled = words[1] == "ON"
                if command == "SALVO" { game.salvo = enabled }
                else if command == "CHAIN" { game.chain = enabled }
                else { game.touch = enabled }
                return ["\(command) \(words[1])"]
            }
            if command == "REEF" {
                let cell = parseCell(words[1])
                if game.reefs.contains(cell) { try fail("reef exists at \(coordinate(cell))") }
                for owner in 0..<2 {
                    if let ship = game.players[owner].shipAt(cell) { try fail("\(coordinate(cell)) occupied by \(owner + 1) \(shipNames[ship])") }
                }
                game.reefs.insert(cell)
                return ["REEF \(coordinate(cell))"]
            }
            let p = Int(words[1])! - 1
            if command == "PLACE" || command == "REMOVE" {
                let ship = shipNames.firstIndex(of: words[2])!
                if command == "REMOVE" {
                    if game.players[p].fleet[ship].isEmpty { try fail("\(shipNames[ship]) not placed") }
                    game.players[p].fleet[ship] = []
                    return ["REMOVED \(p + 1) \(shipNames[ship])"]
                }
                if !game.players[p].fleet[ship].isEmpty { try fail("\(shipNames[ship]) already placed") }
                let cells = footprint(parseCell(words[3]), words[4], shipLengths[ship])
                if let problem = game.placementProblem(game.players[p], cells) { try fail(problem) }
                game.players[p].fleet[ship] = cells!
                return ["PLACED \(p + 1) \(shipNames[ship]) \(shipRange(cells!))"]
            }
            if command == "AUTOPLACE" {
                let attempts = game.autoPlace(p, seed: Int64(words[2])!)
                return ["AUTOPLACE \(p + 1) attempts \(attempts)"] + game.placementOutput(p)
            }
            return try game.layout(p, text: words[2])
        }
        if turnCommands.contains(command) {
            let p = Int(words[1])! - 1
            try game.checkTurn(p)
            var output: [String] = []
            if command == "FIRE" {
                let allowance = game.allowance(p)
                if words.count - 2 != allowance { try fail("expected \(allowance) shots") }
                let cells = words.dropFirst(2).map(parseCell)
                for cell in cells where game.reefs.contains(cell) { try fail("reef at \(coordinate(cell))") }
                game.shootingTurn(p, strategy: nil, cells: cells, output: &output)
            } else if command == "AI" { game.shootingTurn(p, strategy: Strategy(rawValue: words[2])!, cells: [], output: &output) }
            else {
                if command == "TORPEDO" && game.players[p].torpedo { try fail("torpedo used") }
                if command == "SONAR" && game.players[p].sonar { try fail("sonar used") }
                game.specialTurn(p, command: command, args: Array(words.dropFirst(2)), output: &output)
            }
            game.automatic(output: &output)
            return output
        }
        if command == "STATUS" { return [game.status()] }
        if command == "STATS" { return game.statistics() }
        if ["MATCH", "SERIES", "TOURNEY"].contains(command) { return simulation(words) }
        let p = Int(words[1])! - 1
        switch command {
        case "RESIGN":
            if game.phase != .battle { try fail("not in battle") }
            game.phase = .over
            game.winner = 1 - p
            game.players[1 - p].wins += 1
            return ["RESIGN \(p + 1)", "WINNER \(2 - p)"]
        case "CONTROL":
            game.players[p].controller = Strategy(rawValue: words[2])!
            return ["CONTROL \(p + 1) \(words[2])"]
        case "SEED":
            game.players[p].random = Int64(words[2])!
            return ["SEED \(p + 1) \(game.players[p].random)"]
        case "HINT":
            if game.phase == .over { try fail("game over") }
            let choice = game.choose(p, strategy: Strategy(rawValue: words[2])!, mutate: false)
            return ["HINT \(p + 1) \(words[2]) \(coordinate(choice.cell)) \(choice.info)"]
        case "DENSITY":
            if game.phase == .over { try fail("game over") }
            return game.densityOutput(p)
        case "SHOW", "RADAR": return game.boardOutput(p, radar: command == "RADAR")
        case "EXPORT": return ["EXPORT \(p + 1) \(game.exportFleet(p))"]
        case "FLEET": return game.fleetOutput(p)
        default: preconditionFailure("Unknown command")
        }
    }

    func simulation(_ words: [String]) -> [String] {
        let command = words[0]
        if command == "MATCH" {
            var output = ["MATCH 1 \(words[3]) 2 \(words[4])"]
            let match = game.match(seed1: Int64(words[1])!, seed2: Int64(words[2])!,
                                   first: Strategy(rawValue: words[3])!, second: Strategy(rawValue: words[4])!, output: &output, mode: .match)
            output.append("RESULT winner \(match.winner! + 1) shots \(match.players[0].shots) \(match.players[1].shots) hits \(match.players[0].hits) \(match.players[1].hits)")
            return output
        }
        let count = Int(words[1])!
        var random = Int64(words[2])!
        var discarded: [String] = []
        if command == "SERIES" {
            var wins = [0, 0], shots = [0, 0]
            var fastest: [Int?] = [nil, nil]
            for _ in 0..<count {
                random = advance(random)
                let seed1 = random
                random = advance(random)
                let match = game.match(seed1: seed1, seed2: random, first: Strategy(rawValue: words[3])!,
                                       second: Strategy(rawValue: words[4])!, output: &discarded)
                let winner = match.winner!
                wins[winner] += 1
                for seat in 0..<2 { shots[seat] += match.players[seat].shots }
                let wonShots = match.players[winner].shots
                fastest[winner] = min(fastest[winner] ?? wonShots, wonShots)
            }
            let first = fastest[0].map { String($0) } ?? "-"
            let second = fastest[1].map { String($0) } ?? "-"
            return ["SERIES \(count) wins \(wins[0]) \(wins[1]) shots \(shots[0]) \(shots[1]) fastest \(first) \(second)"]
        }
        struct Total { let strategy: Int; var wins = 0; var shots = 0 }
        var totals = (0..<3).map { Total(strategy: $0) }
        for first in 0..<3 {
            for second in 0..<3 where first != second {
                for _ in 0..<count {
                    random = advance(random)
                    let seed1 = random
                    random = advance(random)
                    let match = game.match(seed1: seed1, seed2: random, first: strategies[first], second: strategies[second], output: &discarded)
                    totals[match.winner == 0 ? first : second].wins += 1
                    totals[first].shots += match.players[0].shots
                    totals[second].shots += match.players[1].shots
                }
            }
        }
        totals.sort {
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.shots != $1.shots { return $0.shots < $1.shots }
            return $0.strategy < $1.strategy
        }
        return ["TOURNEY \(count)"] + totals.enumerated().map { rank, total in
            "\(rank + 1) \(strategies[total.strategy].rawValue) wins \(total.wins) shots \(total.shots)"
        }
    }
}

let commandCount = Int(readLine()!)!
var program = Program()
for _ in 0..<commandCount {
    let words = readLine()!.split(separator: " ").map(String.init)
    do {
        print(try program.execute(words).joined(separator: "\n"))
    } catch let error as CommandError {
        print("ERROR \(error.message)")
    } catch {
        fatalError(String(describing: error))
    }
}
