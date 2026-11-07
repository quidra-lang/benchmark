import Foundation

let kinds = Array("IOTSZJL")
let operations = ["L", "R", "LL", "RR", "SD", "DD", "CW", "CCW", "HD", "LOCK", "HOLD"]
let commands = [
    "NEW",
    "PRINT",
    "NEXT",
    "PREVIEW",
    "STATUS",
    "ANALYZE",
    "ROW",
    "GARBAGE",
    "ATTACK",
    "TICK",
    "UNDO",
    "SAVE",
    "LOAD",
    "SPINS",
    "HINT",
    "AUTO"
]
let allowedAfterEnd: Set<String> = ["PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD"]
let stateNames = Array("0R2L")
let clearNames = [
    "SINGLE",
    "DOUBLE",
    "TRIPLE",
    "TETRIS",
    "TSPIN_MINI",
    "TSPIN_MINI_SINGLE",
    "TSPIN_MINI_DOUBLE",
    "TSPIN",
    "TSPIN_SINGLE",
    "TSPIN_DOUBLE",
    "TSPIN_TRIPLE"
]
let frames = [
    ["....", "####", "....", "...."], ["##", "##"], [".#.", "###", "..."],
    [".##", "##.", "..."], ["##.", ".##", "..."], ["#..", "###", "..."], ["..#", "###", "..."]
]
let ordinaryKicks = [
    [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
    [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
    [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
    [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
    [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]]
]
let iKicks = [
    [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
    [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]],
    [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
    [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
    [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]]
]
let kickStates = [[0, 1], [1, 0], [1, 2], [2, 1], [2, 3], [3, 2], [3, 0], [0, 3]]

struct Position: Hashable {
    var s: Int
    var x: Int
    var y: Int
}
struct Cell: Hashable {
    var x: Int
    var y: Int
}
struct Movement {
    let position: Position
    let test: Int
}
struct Metrics {
    let heights: [Int]
    let holes: Int
    let bumpiness: Int
    let value: Int
}
struct ClearInfo {
    let name: Int
    let points: Int
    let sent: Int
}
struct Statistics {
    var drops = 0
    var holds = 0
    var operations = 0
    var faults = 0
    var perfect = 0
    var sent = 0
    var cancelled = 0
    var received = 0
    var combo = 0
    var chain = 0
    var kinds = Array(repeating: 0, count: 7)
    var clears = Array(repeating: 0, count: 11)
}
struct State {
    var board = Array(repeating: 0, count: 22)
    var random: Int
    var queue: [Int] = []
    var hold: Int? = nil
    var usedHold = false
    var kind = 0
    var position = Position(s: 0, x: 4, y: 22)
    var last = 0
    var test = 0
    var keys = 0
    var drop = 0
    var fall = 0
    var ground = 0
    var resets = 0
    var lowest = 0
    var initialLevel: Int
    var level: Int
    var score = 0
    var lines = 0
    var pieces = 0
    var streak = 0
    var chain = 0
    var pending: [Int] = []
    var ended = false
    var stats = Statistics()
}
struct SavedGame {
    let state: State
    let history: [State]
    let start: State
}
struct RouteNode {
    let position: Position
    let parent: Int
    let operation: Int
}
struct Candidate {
    let kind: Int
    let value: Int
    let operations: [Int]
    let occupied: [Int]
    var order: Int = 0
}
struct SpinCandidate {
    let position: Position
    let spin: Int
}
enum GameOver: Error { case ended }
var output: [String] = []
func emit(_ line: String) {
    output.append(line)
}

let shapes: [[[Cell]]] = {
    frames.enumerated().map { (kind, pattern) in
        let n = pattern.count
        var cells: [Cell] = []
        for (j, line) in pattern.enumerated() {
            for (i, character) in line.enumerated() where character == "#" {
                cells.append(Cell(x: i, y: j))
            }
        }
        var rotations: [[Cell]] = [cells]
        for _ in 1..<4 {
            cells = cells.map { Cell(x: n - 1 - $0.y, y: $0.x) }
            rotations.append(cells)
        }
        return rotations
    }
}()
func seedStep(_ x: Int) -> Int {
    (48271 * x) % 2147483647
}
func spawn(_ kind: Int) -> Position {
    Position(s: 0, x: kind == 1 ? 5 : 4, y: 22)
}
func cells(_ kind: Int, _ p: Position) -> [Cell] {
    shapes[kind][p.s].map { Cell(x: p.x + $0.x, y: p.y - $0.y) }
}
func lowest(_ kind: Int, _ p: Position) -> Int {
    cells(kind, p).map(\.y).min()!
}
func bag(_ initial: Int) -> (Int, [Int]) {
    var random = initial
    var pieces = Array(0..<7)
    for i in stride(from: 6, through: 1, by: -1) {
        random = seedStep(random)
        pieces.swapAt(i, random % (i + 1))
    }
    return (random, pieces)
}
func fits(_ board: [Int], _ kind: Int, _ p: Position) -> Bool {
    for cell in cells(kind, p) {
        if cell.x < 1 || cell.x > 10 || cell.y < 1 || cell.y > 22 {
            return false
        }
        if (board[cell.y - 1] & (1 << (cell.x - 1))) != 0 {
            return false
        }
    }
    return true
}
func move(_ board: [Int], _ kind: Int, _ p: Position, _ op: Int) -> Movement? {
    if op == 6 || op == 7 {
        let b = (p.s + (op == 6 ? 1 : 3)) % 4
        let row = kickStates.firstIndex { $0[0] == p.s && $0[1] == b }!
        let kicks = kind == 1 ? [[0, 0]] : (kind == 0 ? iKicks : ordinaryKicks)[row]
        for (index, offset) in kicks.enumerated() {
            let target = Position(s: b, x: p.x + offset[0], y: p.y + offset[1])
            if fits(board, kind, target) {
                return Movement(position: target, test: index + 1)
            }
        }
        return nil
    }
    let dx = (op == 0 || op == 2) ? -1 : (op == 1 || op == 3) ? 1 : 0
    let dy = dx == 0 ? -1 : 0
    var q = p
    var changed = false
    repeat {
        let next = Position(s: p.s, x: q.x + dx, y: q.y + dy)
        if !fits(board, kind, next) {
            break
        }
        q = next
        changed = true
    } while op == 2 || op == 3 || op == 5
    return changed ? Movement(position: q, test: 0) : nil
}
func landing(_ board: [Int], _ kind: Int, _ p: Position) -> Position {
    move(board, kind, p, 5)?.position ?? p
}
func placed(_ board: [Int], _ kind: Int, _ p: Position) -> ([Int], Int) {
    var next = board
    for cell in cells(kind, p) {
        next[cell.y - 1] |= 1 << (cell.x - 1)
    }
    let remaining = next.filter { $0 != 1023 }
    let n = 22 - remaining.count
    return (remaining + Array(repeating: 0, count: n), n)
}
func evaluate(_ board: [Int], _ cleared: Int) -> Metrics {
    var heights = Array(repeating: 0, count: 10)
    var holes = 0
    for c in 0..<10 {
        for r in stride(from: 21, through: 0, by: -1) where (board[r] & (1 << c)) != 0 {
            heights[c] = r + 1
            break
        }
        if heights[c] > 0 {
            for r in 0..<heights[c] where (board[r] & (1 << c)) == 0 {
                holes += 1
            }
        }
    }
    var bumpiness = 0
    for c in 0..<9 {
        bumpiness += abs(heights[c] - heights[c + 1])
    }
    return Metrics(
        heights: heights,
        holes: holes,
        bumpiness: bumpiness,
        value: 76 * cleared - 51 * heights.reduce(0,+) - 36 * holes - 18 * bumpiness
    )
}
func routes(_ board: [Int], _ kind: Int, _ start: Position, _ target: Position? = nil) -> ([RouteNode], Int?) {
    guard fits(board, kind, start) else {
        return ([], nil)
    }
    var queue = [RouteNode(position: start, parent: -1, operation: -1)]
    var seen: Set<Position> = [start]
    var i = 0
    while i < queue.count {
        let entry = queue[i]
        if let target, landing(board, kind, entry.position) == target {
            return (queue, i)
        }
        for op in 0..<8 {
            guard let result = move(board, kind, entry.position, op) else {
                continue
            }
            if seen.insert(result.position).inserted {
                queue.append(RouteNode(position: result.position, parent: i, operation: op))
            }
        }
        i += 1
    }
    return (target == nil ? queue : [], nil)
}
func shortest(_ nodes: [RouteNode], _ index: Int) -> [Int] {
    var i = index
    var operations: [Int] = []
    while nodes[i].parent >= 0 {
        operations.append(nodes[i].operation)
        i = nodes[i].parent
    }
    return operations.reversed()
}
func tSpin(_ board: [Int], _ p: Position, _ test: Int) -> Int {
    let corners = [
        Cell(x: p.x, y: p.y),
        Cell(x: p.x + 2, y: p.y),
        Cell(x: p.x + 2, y: p.y - 2),
        Cell(x: p.x, y: p.y - 2)
    ]
    let blocked = corners
        .map { c in c.x < 1 || c.x > 10 || c.y < 1 || c.y > 22 || (board[c.y - 1] & (1 << (c.x - 1))) != 0 }
    if blocked.filter({ $0 }).count < 3 {
        return 0
    }
    return (blocked[p.s] && blocked[(p.s + 1) % 4]) || test == 5 ? 2 : 1
}
func clearInfo(_ spin: Int, _ lines: Int) -> ClearInfo {
    if spin == 2 {
        return ClearInfo(name: 7 + lines, points: [400, 800, 1200, 1600][lines], sent: [0, 2, 4, 6][lines])
    }
    if spin == 1 {
        return ClearInfo(name: 4 + lines, points: [100, 200, 400][lines], sent: [0, 0, 1][lines])
    }
    return ClearInfo(
        name: lines == 0 ? -1 : lines - 1,
        points: [0, 100, 300, 500, 800][lines],
        sent: [0, 0, 1, 2, 4][lines]
    )
}
func operationText(_ keys: [Int]) -> String {
    keys.map { operations[$0] }.joined(separator: " ")
}

final class Game {
    let number: Int
    var state: State
    var history: [State] = []
    var start: State
    var saves: [String: SavedGame] = [:]
    init(number: Int, seed: Int, level: Int) throws {
        self.number = number
        state = State(random: seed, initialLevel: level, level: level)
        start = state
        addBag()
        try spawnPiece(takeNext())
        start = state
    }
    func addBag() {
        let result = bag(state.random)
        state.random = result.0
        state.queue += result.1
    }
    func takeNext() -> Int {
        let k = state.queue.removeFirst()
        if state.queue.count < 5 {
            addBag()
        }
        return k
    }
    func spawnPiece(_ kind: Int) throws {
        state.kind = kind
        state.position = spawn(kind)
        state.last = 0
        state.test = 0
        state.keys = 0
        state.drop = 0
        state.fall = 0
        state.ground = 0
        state.resets = 0
        state.lowest = lowest(kind, state.position)
        if !fits(state.board, kind, state.position) {
            try gameOver("block out")
        }
    }
    func gameOver(_ reason: String) throws -> Never {
        emit("game over \(reason)")
        summary()
        state.ended = true
        throw GameOver.ended
    }
    func update(_ p: Position, _ last: Int, _ test: Int = 0) {
        state.position = p
        state.last = last
        state.test = test
        let row = lowest(state.kind, p)
        if row < state.lowest {
            state.lowest = row
            state.resets = 0
        }
    }
    func grounded() -> Bool {
        move(state.board, state.kind, state.position, 4) == nil
    }
    func drops(_ points: Int) {
        state.score += points
        state.drop += points
        state.stats.drops += points
    }
    func insertGarbage(_ count: Int, _ hole: Int) throws {
        if state.board.suffix(count).contains(where: { $0 != 0 }) {
            try gameOver("top out")
        }
        state.board = Array(repeating: 1023 ^ (1 << (hole - 1)), count: count) + state.board.prefix(22 - count)
    }
    func operation(_ op: Int) throws {
        if op < 8 {
            state.keys += 1
            guard let next = move(state.board, state.kind, state.position, op) else {
                emit("fail \(operations[op])")
                return
            }
            if op == 4 || op == 5 {
                drops(state.position.y - next.position.y)
                update(next.position, 1)
                state.fall = 0
                state.ground = 0
            } else {
                update(next.position, op >= 6 ? 2 : 1, next.test)
                if state.ground > 0 && state.resets < 15 {
                    state.ground = 0
                    state.resets += 1
                }
            }
        } else if op == 8 {
            let p = landing(state.board, state.kind, state.position)
            let rows = state.position.y - p.y
            drops(2 * rows)
            if rows > 0 {
                update(p, 1)
            }
            try lock()
        } else if op == 9 {
            if grounded() {
                try lock()
            } else {
                emit("fail LOCK")
            }
        } else {
            if state.usedHold {
                emit("fail HOLD")
                return
            }
            state.usedHold = true
            state.stats.holds += 1
            let previous = state.hold
            state.hold = state.kind
            try spawnPiece(previous ?? takeNext())
        }
    }
    func tick() throws {
        if !grounded() {
            state.ground = 0
            state.fall += 1
            let interval = state.level >= 13 ? 1 : [60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2][state.level - 1]
            if state.fall >= interval {
                update(Position(s: state.position.s, x: state.position.x, y: state.position.y - 1), 1)
                state.fall = 0
            }
        } else {
            state.ground += 1
            if state.ground >= 30 {
                try lock()
            }
        }
    }
    func lock() throws {
        let kind = state.kind
        let position = state.position
        let oldCells = cells(kind, position)
        let route = routes(state.board, kind, spawn(kind), position)
        let shortestOperations = route.1.map { shortest(route.0, $0) }
        let spin = kind == 2 && state.last == 2 ? tSpin(state.board, position, state.test) : 0
        let placement = placed(state.board, kind, position)
        let n = placement.1
        state.board = placement.0
        history.append(start)
        state.pieces += 1
        state.stats.kinds[kind] += 1
        state.stats.operations += state.keys
        let info = clearInfo(spin, n)
        let level = state.level
        var points = info.points * level
        var sent = info.sent
        var back = false
        if n > 0 {
            state.streak += 1
            if n == 4 || spin != 0 {
                state.chain += 1
                back = state.chain >= 2
            } else {
                state.chain = 0
            }
        } else {
            state.streak = 0
        }
        if back {
            points = points * 3 / 2
            sent += 1
        }
        let combo = state.streak - 1
        let comboPoints = combo >= 1 ? 50 * combo * level : 0
        if combo >= 0 {
            sent += [0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5][min(combo, 10)]
        }
        let perfect = n > 0 && state.board.allSatisfy { $0 == 0 }
        let perfectPoints = perfect ? (n == 4 && back ? 3200 : [800, 1200, 1800, 2000][n - 1]) * level : 0
        if perfect {
            sent += 10
            state.stats.perfect += 1
        }
        let gained = points + comboPoints + perfectPoints
        state.score += gained
        state.lines += n
        state.stats.sent += sent
        state.stats.combo = max(state.stats.combo, combo)
        state.stats.chain = max(state.stats.chain, state.chain)
        emit(
            "lock \(state.pieces) \(kinds[kind]) \(stateNames[position.s]) \(position.x) \(position.y) keys \(state.keys) \(shortestOperations.map { String($0.count) } ?? "-") drop \(state.drop) lines \(n) sent \(sent) +\(gained) total \(state.score)"
        )
        if let shortestOperations, state.keys > shortestOperations.count {
            state.stats.faults += 1
            emit("finesse \(shortestOperations.isEmpty ? "none" : operationText(shortestOperations))")
        }
        if info.name >= 0 {
            state.stats.clears[info.name] += 1
            var line = "clear \(clearNames[info.name]) \(points)"
            if back {
                line += " b2b"
            }
            if combo >= 1 {
                line += " combo \(combo) \(comboPoints)"
            }
            if perfect {
                line += " perfect \(perfectPoints)"
            }
            emit(line)
        }
        let nextLevel = state.initialLevel + state.lines / 10
        if nextLevel > level {
            state.level = nextLevel
            emit("level \(nextLevel)")
        }
        if oldCells.allSatisfy({ $0.y >= 21 }) {
            try gameOver("lock out")
        }
        let cancelled = min(sent, state.pending.reduce(0,+))
        var remaining = cancelled
        while remaining > 0 {
            let used = min(remaining, state.pending[0])
            remaining -= used
            state.pending[0] -= used
            if state.pending[0] == 0 {
                state.pending.removeFirst()
            }
        }
        if cancelled > 0 {
            state.stats.cancelled += cancelled
            emit("cancel \(cancelled) pending \(state.pending.reduce(0,+))")
        }
        if n == 0 {
            var risen = 0
            while !state.pending.isEmpty && risen < 8 {
                let count = min(state.pending[0], 8 - risen)
                state.random = seedStep(state.random)
                let hole = state.random % 10 + 1
                try insertGarbage(count, hole)
                state.stats.received += count
                risen += count
                state.pending[0] -= count
                if state.pending[0] == 0 {
                    state.pending.removeFirst()
                }
                emit("rise \(count) hole \(hole) pending \(state.pending.reduce(0,+))")
            }
        }
        state.usedHold = false
        try spawnPiece(takeNext())
        start = state
    }
    func candidates(_ kind: Int, _ start: Position, _ prefix: [Int]) -> [Candidate] {
        var result: [Candidate] = []
        var seen = Set<[Int]>()
        for turns in [[], [6], [6, 6], [7]] {
            var p = start
            var valid = true
            for turn in turns {
                guard let next = move(state.board, kind, p, turn) else {
                    valid = false
                    break
                }
                p = next.position
            }
            if !valid {
                continue
            }
            func add(_ p: Position, _ shifts: [Int]) {
                let landed = landing(state.board, kind, p)
                let occupied = cells(kind, landed).map { ($0.y - 1) * 10 + $0.x - 1 }.sorted()
                if !seen.insert(occupied).inserted {
                    return
                }
                let placedResult = placed(state.board, kind, landed)
                let value = evaluate(placedResult.0, placedResult.1).value
                result.append(Candidate(
                    kind: kind,
                    value: value,
                    operations: prefix + turns + shifts + [8],
                    occupied: occupied
                ))
            }
            add(p, [])
            for direction in [0, 1] {
                var q = p
                var shifts: [Int] = []
                while let next = move(state.board, kind, q, direction) {
                    q = next.position
                    shifts.append(direction)
                    add(q, shifts)
                }
            }
        }
        return result
    }
    func ranked() -> [Candidate] {
        var result = candidates(state.kind, state.position, [])
        let held = state.hold ?? state.queue[0]
        if !state.usedHold && fits(state.board, held, spawn(held)) {
            result += candidates(held, spawn(held), [10])
        }
        for i in result.indices {
            result[i].order = i
        }
        result.sort { a, b in a.value == b.value ? a.order < b.order : a.value > b.value }
        return result
    }
    func spins() {
        if state.kind != 2 {
            emit("spins 0")
            return
        }
        var found: [Position: Int] = [:]
        for entry in routes(state.board, 2, state.position).0 {
            for op in [6, 7] {
                guard let next = move(state.board, 2, entry.position, op),
                      move(state.board, 2, next.position, 4) == nil
                else {
                    continue
                }
                let spin = tSpin(state.board, next.position, next.test)
                if spin != 0 {
                    found[next.position] = max(found[next.position] ?? 0, spin)
                }
            }
        }
        let rows = found.map { SpinCandidate(position: $0.key, spin: $0.value) }.sorted {
            let a = $0.position, b = $1.position
            if a.y != b.y {
                return a.y < b.y
            }
            if a.x != b.x {
                return a.x < b.x
            }
            return a.s < b.s
        }
        for item in rows {
            let lines = placed(state.board, 2, item.position).1
            let info = clearInfo(item.spin, lines)
            emit("spin \(stateNames[item.position.s]) \(item.position.x) \(item.position.y) \(clearNames[info.name])")
        }
        emit("spins \(rows.count)")
    }
    func summary() {
        let s = state, a = state.stats, c = a.clears
        func ratio(_ a: Int, _ b: Int) -> String {
            let q = b == 0 ? 0 : 100 * a / b
            return "\(q / 100)." + String(format: "%02d", q % 100)
        }
        emit("summary game \(number) score \(s.score) level \(s.level) lines \(s.lines) pieces \(s.pieces)")
        emit("clears single \(c[0]) double \(c[1]) triple \(c[2]) tetris \(c[3]) perfect \(a.perfect)")
        emit(
            "tspins mini \(c[4]) mini_single \(c[5]) mini_double \(c[6]) zero \(c[7]) single \(c[8]) double \(c[9]) triple \(c[10])"
        )
        emit("pieces " + kinds.indices.map { "\(kinds[$0]) \(a.kinds[$0])" }.joined(separator: " "))
        emit("best combo \(a.combo) chain \(a.chain) holds \(a.holds) drops \(a.drops) faults \(a.faults)")
        emit("garbage sent \(a.sent) cancelled \(a.cancelled) received \(a.received)")
        emit("rates app \(ratio(a.sent, s.pieces)) apl \(ratio(a.sent, s.lines)) kpp \(ratio(a.operations, s.pieces))")
    }
    func command(_ name: String, _ args: [String]) throws {
        switch name {
        case "PRINT":
            var current = Set<Cell>(), ghost = Set<Cell>()
            if !state.ended {
                current = Set(cells(state.kind, state.position))
                ghost = Set(cells(state.kind, landing(state.board, state.kind, state.position)))
            }
            for r in stride(from: 22, through: 1, by: -1) {
                var line = String(format: "%2d ", r)
                for c in 1...10 {
                    let cell = Cell(x: c, y: r)
                    if (state.board[r - 1] & (1 << (c - 1))) != 0 {
                        line += "#"
                    } else if current.contains(cell) {
                        line += "@"
                    } else if ghost.contains(cell) {
                        line += "+"
                    } else {
                        line += "."
                    }
                }
                emit(line)
            }
        case "NEXT":
            emit("hold \(state.hold.map { String(kinds[$0]) } ?? "-") next " + state.queue.prefix(5)
                .map { String(kinds[$0]) }.joined())
        case "PREVIEW":
            var queue = state.queue, random = state.random
            let n = Int(args[0])!
            while queue.count < n {
                let result = bag(random)
                random = result.0
                queue += result.1
            }
            emit("preview " + queue.prefix(n).map { String(kinds[$0]) }.joined())
        case "STATUS":
            emit("score \(state.score) level \(state.level) lines \(state.lines) pieces \(state.pieces)")
            let piece = state.ended ? "-" : "\(kinds[state.kind]) \(stateNames[state.position.s]) \(state.position.x) \(state.position.y)"
            emit("piece \(piece) streak \(state.streak) chain \(state.chain) pending \(state.pending.reduce(0,+))")
        case "ANALYZE":
            let e = evaluate(state.board, 0)
            emit("heights " + e.heights.map(String.init).joined(separator: " "))
            emit("holes \(e.holes) bumpiness \(e.bumpiness) value \(e.value)")
        case "ROW":
            let row = Int(args[0])!, pattern = Array(args[1])
            if cells(state.kind, state.position)
                .contains(where: { $0.y == row && pattern[$0.x - 1] == "#" })
            {
                emit("ERROR overlap")
                return
            }
            var mask = 0
            for i in 0..<10 where pattern[i] == "#" {
                mask |= 1 << i
            }
            state.board[row - 1] = mask
            emit("OK")
        case "GARBAGE":
            let n = Int(args[0])!, hole = Int(args[1])!
            try insertGarbage(n, hole)
            for j in 0...n {
                let p = Position(s: state.position.s, x: state.position.x, y: state.position.y + j)
                if fits(state.board, state.kind, p) {
                    state.position = p
                    emit("OK")
                    return
                }
            }
            try gameOver("top out")
        case "ATTACK":
            state.pending.append(Int(args[0])!)
            emit("pending \(state.pending.reduce(0,+))")
        case "TICK":
            for _ in 0..<Int(args[0])! {
                try tick()
            }
        case "UNDO":
            guard !history.isEmpty else {
                emit("ERROR nothing to undo")
                return
            }
            state = history.removeLast()
            start = state
            emit("undo \(state.pieces) \(kinds[state.kind])")
        case "SAVE":
            saves[args[0]] = SavedGame(state: state, history: history, start: start)
            emit("OK")
        case "LOAD":
            guard let saved = saves[args[0]] else {
                emit("ERROR unknown save")
                return
            }
            state = saved.state
            history = saved.history
            start = saved.start
            emit("load \(state.pieces) \(kinds[state.kind])")
        case "SPINS":
            spins()
        case "HINT":
            for (i, c) in ranked().prefix(Int(args[0])!).enumerated() {
                emit("hint \(i + 1) \(kinds[c.kind]) \(operationText(c.operations)) value \(c.value)")
            }
        case "AUTO":
            for _ in 0..<Int(args[0])! {
                let c = ranked()[0]
                emit("auto \(kinds[c.kind]) \(operationText(c.operations))")
                for op in c.operations {
                    try operation(op)
                }
            }
        default:
            break
        }
    }
}
func validNumber(_ string: String, _ minValue: Int, _ maxValue: Int) -> Bool {
    if string.isEmpty || (string.count > 1 && string.first == "0") || !string.utf8
        .allSatisfy({ $0 >= 48 && $0 <= 57 })
    {
        return false
    }
    guard let n = Int(string) else {
        return false
    }
    return n >= minValue && n <= maxValue
}
func validArgs(_ command: String, _ args: [String]) -> Bool {
    if command == "NEW" {
        return args.count == 2 && validNumber(args[0], 1, 2147483646) && validNumber(args[1], 1, 15)
    }
    if command == "ROW" {
        return args.count == 2 && validNumber(args[0], 1, 22) && args[1].count == 10 && args[1]
            .allSatisfy({ $0 == "#" || $0 == "." }) && args[1].contains(".")
    }
    if command == "GARBAGE" {
        return args.count == 2 && validNumber(args[0], 1, 10) && validNumber(args[1], 1, 10)
    }
    if command == "SAVE" || command ==
        "LOAD"
    {
        return args.count == 1 && (1...8).contains(args[0].count) && args[0].utf8.allSatisfy({ $0 >= 97 && $0 <= 122 })
    }
    let limits = ["PREVIEW": 14, "ATTACK": 20, "TICK": 1000, "HINT": 10, "AUTO": 50]
    if let limit = limits[command] {
        return args.count == 1 && validNumber(args[0], 1, limit)
    }
    return args.isEmpty
}

let inputCount = Int(readLine() ?? "0") ?? 0
var game: Game?
var serial = 0
for _ in 0..<inputCount {
    guard let line = readLine() else {
        break
    }
    let words = line.split(separator: " ").map(String.init)
    guard let name = words.first else {
        continue
    }
    let args = Array(words.dropFirst())
    do {
        if commands.contains(name) {
            if !validArgs(name, args) {
                emit("ERROR bad arguments")
            } else if name == "NEW" {
                if let game, !game.state.ended {
                    emit("game stopped")
                    game.summary()
                }
                serial += 1
                emit("game \(serial) seed \(Int(args[0])!) level \(Int(args[1])!)")
                game = try Game(number: serial, seed: Int(args[0])!, level: Int(args[1])!)
            } else if let game {
                if game.state.ended && !allowedAfterEnd.contains(name) {
                    emit("ERROR game over")
                } else {
                    try game.command(name, args)
                }
            } else {
                emit("ERROR no game")
            }
        } else {
            let unknown = words.first(where: { !operations.contains($0) })
            if let unknown {
                emit("ERROR unknown \(unknown)")
            } else if let game {
                if game.state.ended {
                    emit("ERROR game over")
                } else {
                    for word in words {
                        try game.operation(operations.firstIndex(of: word)!)
                    }
                }
            } else {
                emit("ERROR no game")
            }
        }
    } catch GameOver.ended {}
}
if let game, !game.state.ended {
    emit("game stopped")
    game.summary()
}
FileHandle.standardOutput.write((output.joined(separator: "\n") + "\n").data(using: .utf8)!)
