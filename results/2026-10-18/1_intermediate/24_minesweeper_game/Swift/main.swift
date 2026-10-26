import Foundation

struct CommandError: Error {
    let message: String
}

func fail(_ message: String) throws -> Never {
    throw CommandError(message: message)
}

enum GameState: String { case ready, playing, won, lost }
enum Mark: String { case none, flag, question }
enum MoveKind: String {
    case reveal, flag, unflag, question, chord, guess
    case autoReveal = "auto-reveal", autoFlag = "auto-flag"
}

struct Move { let kind: MoveKind
    let cell: Int
}
struct Snapshot {
    let command: String
    let visible: [Bool]
    let marks: [Mark]
    let moveCount: Int
}
struct Constraint { let source: Int
    let cells: [Int]
    let remaining: Int
}
struct Component { var cells: [Int] = []
    var constraints: [Constraint] = []
}
struct Deduction { var safe: [Int: String] = [:]
    var mines: [Int: String] = [:]
}
struct Totals { var rounds = 0
    var flagged = 0
    var opened = 0
    var guesses = 0
}
struct Configurations {
    var count = 0
    var minimum: Int
    var maximum = 0
    var frequencies: [Int]
}

struct ConfigurationSearch {
    let incidence: [[Int]]
    let targets: [Int]
    let order: [Int]
    var assigned: [Int]
    var unassigned: [Int]
    var values: [Int]
    var result: Configurations

    mutating func search(depth: Int, mines: Int) {
        if depth == order.count {
            result.count += 1
            result.minimum = min(result.minimum, mines)
            result.maximum = max(result.maximum, mines)
            for index in values.indices {
                result.frequencies[index] += values[index]
            }
            return
        }
        let cell = order[depth]
        let affected = incidence[cell]
        for value in 0...1 {
            values[cell] = value
            var possible = true
            for index in affected {
                assigned[index] += value
                unassigned[index] -= 1
                if assigned[index] > targets[index] || assigned[index] + unassigned[index] <
                    targets[index]
                {
                    possible = false
                }
            }
            if possible {
                search(depth: depth + 1, mines: mines + value)
            }
            for index in affected {
                assigned[index] -= value
                unassigned[index] += 1
            }
        }
        values[cell] = 0
    }
}

func countConfigurations(_ component: Component) -> Configurations {
    let size = component.cells.count
    let empty = Configurations(minimum: size, frequencies: Array(repeating: 0, count: size))
    if component.constraints.contains(where: { $0.remaining < 0 || $0.remaining > $0.cells.count }) {
        return empty
    }
    let positions = Dictionary(uniqueKeysWithValues: component.cells.enumerated().map { ($0.element, $0.offset) })
    var incidence = Array(repeating: [Int](), count: size)
    for (index, constraint) in component.constraints.enumerated() {
        for cell in constraint.cells {
            incidence[positions[cell]!].append(index)
        }
    }
    let order = Array(0..<size).sorted {
        incidence[$0].count == incidence[$1].count ? $0 < $1 : incidence[$0].count > incidence[$1].count
    }
    var search = ConfigurationSearch(
        incidence: incidence, targets: component.constraints.map(\.remaining), order: order,
        assigned: Array(repeating: 0, count: component.constraints.count),
        unassigned: component.constraints.map { $0.cells.count }, values: Array(repeating: 0, count: size),
        result: empty
    )
    search.search(depth: 0, mines: 0)
    return search.result
}

struct Board {
    let width: Int
    let height: Int
    let mineCount: Int
    let seed: Int64
    let neighbors: [[Int]]
    var mines: [Bool]?
    var numbers: [Int]
    var visible: [Bool]
    var marks: [Mark]
    var moves: [Move] = []
    var undo: [Snapshot] = []
    var state: GameState = .ready
    var exploded = -1

    init(width: Int, height: Int, mines: Int, seed: Int64) {
        self.width = width
        self.height = height
        mineCount = mines
        self.seed = seed
        let size = width * height
        numbers = Array(repeating: 0, count: size)
        visible = Array(repeating: false, count: size)
        marks = Array(repeating: .none, count: size)
        neighbors = (0..<size).map { cell in
            let x = cell % width, y = cell / width
            var result: [Int] = []
            for dy in -1...1 {
                for dx in -1...1 {
                    if (dx == 0 && dy == 0) || x + dx < 0 || x + dx >= width || y + dy < 0 || y + dy >=
                        height
                    {
                        continue
                    }
                    result.append((y + dy) * width + x + dx)
                }
            }
            return result
        }
    }

    var size: Int {
        width * height
    }
    var safeCount: Int {
        size - mineCount
    }
    var revealedCount: Int {
        visible.filter { $0 }.count
    }
    var remaining: Int {
        mineCount - marks.filter { $0 == .flag }.count
    }
    var finished: Bool {
        state == .won || state == .lost
    }

    func coordinate(_ cell: Int) -> String {
        "\(cell % width),\(cell / width)"
    }
    func unknown(_ cell: Int) -> Bool {
        !visible[cell] && marks[cell] != .flag
    }

    mutating func restart() {
        visible = Array(repeating: false, count: size)
        marks = Array(repeating: .none, count: size)
        moves = []
        undo = []
        exploded = -1
        state = mines == nil ? .ready : .playing
    }

    mutating func determine(_ placement: [Bool]) {
        mines = placement
        numbers = neighbors.map { $0.filter { placement[$0] }.count }
        state = .playing
    }

    mutating func place(first: Int, safety: String) {
        let x = first % width, y = first / width
        var candidates = (0..<size).filter { cell in
            safety == "none" || (safety == "cell" && cell != first) ||
                (safety == "block" && (abs(cell % width - x) >= 2 || abs(cell / width - y) >= 2))
        }
        var placement = Array(repeating: false, count: size)
        var random = seed
        for _ in 0..<mineCount {
            random = 48271 * random % 2147483647
            let index = Int(random % Int64(candidates.count))
            placement[candidates.remove(at: index)] = true
        }
        determine(placement)
    }

    mutating func reveal(_ cell: Int, safety: String) -> Int {
        if mines == nil {
            place(first: cell, safety: safety)
        }
        if mines![cell] {
            state = .lost
            exploded = cell
            return 0
        }
        var queue = [cell]
        visible[cell] = true
        marks[cell] = .none
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            if numbers[current] != 0 {
                continue
            }
            for next in neighbors[current] where unknown(next) {
                visible[next] = true
                marks[next] = .none
                queue.append(next)
            }
        }
        return queue.count
    }

    mutating func chord(_ cell: Int, safety: String) -> Int {
        var opened = 0
        for next in neighbors[cell] {
            if unknown(next) {
                opened += reveal(next, safety: safety)
            }
            if state == .lost {
                break
            }
        }
        return opened
    }

    mutating func checkWin() {
        if state != .playing || revealedCount != safeCount {
            return
        }
        state = .won
        for cell in 0..<size where mines![cell] {
            marks[cell] = .flag
        }
    }

    func display() -> [String] {
        var rows: [String] = []
        for y in 0..<height {
            var row = ""
            for x in 0..<width {
                let cell = y * width + x
                var symbol = marks[cell] == .flag ? "F" : marks[cell] == .question ? "?" : "#"
                if visible[cell] {
                    symbol = numbers[cell] == 0 ? "." : String(numbers[cell])
                }
                if state == .lost {
                    if mines![cell] {
                        symbol = cell == exploded ? "!" : marks[cell] == .flag ? "F" : "*"
                    } else if marks[cell] == .flag {
                        symbol = "X"
                    }
                }
                row += symbol
            }
            rows.append(row)
        }
        return rows
    }

    func finishOutput() -> [String] {
        if state == .lost {
            return ["boom \(coordinate(exploded))"] + display()
        }
        if state == .won {
            return ["win moves \(moves.count)"]
        }
        return []
    }

    func constraints() -> [Constraint] {
        var result: [Constraint] = []
        for cell in 0..<size where visible[cell] && numbers[cell] != 0 {
            let cells = neighbors[cell].filter { unknown($0) }
            if cells.isEmpty {
                continue
            }
            let flags = neighbors[cell].filter { marks[$0] == .flag }.count
            result.append(Constraint(source: cell, cells: cells, remaining: numbers[cell] - flags))
        }
        return result
    }

    func deduce() -> Deduction {
        let rules = constraints()
        var result = Deduction()
        for clue in rules where clue.remaining == 0 {
            for cell in clue.cells
                where result.safe[cell] == nil
            {
                result.safe[cell] = "single \(coordinate(clue.source))"
            }
        }
        if !result.safe.isEmpty {
            return result
        }
        for clue in rules where clue.remaining == clue.cells.count {
            for cell in clue.cells
                where result.mines[cell] == nil
            {
                result.mines[cell] = "single \(coordinate(clue.source))"
            }
        }
        if !result.mines.isEmpty {
            return result
        }
        for a in rules {
            for b in rules {
                if a.cells.count >= b.cells.count || !a.cells.allSatisfy({ b.cells.contains($0) }) {
                    continue
                }
                let difference = b.cells.filter { !a.cells.contains($0) }
                let remaining = b.remaining - a.remaining
                let reason = "subset \(coordinate(a.source)) \(coordinate(b.source))"
                for cell in difference {
                    if remaining == 0 && result.safe[cell] == nil {
                        result.safe[cell] = reason
                    }
                    if remaining == difference.count && result.mines[cell] == nil {
                        result.mines[cell] = reason
                    }
                }
            }
        }
        if result.safe.isEmpty && result.mines.isEmpty && state == .playing && remaining == 0 {
            for cell in 0..<size where unknown(cell) {
                result.safe[cell] = "count"
            }
        }
        return result
    }

    func frontier() -> [Component] {
        let rules = constraints()
        var parent = Array(0..<size)
        var present = Array(repeating: false, count: size)
        func root(_ original: Int) -> Int {
            var cell = original
            while parent[cell] != cell {
                parent[cell] = parent[parent[cell]]
                cell = parent[cell]
            }
            return cell
        }
        for clue in rules {
            for cell in clue.cells {
                present[cell] = true
                let first = root(clue.cells[0])
                let second = root(cell)
                parent[second] = first
            }
        }
        var groups: [Int: Int] = [:]
        var result: [Component] = []
        for cell in 0..<size where present[cell] {
            let representative = root(cell)
            if groups[representative] == nil {
                groups[representative] = result.count
                result.append(Component())
            }
            result[groups[representative]!].cells.append(cell)
        }
        for clue in rules {
            result[groups[root(clue.cells[0])]!].constraints.append(clue)
        }
        return result
    }

    mutating func automatic(safety: String) -> Totals {
        var totals = Totals()
        while state == .playing {
            let deduction = deduce()
            if deduction.safe.isEmpty && deduction.mines.isEmpty {
                break
            }
            totals.rounds += 1
            for cell in deduction.safe.keys.sorted() where !visible[cell] {
                moves.append(Move(kind: .autoReveal, cell: cell))
                totals.opened += reveal(cell, safety: safety)
                checkWin()
                if finished {
                    return totals
                }
            }
            for cell in deduction.mines.keys.sorted() where unknown(cell) {
                marks[cell] = .flag
                totals.flagged += 1
                moves.append(Move(kind: .autoFlag, cell: cell))
            }
        }
        return totals
    }

    mutating func solve(safety: String) -> Totals {
        var totals = Totals()
        while !finished {
            let step = automatic(safety: safety)
            totals.rounds += step.rounds
            totals.flagged += step.flagged
            totals.opened += step.opened
            if finished {
                break
            }
            var onFrontier = Array(repeating: false, count: size)
            var numerators = Array(repeating: 0, count: size)
            var denominators = Array(repeating: 0, count: size)
            for component in frontier() {
                let configurations = countConfigurations(component)
                for (index, cell) in component.cells.enumerated() {
                    onFrontier[cell] = true
                    numerators[cell] = configurations.frequencies[index]
                    denominators[cell] = configurations.count
                }
            }
            let unknownCount = (0..<size).filter { unknown($0) }.count
            let unconstrainedNumerator = max(remaining, 0)
            var chosen: Int?
            var bestNumerator = 0, bestDenominator = 1
            for cell in 0..<size where unknown(cell) {
                let numerator = onFrontier[cell] ? numerators[cell] : unconstrainedNumerator
                let denominator = onFrontier[cell] ? denominators[cell] : unknownCount
                if denominator == 0 {
                    continue
                }
                if chosen == nil || numerator * bestDenominator < bestNumerator * denominator {
                    chosen = cell
                    bestNumerator = numerator
                    bestDenominator = denominator
                }
            }
            guard let cell = chosen else {
                break
            }
            totals.guesses += 1
            moves.append(Move(kind: .guess, cell: cell))
            totals.opened += reveal(cell, safety: safety)
            checkWin()
        }
        return totals
    }

    func replay(_ count: Int, safety: String) -> [String] {
        var copy = self
        copy.restart()
        for move in moves.prefix(count) {
            switch move.kind {
            case .reveal, .autoReveal, .guess:
                _ = copy.reveal(move.cell, safety: safety)
            case .chord:
                _ = copy.chord(move.cell, safety: safety)
            case .flag, .autoFlag:
                copy.marks[move.cell] = .flag
            case .unflag:
                copy.marks[move.cell] = .none
            case .question:
                copy.marks[move.cell] = copy.marks[move.cell] == .question ? .none : .question
            }
            copy.checkWin()
        }
        return copy.display()
    }

    func boardInfo() -> String {
        let placement = mines!
        var visited = Array(repeating: false, count: size)
        var openings = 0, largest = 0, isolated = 0
        for cell in 0..<size where !placement[cell] {
            if numbers[cell] != 0 {
                if !neighbors[cell].contains(where: { !placement[$0] && numbers[$0] == 0 }) {
                    isolated += 1
                }
                continue
            }
            if visited[cell] {
                continue
            }
            openings += 1
            var queue = [cell]
            var area: Set<Int> = [cell]
            var head = 0
            visited[cell] = true
            while head < queue.count {
                let current = queue[head]
                head += 1
                for next in neighbors[current] {
                    area.insert(next)
                    if !placement[next] && numbers[next] == 0 && !visited[next] {
                        visited[next] = true
                        queue.append(next)
                    }
                }
            }
            largest = max(largest, area.count)
        }
        return "3bv \(openings + isolated) openings \(openings) largest \(largest) mines \(mineCount) safe \(safeCount)"
    }
}

enum Command: String, Hashable {
    case new = "NEW", preset = "PRESET", layout = "LAYOUT", safety = "SAFETY", restart = "RESTART"
    case reveal = "REVEAL", flag = "FLAG", unflag = "UNFLAG", question = "QUESTION", chord = "CHORD"
    case undo = "UNDO", show = "SHOW", status = "STATUS", cell = "CELL", history = "HISTORY", replay = "REPLAY"
    case hint = "HINT", auto = "AUTO", analyze = "ANALYZE", prob = "PROB", frontier = "FRONTIER"
    case solve = "SOLVE", boardInfo = "BOARDINFO", stats = "STATS"
}

let formats: [Command: String] = [
    .new: "nnnn", .preset: "pn", .safety: "s", .restart: "", .reveal: "nn", .flag: "nn",
    .unflag: "nn", .question: "nn", .chord: "nn", .undo: "", .show: "", .status: "", .cell: "nn",
    .history: "n", .replay: "n", .hint: "", .auto: "", .analyze: "", .prob: "nn", .frontier: "",
    .solve: "", .boardInfo: "", .stats: ""
]
let presets: [String: (width: Int, height: Int, mines: Int)] = [
    "beginner": (9, 9, 10), "intermediate": (16, 16, 40), "expert": (30, 16, 99)
]
let cellCommands: Set<Command> = [.reveal, .flag, .unflag, .question, .chord, .cell, .prob]
let liveCommands: Set<Command> = [
    .reveal,
    .flag,
    .unflag,
    .question,
    .chord,
    .undo,
    .hint,
    .auto,
    .analyze,
    .prob,
    .frontier,
    .solve
]
let undoCommands: Set<Command> = [.reveal, .flag, .unflag, .question, .chord, .auto, .solve]

func numberWord(_ text: String) throws -> Int64 {
    let bytes = Array(text.utf8)
    if bytes.isEmpty || bytes.count > 10 || (bytes.count > 1 && bytes[0] == 48) || !bytes
        .allSatisfy({ 48...57 ~= $0 })
    {
        try fail("bad arguments")
    }
    return Int64(text)!
}

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    var a = numerator, b = denominator
    while b != 0 {
        (a, b) = (b, a % b)
    }
    return "\(numerator / a)/\(denominator / a)"
}

struct Statistics {
    var played = 0, won = 0, lost = 0, streak = 0, best = 0
    var fastest: Int?

    mutating func finish(_ board: Board) {
        played += 1
        if board.state == .won {
            won += 1
            streak += 1
            best = max(best, streak)
            fastest = min(fastest ?? board.moves.count, board.moves.count)
        } else {
            lost += 1
            streak = 0
        }
    }

    func display() -> String {
        let rate = played == 0 ? "-" : "\(won * 100 / played)%"
        let minimum = fastest.map { String($0) } ?? "-"
        return "stats played \(played) won \(won) lost \(lost) rate \(rate) streak \(streak) best \(best) fastest \(minimum)"
    }
}

struct Program {
    var game: Board?
    var safety = "block"
    var stats = Statistics()

    mutating func execute(_ words: [String], rows: [String]) throws -> [String] {
        guard let command = Command(rawValue: words[0]) else {
            try fail("unknown command \(words[0])")
        }
        if command == .layout {
            let width = Int(words[1])!, height = Int(words[2])!
            for (index, row) in rows.enumerated() {
                if row.utf8.count != width || !row.utf8
                    .allSatisfy({ $0 == 42 || $0 == 46 })
                {
                    try fail("bad row \(index + 1)")
                }
            }
            let mines = rows.joined().utf8.map { $0 == 42 }
            let count = mines.filter { $0 }.count
            if count == 0 || count == width * height {
                try fail("bad mine count \(count)")
            }
            var board = Board(width: width, height: height, mines: count, seed: 1)
            board.determine(mines)
            game = board
            return ["layout \(width)x\(height) mines \(count)"]
        }
        let format = Array(formats[command]!)
        if words.count - 1 != format.count {
            try fail("bad arguments")
        }
        var values = Array(repeating: Int64(0), count: format.count)
        for (index, kind) in format.enumerated() {
            let word = words[index + 1]
            switch kind {
            case "n":
                values[index] = try numberWord(word)
            case "p":
                if presets[word] == nil {
                    try fail("bad arguments")
                }
            default:
                if !["block", "cell", "none"].contains(word) {
                    try fail("bad arguments")
                }
            }
        }
        if command == .new || command == .preset {
            let width: Int64, height: Int64, count: Int64, seed: Int64
            if command == .new {
                width = values[0]
                height = values[1]
                count = values[2]
                seed = values[3]
            } else {
                let preset = presets[words[1]]!
                width = Int64(preset.width)
                height = Int64(preset.height)
                count = Int64(preset.mines)
                seed = values[1]
            }
            if width < 1 || width > 30 || height < 1 || height > 30 || count < 1 || count > width * height - 9 || seed <
                1 || seed > 2147483646
            {
                try fail("bad value")
            }
            game = Board(width: Int(width), height: Int(height), mines: Int(count), seed: seed)
            return ["new \(width)x\(height) mines \(count)"]
        }
        if command == .history && values[0] == 0 {
            try fail("bad value")
        }
        if command == .safety {
            safety = words[1]
            return ["safety \(safety)"]
        }
        if command == .stats {
            return [stats.display()]
        }
        guard var board = game else {
            try fail("no game")
        }
        var cell = -1
        if cellCommands.contains(command) {
            if values[0] >= Int64(board.width) || values[1] >= Int64(board.height) {
                try fail("out of range")
            }
            cell = Int(values[1]) * board.width + Int(values[0])
        }
        if liveCommands.contains(command) && board.finished {
            try fail("game over")
        }
        if (command == .analyze || command == .boardInfo) && board.state == .ready {
            try fail("not started")
        }
        let snapshot = undoCommands.contains(command) ? Snapshot(
            command: command.rawValue.lowercased(), visible: board.visible, marks: board.marks,
            moveCount: board.moves.count
        ) : nil
        let output = try boardCommand(command, values: values, cell: cell, board: &board)
        if let snapshot, board.moves.count > snapshot.moveCount {
            board.undo.append(snapshot)
        }
        if [Command.reveal, .chord, .auto, .solve].contains(command) && board.finished {
            stats.finish(board)
        }
        game = board
        return output
    }

    func boardCommand(_ command: Command, values: [Int64], cell: Int, board: inout Board) throws -> [String] {
        switch command {
        case .restart:
            board.restart()
            return ["restart \(board.width)x\(board.height) mines \(board.mineCount)"]
        case .reveal, .flag, .unflag, .question:
            if board.visible[cell] {
                try fail("already revealed")
            }
            let mark = board.marks[cell]
            if command == .reveal && mark == .flag {
                try fail("flagged")
            }
            if command == .flag && mark == .flag {
                try fail("already flagged")
            }
            if command == .unflag && mark != .flag {
                try fail("not flagged")
            }
            board.moves.append(Move(kind: MoveKind(rawValue: command.rawValue.lowercased())!, cell: cell))
            if command == .reveal {
                let opened = board.reveal(cell, safety: safety)
                if board.state == .lost {
                    return board.finishOutput()
                }
                board.checkWin()
                return ["revealed \(opened)"] + board.finishOutput()
            }
            board.marks[cell] = command == .flag ? .flag : command == .unflag || mark == .question ? .none : .question
            let action = command == .flag ? "flagged" : command == .unflag ? "unflagged" : mark == .question ?
                "unmarked" : "questioned"
            return ["\(action) \(board.coordinate(cell)) left \(board.remaining)"]
        case .chord:
            if !board.visible[cell] {
                try fail("not revealed")
            }
            let number = board.numbers[cell]
            if number == 0 {
                try fail("no number")
            }
            let flags = board.neighbors[cell].filter { board.marks[$0] == .flag }.count
            if flags != number {
                try fail("flags \(flags) of \(number)")
            }
            if !board.neighbors[cell].contains(where: { board.unknown($0) }) {
                try fail("nothing to reveal")
            }
            board.moves.append(Move(kind: .chord, cell: cell))
            let opened = board.chord(cell, safety: safety)
            if board.state == .lost {
                return board.finishOutput()
            }
            board.checkWin()
            return ["chorded \(opened)"] + board.finishOutput()
        case .undo:
            guard let previous = board.undo.popLast() else {
                try fail("nothing to undo")
            }
            board.visible = previous.visible
            board.marks = previous.marks
            board.moves.removeSubrange(previous.moveCount...)
            return ["undo \(previous.command) moves \(board.moves.count)"]
        case .show:
            return board.display()
        case .status:
            return [
                "status \(board.state.rawValue) left \(board.remaining) moves \(board.moves.count) revealed \(board.revealedCount)/\(board.safeCount)"
            ]
        case .cell:
            let neighbors = board.neighbors[cell]
            if !board.visible[cell] {
                let opened = neighbors.filter { board.visible[$0] }.count
                return ["cell \(board.coordinate(cell)) hidden mark \(board.marks[cell].rawValue) open \(opened)"]
            }
            let flags = neighbors.filter { board.marks[$0] == .flag }.count
            let unknown = neighbors.filter { board.unknown($0) }.count
            return ["cell \(board.coordinate(cell)) number \(board.numbers[cell]) flags \(flags) unknown \(unknown)"]
        case .history:
            var output = ["history \(board.moves.count)"]
            let count = Int(min(values[0], Int64(board.moves.count)))
            for index in (board.moves.count - count)..<board.moves.count {
                let move = board.moves[index]
                output.append("\(index + 1) \(move.kind.rawValue) \(board.coordinate(move.cell))")
            }
            return output
        case .replay:
            if values[0] > Int64(board.moves.count) {
                try fail("no move \(values[0])")
            }
            return ["replay \(values[0])/\(board.moves.count)"] + board.replay(Int(values[0]), safety: safety)
        case .hint:
            let deduction = board.deduce()
            let choices = deduction.safe.isEmpty ? deduction.mines : deduction.safe
            guard let chosen = choices.keys.min() else {
                return ["hint none"]
            }
            let kind = deduction.safe.isEmpty ? "mine" : "safe"
            return ["hint \(kind) \(board.coordinate(chosen)) by \(choices[chosen]!)"]
        case .auto, .solve:
            let result = command == .auto ? board.automatic(safety: safety) : board.solve(safety: safety)
            let prefix = command == .auto ? "auto" : "solve guesses \(result.guesses)"
            return ["\(prefix) rounds \(result.rounds) flagged \(result.flagged) revealed \(result.opened)"] + board
                .finishOutput()
        case .analyze:
            var copy = board
            copy.undo = []
            let result = copy.automatic(safety: safety)
            if copy.state == .lost {
                return ["analyze boom \(copy.coordinate(copy.exploded)) rounds \(result.rounds)"]
            }
            if copy.state == .won {
                return ["analyze clear rounds \(result.rounds)"]
            }
            return ["analyze stuck rounds \(result.rounds) revealed \(copy.revealedCount)/\(copy.safeCount)"]
        case .prob:
            if board.visible[cell] {
                try fail("already revealed")
            }
            if board.marks[cell] == .flag {
                try fail("flagged")
            }
            guard let component = board.frontier().first(where: { $0.cells.contains(cell) }) else {
                return ["prob \(board.coordinate(cell)) unconstrained"]
            }
            let configurations = countConfigurations(component)
            if configurations.count == 0 {
                return ["prob \(board.coordinate(cell)) inconsistent"]
            }
            let numerator = configurations.frequencies[component.cells.firstIndex(of: cell)!]
            return [
                "prob \(board.coordinate(cell)) \(fraction(numerator, configurations.count)) size \(component.cells.count) configs \(configurations.count)"
            ]
        case .frontier:
            let components = board.frontier()
            let count = components.reduce(0) { $0 + $1.cells.count }
            var output = ["frontier \(count) components \(components.count)"]
            for component in components {
                let configurations = countConfigurations(component)
                let prefix = "component \(board.coordinate(component.cells[0])) size \(component.cells.count)"
                output.append(configurations.count == 0 ? "\(prefix) inconsistent" :
                    "\(prefix) configs \(configurations.count) min \(configurations.minimum) max \(configurations.maximum)")
            }
            return output
        case .boardInfo:
            return [board.boardInfo()]
        default:
            preconditionFailure("Global command reached board dispatch")
        }
    }
}

let commandCount = Int(readLine()!)!
var program = Program()
for _ in 0..<commandCount {
    let words = readLine()!.split(separator: " ").map(String.init)
    var rows: [String] = []
    if words[0] == "LAYOUT" {
        for _ in 0..<Int(words[2])! {
            rows.append(readLine()!)
        }
    }
    do {
        print(try program.execute(words, rows: rows).joined(separator: "\n"))
    } catch let error as CommandError {
        print("error: \(error.message)")
    } catch {
        fatalError(String(describing: error))
    }
}
