import Foundation

let directions: [UInt8] = Array("udlr".utf8)
let levelCharacters = Array("#-.$*@+".utf8)
func string(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
func lower(_ c: UInt8) -> UInt8 { c >= 65 && c <= 90 ? c + 32 : c }
func upper(_ c: UInt8) -> UInt8 { c >= 97 && c <= 122 ? c - 32 : c }
func isPush(_ c: UInt8) -> Bool { c >= 65 && c <= 90 }
func pushCount(_ letters: [UInt8]) -> Int { letters.filter(isPush).count }
func count(_ flags: [Bool]) -> Int { flags.filter { $0 }.count }
func moveBox(_ boxes: [Int], _ from: Int, _ to: Int) -> [Int] {
    boxes.map { $0 == from ? to : $0 }.sorted()
}
func decode(_ word: String, allowed: [UInt8]) -> [UInt8]? {
    let bytes = Array(word.utf8)
    var result: [UInt8] = [], i = 0
    while i < bytes.count {
        let start = i
        var n = 0
        while i < bytes.count && bytes[i] >= 48 && bytes[i] <= 57 {
            if i - start < 2 { n = n * 10 + Int(bytes[i] - 48) }
            i += 1
        }
        if i - start > 2 || (i > start && bytes[start] == 48) || i == bytes.count { return nil }
        guard allowed.contains(bytes[i]) else { return nil }
        result += Array(repeating: bytes[i], count: i == start ? 1 : n)
        i += 1
    }
    return result
}
func encode(_ row: String) -> String {
    let bytes = Array(row.utf8)
    var result = "", i = 0
    while i < bytes.count {
        var j = i + 1
        while j < bytes.count && bytes[j] == bytes[i] { j += 1 }
        if j - i > 1 { result += String(j - i) }
        result += string([bytes[i]])
        i = j
    }
    return result
}
func turnMap(_ kind: String) -> [UInt8]? {
    switch kind {
    case "ROT90": return Array("rlud".utf8)
    case "ROT180": return Array("durl".utf8)
    case "ROT270": return Array("lrdu".utf8)
    case "FLIPH": return Array("udrl".utf8)
    case "FLIPV": return Array("dulr".utf8)
    default: return nil
    }
}
func turn(_ letters: [UInt8], _ kind: String) -> [UInt8] {
    let map = turnMap(kind)!
    return letters.map { c in
        let d = map[directions.firstIndex(of: lower(c))!]
        return isPush(c) ? upper(d) : d
    }
}
func schema(_ command: String) -> String? {
    switch command {
    case "IMPORT": return "t"
    case "MOVE", "CHECK": return "s"
    case "PUSH": return "nnd"
    case "BRING": return "nnnn"
    case "PATH": return "nn"
    case "UNDO", "REDO", "SOLVE", "HINT": return "n"
    case "SAVE", "RESTORE": return "a"
    case "TRANSFORM": return "f"
    case "VALID", "INFO", "SHOW", "EXPORT", "RESET", "STATUS", "HISTORY", "BOXES", "REACH", "DEADSQUARES", "DEADLOCK", "BOUND", "PLAY": return ""
    default: return nil
    }
}
func validArgument(_ kind: Character, _ word: String) -> Bool {
    let b = Array(word.utf8)
    switch kind {
    case "n": return !b.isEmpty && b.count <= 6 && b.allSatisfy { $0 >= 48 && $0 <= 57 } && (b.count == 1 || b[0] != 48)
    case "s": return decode(word, allowed: Array("udlrUDLR".utf8)) != nil
    case "d": return b.count == 1 && directions.contains(b[0])
    case "a": return !b.isEmpty && b.count <= 8 && b.allSatisfy { $0 >= 97 && $0 <= 122 }
    case "f": return turnMap(word) != nil
    default: return true
    }
}
struct Position: Equatable {
    var player: Int
    var boxes: [Int]
}
struct CommandError: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}
struct Level {
    var h: Int, w: Int
    var walls: [Bool], goals: [Bool], inside: [Bool], dead: [Bool]
    var goalCells: [Int], distances: [[Int]] = []
    var reason: String? = nil
    var size: Int { h * w }
    var offsets: [Int] { [-w, w, -1, 1] }

    func offset(_ d: UInt8) -> Int { offsets[directions.firstIndex(of: lower(d))!] }

    func interior(_ p: Int) -> Bool { p >= 0 && p < size && inside[p] }

    func cell(_ p: Int) -> String { "\(p / w + 1) \(p % w + 1)" }
    static func build(_ rows: [String]) -> (Level, Position) {
        let h = rows.count, w = rows[0].utf8.count
        let bytes = rows.flatMap { Array($0.utf8) }
        let walls = bytes.map { $0 == 35 }
        let goals = bytes.map { [UInt8(46),42,43].contains($0) }
        let players = bytes.indices.filter { bytes[$0] == 64 || bytes[$0] == 43 }
        let boxes = bytes.indices.filter { bytes[$0] == 36 || bytes[$0] == 42 }
        let goalCells = bytes.indices.filter { goals[$0] }
        var level = Level(h: h, w: w, walls: walls, goals: goals,
                          inside: Array(repeating: false, count: h*w),
                          dead: Array(repeating: false, count: h*w), goalCells: goalCells)
        if players.count == 1 {
            var queue = [players[0]], head = 0
            level.inside[players[0]] = true
            while head < queue.count {
                let p = queue[head], r = p / w, c = p % w
                head += 1
                for (dr, dc) in [(-1,0),(1,0),(0,-1),(0,1)] {
                    let nr = r + dr, nc = c + dc
                    if nr >= 0 && nr < h && nc >= 0 && nc < w {
                        let q = nr*w+nc
                        if !walls[q] && !level.inside[q] { level.inside[q] = true; queue.append(q) }
                    }
                }
            }
        }
        if players.count != 1 { level.reason = "players \(players.count)" }
        else if boxes.isEmpty { level.reason = "no boxes" }
        else if boxes.count != goalCells.count { level.reason = "boxes \(boxes.count) goals \(goalCells.count)" }
        else if let p = (0..<h*w).first(where: { level.inside[$0] && ($0/w == 0 || $0/w == h-1 || $0%w == 0 || $0%w == w-1) }) { level.reason = "open \(level.cell(p))" }
        else if let p = (0..<h*w).first(where: { (goals[$0] || boxes.contains($0)) && !level.inside[$0] }) { level.reason = "outside \(level.cell(p))" }
        if level.reason == nil { level.analyze() }
        return (level, Position(player: players.first ?? 0, boxes: boxes))
    }

    mutating func analyze() {
        goalCells = (0..<size).filter { goals[$0] }
        distances = goalCells.map { goal in
            var dist = Array(repeating: -1, count: size), queue = [goal], head = 0
            dist[goal] = 0
            while head < queue.count {
                let q = queue[head]
                head += 1
                for delta in offsets {
                    let b = q - delta
                    if interior(b) && interior(b-delta) && dist[b] < 0 { dist[b] = dist[q]+1; queue.append(b) }
                }
            }
            return dist
        }
        dead = (0..<size).map { p in inside[p] && distances.allSatisfy { $0[p] < 0 } }
    }

    func reach(_ player: Int, _ boxes: [Int]) -> [Bool] {
        var seen = Array(repeating: false, count: size), queue = [player], head = 0
        seen[player] = true
        while head < queue.count {
            let q = queue[head]
            head += 1
            for delta in offsets {
                let p = q+delta
                if interior(p) && !seen[p] && !boxes.contains(p) { seen[p] = true; queue.append(p) }
            }
        }
        return seen
    }

    func representative(_ player: Int, _ boxes: [Int]) -> Int { reach(player,boxes).firstIndex(of: true)! }

    func path(_ player: Int, _ target: Int, _ boxes: [Int]) -> [UInt8] {
        var from = Array<(Int, UInt8)?>(repeating: nil, count: size), queue = [player], head = 0
        while head < queue.count {
            let q = queue[head]
            head += 1
            for d in 0..<4 {
                let p = q + offsets[d]
                if interior(p) && p != player && !boxes.contains(p) && from[p] == nil {
                    from[p] = (q,directions[d])
                    queue.append(p)
                }
            }
        }
        var result: [UInt8] = [], p = target
        while p != player {
            let (q,d) = from[p]!
            result.append(d)
            p = q
        }
        return Array(result.reversed())
    }

    func step(_ pos: Position, _ direction: UInt8) -> (Position, UInt8, String?) {
        let d = lower(direction), delta = offset(d), p = pos.player+delta
        if walls[p] { return (pos,d,"wall") }
        if pos.boxes.contains(p) {
            let dest = p+delta
            if walls[dest] || pos.boxes.contains(dest) { return (pos,d,"blocked") }
            return (Position(player: p, boxes: moveBox(pos.boxes,p,dest)),upper(d),nil)
        }
        return (Position(player: p, boxes: pos.boxes),d,nil)
    }

    func pushable(_ b: Int, _ d: Int, _ boxes: [Int], _ reachable: [Bool]) -> Bool {
        let delta = offsets[d]
        return reachable[b-delta] && interior(b+delta) && !boxes.contains(b+delta)
    }

    func frozen(_ b: Int, _ boxes: [Int], _ assumed: Set<Int> = []) -> Bool {
        func axis(_ sides: [Int]) -> Bool {
            if sides.contains(where: { walls[$0] || assumed.contains($0) }) || sides.allSatisfy({ dead[$0] }) { return true }
            let extended = assumed.union([b])
            return sides.contains { boxes.contains($0) && frozen($0,boxes,extended) }
        }
        return axis([b-1,b+1]) && axis([b-w,b+w])
    }

    func onGoals(_ boxes: [Int]) -> Int { boxes.filter { goals[$0] }.count }

    func solved(_ boxes: [Int]) -> Bool { onGoals(boxes) == boxes.count }

    func render(_ pos: Position, deadMap: Bool = false) -> [String] {
        let bytes: [UInt8] = (0..<size).map { p in
            if walls[p] { return 35 }
            if deadMap { return goals[p] ? 46 : (dead[p] ? 120 : 45) }
            if p == pos.player { return goals[p] ? 43 : 64 }
            if pos.boxes.contains(p) { return goals[p] ? 42 : 36 }
            return goals[p] ? 46 : 45
        }
        return (0..<h).map { string(Array(bytes[$0*w..<($0+1)*w])) }
    }

    func mapCell(_ p: Int, _ kind: String) -> Int {
        let r = p/w, c = p%w
        switch kind {
        case "ROT90": return c*h+h-1-r
        case "ROT180": return (h-1-r)*w+w-1-c
        case "ROT270": return (w-1-c)*h+r
        case "FLIPH": return r*w+w-1-c
        default: return (h-1-r)*w+c
        }
    }

    func mapPosition(_ pos: Position, _ kind: String) -> Position {
        Position(player: mapCell(pos.player,kind), boxes: pos.boxes.map { mapCell($0,kind) }.sorted())
    }

    func transformed(_ kind: String) -> Level {
        var result = self
        if kind == "ROT90" || kind == "ROT270" { result.h = w; result.w = h }
        for p in 0..<size {
            let q = mapCell(p,kind)
            result.walls[q] = walls[p]
            result.goals[q] = goals[p]
            result.inside[q] = inside[p]
        }
        result.analyze()
        return result
    }
}
// The representative merges positions with the same reachable player region.
struct SearchState: Hashable {
    let boxes: [Int]
    let representative: Int
}
struct SearchNode {
    let state: SearchState
    let parent: Int?
    let box: Int
    let direction: Int
}
struct SearchResult {
    let outcome: String
    let expanded: Int
    let states: Int
    var notation: [UInt8] = []
}
func search(_ level: Level, _ start: Position, fixed: [Int] = [], target: Int? = nil, pruning: Bool, limit: Int?) -> SearchResult {
    let first = SearchState(boxes: start.boxes, representative: level.representative(start.player,start.boxes))
    var nodes = [SearchNode(state: first,parent: nil,box: 0,direction: 0)]
    var known: Set<SearchState> = [first], expanded = 0
    // Discovery order is the BFS queue, and its cursor counts expanded states.
    while expanded < nodes.count {
        if let limit, expanded == limit { return SearchResult(outcome: "limit", expanded: expanded, states: nodes.count) }
        let parent = expanded, state = nodes[parent].state
        expanded += 1
        let reachable = level.reach(state.representative,state.boxes)
        for b in state.boxes where !fixed.contains(b) {
            for d in 0..<4 {
                if !level.pushable(b,d,state.boxes,reachable) { continue }
                let dest = b+level.offsets[d], boxes = moveBox(state.boxes,b,dest)
                if pruning && (level.dead[dest] || boxes.contains { !level.goals[$0] && level.frozen($0,boxes) }) { continue }
                let next = SearchState(boxes: boxes, representative: level.representative(b,boxes))
                if !known.insert(next).inserted { continue }
                nodes.append(SearchNode(state: next,parent: parent,box: b,direction: d))
                let found = target.map { dest == $0 } ?? level.solved(boxes)
                if found {
                    var pushes: [(Int,Int)] = [], i = nodes.count-1
                    while let p = nodes[i].parent { pushes.append((nodes[i].box,nodes[i].direction)); i = p }
                    var pos = start, notation: [UInt8] = []
                    for (box,direction) in pushes.reversed() {
                        let delta = level.offsets[direction]
                        notation += level.path(pos.player,box-delta,pos.boxes)
                        notation.append(upper(directions[direction]))
                        pos = Position(player: box,boxes: moveBox(pos.boxes,box,box+delta))
                    }
                    return SearchResult(outcome: "found",expanded: expanded,states: nodes.count,notation: notation)
                }
            }
        }
    }
    return SearchResult(outcome: "no solution",expanded: expanded,states: nodes.count)
}
struct Snapshot {
    var position: Position
    var history: [UInt8]
}
struct Solution {
    var position: Position
    var notation: [UInt8]
}
final class Game {
    var level: Level, initial: Position, current: Position
    var history: [UInt8] = [], redo: [UInt8] = []
    var snapshots: [String:Snapshot] = [:]
    var solution: Solution? = nil
    var output: [String] = []
    init(_ rows: [String]) {
        let (l,p) = Level.build(rows)
        level = l
        initial = p
        current = p
    }

    func load(_ rows: [String]) {
        let (l,p) = Level.build(rows)
        level = l
        initial = p
        current = p
        history = []
        redo = []
        snapshots = [:]
        solution = nil
    }

    func emit(_ line: String) { output.append(line) }

    func progress(_ boxes: [Int]) -> String {
        let n = level.onGoals(boxes)
        return "goals \(n)/\(boxes.count)" + (n == boxes.count ? " solved" : "")
    }

    func simulate(_ steps: [UInt8]) -> (Position,[UInt8],String?) {
        var pos = current, letters: [UInt8] = []
        for d in steps {
            let (next,letter,error) = level.step(pos,d)
            if let error { return (pos,letters,"step \(letters.count+1) \(error)") }
            pos = next
            letters.append(letter)
        }
        return (pos,letters,nil)
    }
    @discardableResult func take(_ steps: [UInt8]) -> ([UInt8],String?) {
        let (pos,letters,error) = simulate(steps)
        current = pos
        history += letters
        if !letters.isEmpty { redo = [] }
        return (letters,error)
    }

    func cellArgument(_ a: [String], _ i: Int) -> Int { (Int(a[i])!-1)*level.w+Int(a[i+1])!-1 }

    func assignment() -> (Int,[Int])? {
        var best: (Int,[Int])? = nil
        func visit(_ order: [Int], _ used: Set<Int>, _ total: Int) {
            let i = order.count
            if i == current.boxes.count {
                if best == nil || total < best!.0 { best = (total,order) }
                return
            }
            // Ascending goals enumerate assignments lexicographically; retain ties.
            for g in level.goalCells.indices where !used.contains(g) {
                let d = level.distances[g][current.boxes[i]]
                if d >= 0 { visit(order+[g],used.union([g]),total+d) }
            }
        }
        visit([],[],0)
        return best
    }

    func searchSolution(_ limit: Int) -> (String,[UInt8]?) {
        if level.solved(current.boxes) { return ("already solved",nil) }
        let result = search(level,current,pruning: true,limit: limit)
        let counts = "expanded \(result.expanded) states \(result.states)"
        if result.outcome != "found" { return ("\(result.outcome) \(counts)",nil) }
        return ("solution pushes \(pushCount(result.notation)) moves \(result.notation.count) \(counts)",result.notation)
    }

    func execute(_ words: [String], _ rows: [String]) throws {
        let name = words[0], a = Array(words.dropFirst())
        if name == "LOAD" {
            let w = Int(a[1])!
            if let i = rows.firstIndex(where: { $0.utf8.count != w || !$0.utf8.allSatisfy { levelCharacters.contains($0) } }) { throw CommandError("bad row \(i+1)") }
            load(rows)
            emit("loaded \(rows.count)x\(w)")
            return
        }
        guard let kinds = schema(name) else { throw CommandError("unknown command \(name)") }
        guard a.count == kinds.count && zip(kinds,a).allSatisfy({ validArgument($0.0,$0.1) }) else { throw CommandError("bad arguments") }
        if name == "IMPORT" {
            let parts = a[0].components(separatedBy: "|")
            var imported: [String] = []
            for part in parts {
                guard let decoded = decode(part,allowed: levelCharacters) else { throw CommandError("bad level") }
                imported.append(string(decoded))
            }
            let w = imported[0].utf8.count
            guard imported.count <= 10 && w >= 1 && w <= 10 && imported.allSatisfy({ $0.utf8.count == w }) else { throw CommandError("bad level") }
            load(imported)
            emit("loaded \(imported.count)x\(w)")
            return
        }
        if name == "VALID" {
            emit(level.reason.map { "invalid \($0)" } ?? "valid")
            return
        }
        guard level.reason == nil else { throw CommandError("invalid level") }
        let cells = name == "BRING" ? 2 : (["PATH","PUSH"].contains(name) ? 1 : 0)
        for i in 0..<cells {
            let r = Int(a[2*i])!, c = Int(a[2*i+1])!
            guard r >= 1 && r <= level.h && c >= 1 && c <= level.w else { throw CommandError("bad value") }
        }
        if ["UNDO","REDO","SOLVE","HINT"].contains(name) {
            let n = Int(a[0])!
            guard n >= 1 && (!["SOLVE","HINT"].contains(name) || n <= 100000) else { throw CommandError("bad value") }
        }
        switch name {
        case "INFO": emit("size \(level.h)x\(level.w) walls \(count(level.walls)) cells \(count(level.inside)) boxes \(current.boxes.count) dead \(count(level.dead))")
        case "SHOW": output += level.render(current)
        case "EXPORT": emit("level " + level.render(current).map(encode).joined(separator: "|"))
        case "MOVE":
            let (letters,error) = take(decode(a[0],allowed: Array("udlrUDLR".utf8))!)
            if !letters.isEmpty { emit("moved \(string(letters))") }
            if let error { throw CommandError(error) }
        case "PUSH":
            let b = cellArgument(a,0), d = Array(a[2].utf8)[0], delta = level.offset(d)
            guard current.boxes.contains(b) else { throw CommandError("no box") }
            guard level.interior(b+delta) && !current.boxes.contains(b+delta) else { throw CommandError("blocked") }
            guard level.reach(current.player,current.boxes)[b-delta] else { throw CommandError("unreachable") }
            let path = level.path(current.player,b-delta,current.boxes) + [d]
            emit("pushed \(string(take(path).0))")
        case "BRING":
            let b = cellArgument(a,0), target = cellArgument(a,2)
            guard current.boxes.contains(b) else { throw CommandError("no box") }
            if b == target {
                emit("brought 0")
                break
            }
            let fixed = current.boxes.filter { $0 != b }
            let result = search(level,current,fixed: fixed,target: target,pruning: false,limit: nil)
            guard result.outcome == "found" else { throw CommandError("no route") }
            take(result.notation)
            emit("brought \(pushCount(result.notation)) \(string(result.notation))")
        case "PATH":
            let target = cellArgument(a,0)
            guard level.reach(current.player,current.boxes)[target] else { throw CommandError("unreachable") }
            let path = level.path(current.player,target,current.boxes), letters = take(path).0
            emit(letters.isEmpty ? "path 0" : "path \(letters.count) \(string(letters))")
        case "UNDO":
            guard !history.isEmpty else { throw CommandError("nothing to undo") }
            let n = min(Int(a[0])!,history.count)
            for _ in 0..<n {
                let letter = history.removeLast(), d = lower(letter), delta = level.offset(d), p = current.player
                if isPush(letter) { current.boxes = moveBox(current.boxes,p+delta,p) }
                current.player = p-delta
                redo.append(d)
            }
            emit("undone \(n)")
        case "REDO":
            guard !redo.isEmpty else { throw CommandError("nothing to redo") }
            let n = min(Int(a[0])!,redo.count)
            for _ in 0..<n {
                let d = redo.removeLast()
                let (pos,letter,_) = level.step(current,d)
                current = pos
                history.append(letter)
            }
            emit("redone \(n)")
        case "RESET":
            current = initial
            history = []
            redo = []
            emit("reset")
        case "STATUS": emit("moves \(history.count) pushes \(pushCount(history)) \(progress(current.boxes))")
        case "HISTORY": emit(history.isEmpty ? "history 0" : "history \(history.count) \(string(history))")
        case "BOXES":
            emit("boxes \(current.boxes.count)")
            let reachable = level.reach(current.player,current.boxes)
            for b in current.boxes {
                let distance = level.distances.map { $0[b] }.filter { $0 >= 0 }.min().map(String.init) ?? "dead"
                let dirs = (0..<4).filter { level.pushable(b,$0,current.boxes,reachable) }.map { directions[$0] }
                emit("box \(level.cell(b)) \(distance) \(dirs.isEmpty ? "-" : string(dirs))")
            }
        case "REACH":
            let reachable = level.reach(current.player,current.boxes)
            emit("reach \(count(reachable)) first \(level.cell(reachable.firstIndex(of: true)!))")
        case "DEADSQUARES":
            emit("dead \(count(level.dead))")
            output += level.render(current,deadMap: true)
        case "DEADLOCK":
            if let b = current.boxes.first(where: { level.dead[$0] }) { emit("deadlock dead \(level.cell(b))") }
            else if let b = current.boxes.first(where: { !level.goals[$0] && level.frozen($0,current.boxes) }) { emit("deadlock frozen \(level.cell(b))") }
            else { emit("no deadlock") }
        case "BOUND":
            if let (total,order) = assignment() {
                emit("bound \(total)")
                for (i,g) in order.enumerated() {
                    let b = current.boxes[i]
                    emit("box \(level.cell(b)) goal \(level.cell(level.goalCells[g])) pushes \(level.distances[g][b])")
                }
            } else { emit("bound none") }
        case "SAVE":
            snapshots[a[0]] = Snapshot(position: current,history: history)
            emit("saved \(a[0]) moves \(history.count)")
        case "RESTORE":
            guard let snapshot = snapshots[a[0]] else { throw CommandError("no snapshot \(a[0])") }
            current = snapshot.position
            history = snapshot.history
            redo = []
            emit("restored \(a[0]) moves \(history.count)")
        case "CHECK":
            let (pos,letters,error) = simulate(decode(a[0],allowed: Array("udlrUDLR".utf8))!)
            if let error { emit("check fail \(error)") }
            else { emit("check ok moves \(letters.count) pushes \(pushCount(letters)) \(progress(pos.boxes))") }
        case "SOLVE", "HINT":
            let (summary,notation) = searchSolution(Int(a[0])!)
            if name == "SOLVE" {
                solution = notation.map { Solution(position: current,notation: $0) }
                emit(summary)
                if let notation { emit(string(notation)) }
            } else if let notation {
                let end = notation.firstIndex(where: isPush)! + 1, part = Array(notation[..<end])
                take(part)
                emit("hint \(string(part))")
            } else { emit(summary) }
        case "PLAY":
            guard let solution, solution.position == current else { throw CommandError("no solution") }
            take(solution.notation)
            emit("played pushes \(pushCount(solution.notation)) moves \(solution.notation.count)")
        case "TRANSFORM":
            let kind = a[0], old = level
            level = old.transformed(kind)
            initial = old.mapPosition(initial,kind)
            current = old.mapPosition(current,kind)
            history = turn(history,kind)
            redo = turn(redo,kind)
            snapshots = snapshots.mapValues { Snapshot(position: old.mapPosition($0.position,kind),history: turn($0.history,kind)) }
            if let stored = solution { solution = Solution(position: old.mapPosition(stored.position,kind),notation: turn(stored.notation,kind)) }
            emit("transformed \(level.h)x\(level.w)")
        default: break
        }
    }
}
let height = Int(readLine()!.split(separator: " ")[0])!
let initialRows = (0..<height).map { _ in readLine()! }
let game = Game(initialRows)
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    let words = readLine()!.components(separatedBy: " ")
    let rows = words[0] == "LOAD" ? (0..<Int(words[1])!).map { _ in readLine()! } : []
    do { try game.execute(words,rows) }
    catch let error as CommandError { game.emit("error: \(error.reason)") }
    catch { fatalError("Unexpected error") }
}
print(game.output.joined(separator: "\n"))
