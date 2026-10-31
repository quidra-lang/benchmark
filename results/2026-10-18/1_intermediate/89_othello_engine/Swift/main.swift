import Foundation
let weights = [
    100,
    -20,
    10,
    5,
    5,
    10,
    -20,
    100,
    -20,
    -50,
    -2,
    -2,
    -2,
    -2,
    -50,
    -20,
    10,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    10,
    5,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    5,
    5,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    5,
    10,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    10,
    -20,
    -50,
    -2,
    -2,
    -2,
    -2,
    -50,
    -20,
    100,
    -20,
    10,
    5,
    5,
    10,
    -20,
    100
]
let transforms = Set("rot90 rot180 rot270 mirror flip diag anti".components(separatedBy: " "))
let zero = Set("NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE".components(separatedBy: " "))
let numeric = Set("UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE".components(separatedBy: " "))
let active = Set("FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE".components(separatedBy: " "))
let extra = Set("LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD".components(separatedBy: " "))
func other(_ s: UInt8) -> UInt8 {
    s == 66 ? 87 : 66
}
func color(_ s: UInt8) -> String {
    String(UnicodeScalar(s))
}
func name(_ p: Int) -> String {
    String(UnicodeScalar(97 + p % 8)!) + String(p / 8 + 1)
}
func square(_ s: String) -> Int {
    let a = Array(s.utf8)
    return (Int(a[1]) - 49) * 8 + Int(a[0]) - 97
}
func inside(_ r: Int, _ c: Int) -> Bool {
    r >= 0 && r < 8 && c >= 0 && c < 8
}
func initial() -> [UInt8] {
    var b = Array(repeating: UInt8(46), count: 64)
    b[27] = 87
    b[36] = 87
    b[28] = 66
    b[35] = 66
    return b
}
func flips(_ b: [UInt8], _ s: UInt8, _ p: Int) -> [Int] {
    if b[p] != 46 {
        return []
    }
    var out: [Int] = []
    let row = p / 8, col = p % 8
    for dr in -1...1 {
        for dc in -1...1 {
            if dr == 0 && dc == 0 {
                continue
            }
            var r = row + dr, c = col + dc
            var line: [Int] = []
            while inside(r, c) && b[8 * r + c] == other(s) {
                line.append(8 * r + c)
                r += dr
                c += dc
            }
            if !line.isEmpty && inside(r, c) && b[8 * r + c] == s {
                out += line
            }
        }
    }
    return out.sorted()
}
func legal(_ b: [UInt8], _ s: UInt8) -> [Int] {
    (0..<64).filter {
        b[$0] == 46 && !flips(b, s, $0).isEmpty
    }
}
func place(_ b: [UInt8], _ s: UInt8, _ p: Int) -> [UInt8] {
    var a = b
    for q in flips(b, s, p) {
        a[q] = s
    }
    a[p] = s
    return a
}
func count(_ b: [UInt8], _ s: UInt8) -> Int {
    b.filter {
        $0 == s
    }.count
}
func terminal(_ b: [UInt8]) -> Bool {
    legal(b, 66).isEmpty && legal(b, 87).isEmpty
}
func gameOver(_ b: [UInt8]) -> String {
    let x = count(b, 66), y = count(b, 87)
    return "game over B \(x) W \(y) \(x > y ? "winner B" : x < y ? "winner W" : "draw")"
}
func evaluate(_ b: [UInt8], _ s: UInt8) -> [Int] {
    let w = (0..<64).reduce(0) {
        $0 + (b[$1] == s ? weights[$1] : b[$1] == other(s) ? -weights[$1] : 0)
    }, own = legal(b, s).count, enemy = legal(b, other(s)).count
    return [w + 10 * (own - enemy), w, own, enemy]
}
struct Key: Hashable {
    let board: [UInt8]
    let side: UInt8
    let depth: Int
}
var searchCache: [Key: Int] = [:], perftCache: [Key: Int] = [:]
func search(_ b: [UInt8], _ s: UInt8, _ d: Int) -> Int {
    let key = Key(board: b, side: s, depth: d)
    if let found = searchCache[key] {
        return found
    }
    let moves = legal(b, s), o = other(s)
    let v: Int
    if moves.isEmpty && legal(b, o).isEmpty {
        v = (d < 0 ? 1 : 1000) * (count(b, s) - count(b, o))
    } else if d == 0 {
        v = evaluate(b, s)[0]
    } else if moves.isEmpty {
        v = -search(b, o, d < 0 ? -1 : d - 1)
    } else {
        v = moves.map { -search(place(b, s, $0), o, d < 0 ? -1 : d - 1)
        }.max()!
    }
    if searchCache.count > 300000 {
        searchCache.removeAll()
    }
    searchCache[key] = v
    return v
}
func ranked(_ b: [UInt8], _ s: UInt8, _ d: Int) -> [(Int, Int)] {
    legal(b, s).map {
        (-search(place(b, s, $0), other(s), d < 0 ? -1 : d - 1), $0)
    }.sorted {
        $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1
    }
}
func variation(_ start: [UInt8], _ side: UInt8, _ depth: Int) -> ([String], [UInt8]) {
    var b = start, s = side, d = depth
    var steps: [String] = []
    while d != 0 && !terminal(b) {
        let rows = ranked(b, s, d)
        if rows.isEmpty {
            steps.append("pass")
        } else {
            let p = rows[0].1
            steps.append(name(p))
            b = place(b, s, p)
        }
        s = other(s)
        if d > 0 {
            d -= 1
        }
    }
    return (steps, b)
}
func perft(_ b: [UInt8], _ s: UInt8, _ d: Int) -> Int {
    if d == 0 {
        return 1
    }
    let key = Key(board: b, side: s, depth: d)
    if let found = perftCache[key] {
        return found
    }
    let moves = legal(b, s), o = other(s)
    let n = moves.isEmpty ? (legal(b, o).isEmpty ? 1 : perft(b, o, d - 1)) : moves.reduce(0) {
        $0 + perft(place(b, s, $1), o, d - 1)
    }
    if perftCache.count > 200000 {
        perftCache.removeAll()
    }
    perftCache[key] = n
    return n
}
func stable(_ b: [UInt8]) -> (Int, Int) {
    var stable = Array(repeating: false, count: 64)
    let axes = [(0, 1), (1, 0), (1, 1), (1, -1)]
    while true {
        var found: [Int] = []
        for p in 0..<64 {
            if b[p] == 46 || stable[p] {
                continue
            }
            var ok = true
            for (dr, dc) in axes {
                var full = true, anchor = false
                for sign in [-1, 1] {
                    var r = p / 8 + dr * sign, c = p % 8 + dc * sign
                    if !inside(r, c) || (stable[8 * r + c] && b[8 * r + c] == b[p]) {
                        anchor = true
                    }
                    while inside(r, c) {
                        if b[8 * r + c] == 46 {
                            full = false
                        }
                        r += dr * sign
                        c += dc * sign
                    }
                }
                if !full && !anchor {
                    ok = false
                    break
                }
            }
            if ok {
                found.append(p)
            }
        }
        if found.isEmpty {
            break
        }
        for p in found {
            stable[p] = true
        }
    }
    return ((0..<64).filter {
        stable[$0] && b[$0] == 66
    }.count, (0..<64).filter {
        stable[$0] && b[$0] == 87
    }.count)
}
func transform(_ p: Int, _ op: String) -> Int {
    let r = p / 8, c = p % 8
    switch op {
    case "rot90":
        return 8 * c + 7 - r
    case "rot180":
        return 63 - p
    case "rot270":
        return 8 * (7 - c) + r
    case "mirror":
        return 8 * r + 7 - c
    case "flip":
        return 8 * (7 - r) + c
    case "diag":
        return 8 * c + r
    default:
        return 8 * (7 - c) + 7 - r
    }
}
func transformBoard(_ b: [UInt8], _ op: String) -> [UInt8] {
    var a = Array(repeating: UInt8(46), count: 64)
    for p in 0..<64 {
        a[transform(p, op)] = b[p]
    }
    return a
}
struct Minstd {
    var value: Int
    mutating func draw() -> Int {
        value = value * 48271 % 2147483647
        return value
    }
}
func randomGame(_ start: [UInt8], _ side: UInt8, _ rng: inout Minstd) -> [UInt8] {
    var b = start, s = side
    while true {
        let moves = legal(b, s)
        if !moves.isEmpty {
            b = place(b, s, moves[rng.draw() % moves.count])
        } else if legal(b, other(s)).isEmpty {
            return b
        }
        s = other(s)
    }
}
func average(_ f: Int, _ n: Int) -> String {
    let v = 100 * f / n
    return "\(v / 100)." + (v % 100 < 10 ? "0" : "") + String(v % 100)
}
struct Position {
    var board: [UInt8]
    let side: UInt8
    let over: Bool
}
struct Move {
    let side: UInt8
    var square: Int
    let count: Int, passed: Bool
    var before: Position, after: Position
}
func matches(_ s: String, _ pattern: String) -> Bool {
    s.range(of: pattern, options: .regularExpression) != nil
}
final class Othello {
    var board = initial()
    var side: UInt8 = 66
    var over = false
    var history: [Move] = [], redo: [Move] = []
    func reset() {
        board = initial()
        side = 66
        over = false
        history = []
        redo = []
    }
    func snapshot() -> Position {
        Position(board: board, side: side, over: over)
    }
    func restore(_ p: Position) {
        board = p.board
        side = p.side
        over = p.over
    }
    func status() -> String {
        over ? gameOver(board) : color(side) + " to move"
    }
    func adjust(_ quiet: Bool = false) -> Bool {
        if !legal(board, side).isEmpty {
            return false
        }
        if !legal(board, other(side)).isEmpty {
            if !quiet {
                print(color(side) + " passes")
            }
            side = other(side)
            return true
        }
        over = true
        if !quiet {
            print(gameOver(board))
        }
        return false
    }
    @discardableResult func move(_ p: Int, _ quiet: Bool = false, _ value: Int? = nil) -> Bool {
        let before = snapshot(), s = side, k = flips(board, side, p).count
        board = place(board, s, p)
        if !quiet {
            print("\(color(s)) \(name(p)) flips \(k)" + (value == nil ? "" : " value \(value!)"))
        }
        side = other(s)
        let passed = adjust(quiet)
        history.append(Move(side: s, square: p, count: k, passed: passed, before: before, after: snapshot()))
        redo = []
        return passed
    }
    func reason(_ p: Int) -> String {
        over ? "game over" : board[p] != 46 ? "occupied" : flips(board, side, p).isEmpty ? "no flips" : ""
    }
    func record(_ text: String) {
        let e = Othello(), chars = Array(text)
        var ps: [Int] = []
        var passes = 0
        for i in stride(from: 0, to: chars.count, by: 2) {
            let p = square(String(chars[i..<i + 2])), why = e.reason(p)
            if !why.isEmpty {
                print("ILLEGAL move \(i / 2 + 1) \(name(p)) \(why)")
                return
            }
            ps.append(p)
            if e.move(p, true) {
                passes += 1
            }
        }
        restore(e.snapshot())
        history = e.history
        redo = []
        let op = ["f5": "", "e6": "diag", "d3": "anti", "c4": "rot180"][name(ps[0])]!
        let normal = ps.map {
            name(op.isEmpty ? $0 : transform($0, op))
        }.joined()
        print("record \(ps.count) moves \(passes) passes")
        print("normal " + normal)
        print(status())
    }
    func sheet() {
        let b = history.isEmpty ? board : history[0].before.board
        var fields = b.map {
            color($0)
        }
        for (i, r) in history.enumerated() {
            fields[r.square] = String(i + 1)
        }
        print("   a  b  c  d  e  f  g  h")
        for r in 0..<8 {
            print(String(r + 1) + fields[8 * r..<8 * r + 8].map {
                String(repeating: " ", count: 3 - $0.count) + $0
            }.joined())
        }
    }
    func stats() {
        let total = history.reduce(0) {
            $0 + $1.count
        }
        if history.isEmpty {
            print("moves 0")
        } else {
            print(
                "moves \(history.count) flips \(total) avg \(average(total, history.count)) passes \(history.filter { $0.passed }.count)"
            )
        }
        for s in [UInt8(66), UInt8(87)] {
            let rows = history.filter {
                $0.side == s
            }
            if rows.isEmpty {
                print(color(s) + " moves 0")
                continue
            }
            let sum = rows.reduce(0) {
                $0 + $1.count
            }, maximum = rows.map {
                $0.count
            }.max()!, first = rows.first {
                $0.count == maximum
            }!, corners = rows.filter {
                [0, 7, 56, 63].contains($0.square)
            }.count
            print(
                "\(color(s)) moves \(rows.count) flips \(sum) avg \(average(sum, rows.count)) max \(maximum) \(name(first.square)) corners \(corners)"
            )
        }
    }
    func auto(_ black: Int, _ white: Int, _ seed: Int = 0) {
        var rng = Minstd(value: seed)
        var ps: [String] = []
        var passes = 0
        while !over {
            let moves = legal(board, side)
            let p = seed != 0 ? moves[rng.draw() % moves.count] : ranked(board, side, side == 66 ? black : white)[0].1
            ps.append(name(p))
            if move(p, true) {
                passes += 1
            }
        }
        print("\(seed != 0 ? "random" : "autoplay") \(ps.count) moves \(passes) passes")
        print("moves " + ps.joined())
        print(gameOver(board))
    }
    func monteCarlo(_ k: Int, _ seed: Int) {
        var rng = Minstd(value: seed)
        var best = -1, bp = -1
        for p in legal(board, side) {
            var w = 0, d = 0, l = 0
            let start = place(board, side, p)
            for _ in 0..<k {
                let b = randomGame(start, other(side), &rng), diff = count(b, side) - count(b, other(side))
                if diff > 0 {
                    w += 1
                } else if diff < 0 {
                    l += 1
                } else {
                    d += 1
                }
            }
            print("\(name(p)) \(w) \(d) \(l)")
            if 2 * w + d > best {
                best = 2 * w + d
                bp = p
            }
        }
        print("best \(name(bp)) \(best)")
    }
    func execute(_ text: String) {
        let words = text.components(separatedBy: " "), cmd = words[0], a = Array(words.dropFirst())
        var error = ""
        if !zero.contains(cmd) && !numeric.contains(cmd) && !extra.contains(cmd) {
            error = "unknown command"
        } else if cmd == "LOAD" {
            if a.count != 2 || !matches(a[0], "\\A[.BW]{64}\\z") || !["B", "W"].contains(a[1]) {
                error = "bad board"
            }
        } else if ["MOVE", "FLIPS"].contains(cmd) {
            if a.count != 1 {
                error = "bad arguments"
            } else if !matches(a[0], "\\A[a-h][1-8]\\z") {
                error = "bad square"
            }
        } else if ["PLAY", "RECORD"].contains(cmd) {
            if a.count != 1 {
                error = "bad arguments"
            } else if a[0].count > 120 || !matches(a[0], "\\A([a-h][1-8])+\\z") {
                error = "bad record"
            }
        } else if zero.contains(cmd) {
            if !a.isEmpty {
                error = "bad arguments"
            }
        } else if cmd == "TRANSFORM" {
            if a.count != 1 || !transforms.contains(a[0]) {
                error = "bad arguments"
            }
        } else {
            let expected = ["AUTOPLAY", "MC"].contains(cmd) ? 2 : 1
            var valid = a.count == expected && a.allSatisfy {
                matches($0, "\\A[0-9]+\\z")
            }
            if valid {
                let ns = a.map {
                    Int($0)!
                }, n = ns[0]
                switch cmd {
                case "AUTOPLAY":
                    valid = ns.allSatisfy {
                        (1...4).contains($0)
                    }
                case "HINT", "PV", "AI", "ANALYZE":
                    valid = (1...4).contains(n)
                case "PERFT", "DIVIDE":
                    valid = (1...8).contains(n)
                case "MC":
                    valid = (1...100).contains(n) && (1...2147483646).contains(ns[1])
                case "RANDOM":
                    valid = (1...2147483646).contains(n)
                default:
                    valid = n >= 1
                }
            }
            if !valid {
                error = "bad arguments"
            }
        }
        if !error.isEmpty {
            print("ERROR " + error)
            return
        }
        if over && active.contains(cmd) {
            print("ERROR game over")
            return
        }
        let n = a.first.flatMap {
            Int($0)
        }
            ?? 0
        switch cmd {
        case "NEW":
            reset()
            print("OK")
        case "LOAD":
            board = Array(a[0].utf8)
            side = Array(a[1].utf8)[0]
            over = false
            history = []
            redo = []
            print("OK")
            _ = adjust()
        case "DUMP":
            print("board \(String(decoding: board, as: UTF8.self)) \(color(side))")
        case "SHOW":
            print("  a b c d e f g h")
            let moves = Set(over ? [] : legal(board, side))
            for r in 0..<8 {
                print(String(r + 1) + " " + (0..<8).map {
                    moves.contains(8 * r + $0) ? "*" : color(board[8 * r + $0])
                }.joined(separator: " "))
            }
            print(status())
        case "SCORE":
            print("score B \(count(board, 66)) W \(count(board, 87)) empty \(count(board, 46))")
        case "LEGAL":
            let moves = over ? [] : legal(board, side)
            print((["legal", String(moves.count)] + moves.map {
                name($0)
            }).joined(separator: " "))
        case "MOVE", "FLIPS":
            let p = square(a[0]), why = reason(p)
            if !why.isEmpty {
                print("ILLEGAL " + why)
            } else if cmd == "MOVE" {
                move(p)
            } else {
                let f = flips(board, side, p)
                print((["flips", a[0], String(f.count)] + f.map {
                    name($0)
                }).joined(separator: " "))
            }
        case "PLAY":
            let chars = Array(a[0])
            for i in stride(from: 0, to: chars.count, by: 2) {
                let p = square(String(chars[i..<i + 2])), why = reason(p)
                if !why.isEmpty {
                    print("ILLEGAL move \(i / 2 + 1) \(name(p)) \(why)")
                    break
                }
                move(p)
            }
        case "RECORD":
            record(a[0])
        case "UNDO":
            if n > history.count {
                print("ERROR cannot undo")
            } else {
                let removed = Array(history.suffix(n))
                restore(removed[0].before)
                history.removeLast(n)
                redo = removed + redo
                print(status())
            }
        case "REDO":
            if n > redo.count {
                print("ERROR cannot redo")
            } else {
                let added = Array(redo.prefix(n))
                redo.removeFirst(n)
                history += added
                restore(added.last!.after)
                print(status())
            }
        case "HISTORY":
            print("history \(history.count)")
            for (i, r) in history.enumerated() {
                print("\(i + 1) \(color(r.side)) \(name(r.square)) \(r.count)" + (r.passed ? " pass" : ""))
            }
        case "SHEET":
            sheet()
        case "STATS":
            stats()
        case "TRANSFORM":
            let op = a[0]
            board = transformBoard(board, op)
            func tr(_ r: Move) -> Move {
                var row = r
                row.square = transform(r.square, op)
                row.before.board = transformBoard(r.before.board, op)
                row.after.board = transformBoard(r.after.board, op)
                return row
            }
            history = history.map {
                tr($0)
            }
            redo = redo.map {
                tr($0)
            }
            print("OK")
        case "EVAL":
            let e = evaluate(board, side)
            print("eval \(e[0]) weights \(e[1]) mobility \(e[2]) \(e[3])")
        case "STABLE":
            let (b, w) = stable(board)
            print("stable B \(b) W \(w)")
        case "HINT":
            for (v, p) in ranked(board, side, n) {
                print("\(name(p)) \(v)")
            }
        case "PV":
            let (steps, _) = variation(board, side, n)
            print((["pv", String(search(board, side, n))] + steps).joined(separator: " "))
        case "AI":
            let (v, p) = ranked(board, side, n)[0]
            move(p, false, v)
        case "ANALYZE":
            var loss: [UInt8: Int] = [66: 0, 87: 0]
            for (i, r) in history.enumerated() {
                let rows = ranked(r.before.board, r.side, n), (best, bp) = rows[0], value = rows.first {
                    $0.1 == r.square
                }!.0
                loss[r.side, default: 0] += best - value
                print("\(i + 1) \(color(r.side)) \(name(r.square)) \(value) best \(name(bp)) \(best)")
            }
            print("loss B \(loss[66]!) W \(loss[87]!)")
        case "SOLVE":
            if count(board, 46) >= 9 {
                print("ERROR too many empties")
            } else {
                for (v, p) in ranked(board, side, -1) {
                    print("\(name(p)) \(v)")
                }
                let (steps, b) = variation(board, side, -1)
                print((["line"] + steps).joined(separator: " "))
                print("final B \(count(b, 66)) W \(count(b, 87))")
            }
        case "AUTOPLAY":
            auto(n, Int(a[1])!)
        case "RANDOM":
            auto(0, 0, n)
        case "MC":
            monteCarlo(n, Int(a[1])!)
        case "PERFT":
            print("perft \(n) \(perft(board, side, n))")
        case "DIVIDE":
            var total = 0
            for p in legal(board, side) {
                let v = perft(place(board, side, p), other(side), n - 1)
                print("\(name(p)) \(v)")
                total += v
            }
            print("total \(total)")
        default:
            break
        }
    }
}
let n = Int(readLine()!)!, engine = Othello()
for _ in 0..<n {
    engine.execute(readLine()!)
}
