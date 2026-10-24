import Foundation

struct Process {
    var maximum: [Int]
    var allocation: [Int]
    var created: Int
}
struct Waiting {
    var id: Int
    var vector: [Int]
    var since: Int
}
struct Event {
    var time: Int
    var kind: String
    var id: Int
    var vector: [Int]
    var wait: Int
}
struct State {
    var total: [Int] = []
    var available: [Int] = []
    var processes: [Int: Process] = [:]
    var queue: [Waiting] = []
    var history: [Event] = []
    var ids: [Int] { processes.keys.sorted() }
}
func vector(_ v: [Int]) -> String { "(" + v.map(String.init).joined(separator: ",") + ")" }
func list(_ ids: [Int]) -> String { ids.map { "P\($0)" }.joined(separator: " ") }
func le(_ a: [Int], _ b: [Int]) -> Bool { zip(a, b).allSatisfy { $0.0 <= $0.1 } }
func add(_ a: [Int], _ b: [Int]) -> [Int] { zip(a, b).map { $0.0 + $0.1 } }
func sub(_ a: [Int], _ b: [Int]) -> [Int] { zip(a, b).map { $0.0 - $0.1 } }
func need(_ p: Process) -> [Int] { sub(p.maximum, p.allocation) }
func check(_ state: State, detect: Bool, trace: Bool) -> (sequence: [Int], left: [Int]) {
    var work = state.available
    let idle = state.ids.filter { detect && state.processes[$0]!.allocation.allSatisfy { $0 == 0 } }
    var left = state.ids.filter { !idle.contains($0) }
    var sequence: [Int] = []
    let tag = detect ? "[detect]" : "[safety]"
    if trace { print("\(tag) start work=\(vector(work))" + (idle.isEmpty ? "" : " idle " + list(idle))) }
    while let index = left.firstIndex(where: { id in
        let request = detect ? state.queue.first(where: { $0.id == id })?.vector ?? Array(repeating: 0, count: work.count) : need(state.processes[id]!)
        return le(request, work)
    }) {
        let id = left.remove(at: index)
        sequence.append(id)
        work = add(work, state.processes[id]!.allocation)
        if trace { print("\(tag) P\(id) can finish, work=\(vector(work))") }
    }
    if trace && !left.isEmpty { print("\(tag) stuck work=\(vector(work)) remaining \(list(left))") }
    return (sequence, left)
}
struct CommandError: Error { let message: String }
final class Manager {
    var state = State()
    var snapshots: [String: State] = [:]
    var mode = "AVOID", policy = "ALLOC"
    var trace = false, automatic = false, time = 0
    let kinds = ["granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"]
    func fail(_ message: String) throws { throw CommandError(message: message) }
    func blocked(_ id: Int) -> Int? { state.queue.firstIndex { $0.id == id } }
    func reject(_ id: Int, _ v: [Int]) -> String? {
        if blocked(id) != nil { return "process P\(id) is blocked" }
        if v.allSatisfy({ $0 == 0 }) { return "zero vector" }
        let p = state.processes[id]!
        if !le(v, need(p)) { return "request exceeds need" }
        if mode == "ORDER", let last = p.allocation.lastIndex(where: { $0 > 0 }), v[...last].contains(where: { $0 > 0 }) { return "resource order violation" }
        return nil
    }
    func decision(_ id: Int, _ v: [Int], trace: Bool) -> (reason: String?, sequence: [Int]) {
        if !le(v, state.available) { return ("insufficient resources", []) }
        if mode != "AVOID" { return (nil, []) }
        var candidate = state
        candidate.available = sub(candidate.available, v)
        candidate.processes[id]!.allocation = add(candidate.processes[id]!.allocation, v)
        let result = check(candidate, detect: false, trace: trace)
        return (result.left.isEmpty ? nil : "unsafe state", result.sequence)
    }
    func record(_ kind: String, _ id: Int, _ v: [Int], wait: Int = 0) {
        state.history.append(Event(time: time, kind: kind, id: id, vector: v, wait: wait))
    }
    func allocate(_ id: Int, _ v: [Int]) {
        state.available = sub(state.available, v)
        state.processes[id]!.allocation = add(state.processes[id]!.allocation, v)
    }
    func retry() {
        var index = 0
        while index < state.queue.count {
            let q = state.queue[index]
            if decision(q.id, q.vector, trace: trace).reason != nil { index += 1; continue }
            allocate(q.id, q.vector)
            state.queue.remove(at: index)
            print("unblocked P\(q.id) \(vector(q.vector))")
            record("unblocked", q.id, q.vector, wait: time - q.since)
        }
    }
    func terminate(_ id: Int, kind: String, retry shouldRetry: Bool) {
        let p = state.processes.removeValue(forKey: id)!
        state.available = add(state.available, p.allocation)
        state.queue.removeAll { $0.id == id }
        print("\(kind) P\(id) released \(vector(p.allocation))")
        record(kind, id, p.allocation)
        if shouldRetry { retry() }
    }
    func sequences(_ limit: Int) {
        if state.ids.isEmpty { print("safe sequences: no processes"); return }
        var count = 0, rows: [String] = []
        func visit(_ path: [Int], _ left: [Int], _ work: [Int]) {
            if left.isEmpty {
                count += 1
                if rows.count < limit { rows.append(list(path)) }
                return
            }
            for id in left where le(need(state.processes[id]!), work) {
                visit(path + [id], left.filter { $0 != id }, add(work, state.processes[id]!.allocation))
            }
        }
        visit([], state.ids, state.available)
        print("safe sequences: \(count)")
        for row in rows { print(row) }
    }
    func victims() {
        let dead = check(state, detect: true, trace: false).left
        if dead.isEmpty { print("no deadlock"); return }
        var sets: [[Int]] = []
        for mask in 1..<(1 << dead.count) { sets.append(dead.enumerated().filter { mask & (1 << $0.offset) != 0 }.map { $0.element }) }
        func amount(_ ids: [Int]) -> Int { ids.reduce(0) { $0 + state.processes[$1]!.allocation.reduce(0, +) } }
        sets.sort {
            if $0.count != $1.count { return $0.count < $1.count }
            if amount($0) != amount($1) { return amount($0) < amount($1) }
            return $0.lexicographicallyPrecedes($1)
        }
        for ids in sets {
            var candidate = state
            for id in ids {
                candidate.available = add(candidate.available, candidate.processes[id]!.allocation)
                candidate.processes.removeValue(forKey: id)
                candidate.queue.removeAll { $0.id == id }
            }
            if check(candidate, detect: true, trace: false).left.isEmpty { print("victims: \(list(ids))"); return }
        }
    }
    func graph(resource: Bool) throws {
        if resource && state.total.contains(where: { $0 != 1 }) { try fail("not single-instance") }
        func type(_ j: Int) -> String { String(UnicodeScalar(65 + j)!) }
        var edges: [Int: [(Int, Int)]] = Dictionary(uniqueKeysWithValues: state.ids.map { ($0, []) })
        if resource {
            for j in state.total.indices {
                for id in state.ids where state.processes[id]!.allocation[j] > 0 { print("assign \(type(j)) -> P\(id)") }
            }
            for id in state.ids {
                if let index = blocked(id) {
                    for j in state.total.indices where state.queue[index].vector[j] > 0 {
                        print("request P\(id) -> \(type(j))")
                        for other in state.ids where state.processes[other]!.allocation[j] > 0 { edges[id]!.append((j, other)) }
                    }
                }
            }
            for id in state.ids {
                let request = blocked(id).map { state.queue[$0].vector } ?? Array(repeating: 0, count: state.total.count)
                let n = need(state.processes[id]!)
                for j in state.total.indices where n[j] > 0 && request[j] == 0 { print("claim P\(id) -> \(type(j))") }
            }
        } else {
            var count = 0
            for id in state.ids {
                guard let index = blocked(id) else { continue }
                for other in state.ids where other != id {
                    let labels = state.total.indices.filter { state.queue[index].vector[$0] > state.available[$0] && state.processes[other]!.allocation[$0] > 0 }
                    if labels.isEmpty { continue }
                    count += 1
                    print("P\(id) -> P\(other) on \(labels.map(type).joined(separator: ","))")
                    edges[id]!.append((0, other))
                }
            }
            if count == 0 { print("no wait edges") }
        }
        var any = false
        for start in state.ids {
            func visit(_ at: Int, _ seen: [Int], _ path: [String]) {
                for (kind, next) in edges[at]! {
                    let text = path + (resource ? [type(kind)] : []) + ["P\(next)"]
                    if next == start && (resource || seen.count >= 2) { print("cycle: \(text.joined(separator: " -> "))"); any = true }
                    else if next > start && !seen.contains(next) { visit(next, seen + [next], text) }
                }
            }
            visit(start, [start], ["P\(start)"])
        }
        if !any { print("no cycles") }
    }
    func table() {
        let widths = state.total.map { String($0).count }
        func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
            let spaces = String(repeating: " ", count: max(0, width - text.count))
            return left ? spaces + text : text + spaces
        }
        func form(_ v: [Int]) -> String { v.enumerated().map { pad(String($0.element), widths[$0.offset], left: true) }.joined(separator: " ") }
        let names = widths.enumerated().map { pad(String(UnicodeScalar(65 + $0.offset)!), $0.element, left: true) }.joined(separator: " ")
        let columns = [10, 3, 4, 7].map { max($0, names.count) }
        func row(_ heading: String, _ cells: [String]) {
            var text = pad(heading, 9)
            for i in 0..<4 { text += "  " + pad(i < cells.count ? cells[i] : "", columns[i]) }
            while text.last == " " { text.removeLast() }
            print(text)
        }
        row("Process", ["Allocation", "Max", "Need", "Request"])
        row("", Array(repeating: names, count: 4))
        for id in state.ids {
            let p = state.processes[id]!
            let request = blocked(id).map { state.queue[$0].vector } ?? Array(repeating: 0, count: widths.count)
            row("P\(id)", [form(p.allocation), form(p.maximum), form(need(p)), form(request)])
        }
        row("Available", [form(state.available)])
        row("Total", [form(state.total)])
        print("blocked queue: " + (state.queue.isEmpty ? "empty" : state.queue.map { "P\($0.id) \(vector($0.vector)) since t=\($0.since)" }.joined(separator: ", ")))
    }
    func execute(_ a: [String]) throws {
        let cmd = a[0]
        switch cmd {
        case "RESOURCES":
            let v = a.dropFirst().map { Int($0)! }
            state = State(total: v, available: v)
            print("resources \(vector(v))")
        case "MODE", "POLICY", "TRACE", "AUTODETECT":
            switch cmd {
            case "MODE": mode = a[1]
            case "POLICY": policy = a[1]
            case "TRACE": trace = a[1] == "ON"
            default: automatic = a[1] == "ON"
            }
            print("\(cmd.lowercased()) \(a[1])")
        case "SNAPSHOT": snapshots[a[1]] = state; print("saved \(a[1])")
        case "RESTORE":
            guard let saved = snapshots[a[1]] else { try fail("unknown snapshot \(a[1])"); return }
            state = saved; print("restored \(a[1])")
        case "STATE": table()
        case "GRAPH", "WAITGRAPH": try graph(resource: cmd == "GRAPH")
        case "VICTIMS": victims()
        case "SEQUENCES": sequences(Int(a[1])!)
        case "SAFE":
            if state.processes.isEmpty { print("safe: no processes") }
            else {
                let result = check(state, detect: false, trace: trace)
                print(result.left.isEmpty ? "safe: \(list(result.sequence))" : "unsafe: \(list(result.left)) cannot finish")
            }
        case "DETECT":
            let dead = check(state, detect: true, trace: trace).left
            print(dead.isEmpty ? "no deadlock" : "deadlocked: \(list(dead))")
        case "RECOVER":
            var count = 0
            while true {
                let dead = check(state, detect: true, trace: trace).left
                if dead.isEmpty { break }
                if a.count > 1 {
                    for id in dead { terminate(id, kind: "aborted", retry: false) }
                    count += dead.count; retry(); break
                }
                func rank(_ id: Int) -> Int {
                    let p = state.processes[id]!
                    switch policy {
                    case "ALLOC": return -p.allocation.reduce(0, +)
                    case "NEED": return need(p).reduce(0, +)
                    default: return p.created
                    }
                }
                let victim = dead.max { rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1) }!
                terminate(victim, kind: "aborted", retry: true); count += 1
            }
            print(count == 0 ? "no deadlock" : "recovered: \(count) aborted")
        case "DEFICIT":
            var values: [String] = []
            for j in state.total.indices {
                let bound = state.processes.values.reduce(0) { $0 + need($1)[j] }
                var value = "-"
                for x in 0...bound {
                    var candidate = state; candidate.available[j] += x
                    if check(candidate, detect: false, trace: false).left.isEmpty { value = String(x); break }
                }
                values.append(value)
            }
            print("deficit: (\(values.joined(separator: ",")))")
        case "HISTORY":
            let events = state.history.filter { a.count == 1 || a[1] == $0.kind || a[1] == String($0.id) }
            if events.isEmpty { print("no events") }
            for e in events { print("t=\(e.time) \(e.kind) P\(e.id) \(vector(e.vector))" + (e.kind == "unblocked" ? " waited \(e.wait)" : "")) }
        case "STATS":
            for j in state.total.indices {
                let used = state.total[j] - state.available[j], percent = used * 1000 / state.total[j]
                let requested = state.queue.reduce(0) { $0 + $1.vector[j] }
                print("\(UnicodeScalar(65 + j)!): allocated \(used)/\(state.total[j]) (\(percent / 10).\(percent % 10)%), requested \(requested)")
            }
            print("events: " + kinds.map { kind in "\(kind) \(state.history.filter { $0.kind == kind }.count)" }.joined(separator: ", "))
            let waits = state.history.filter { $0.kind == "unblocked" }, total = state.history.filter { $0.kind == "unblocked" }.reduce(0) { $0 + $1.wait }
            if waits.isEmpty { print("waits: none") }
            else {
                let average = total * 100 / waits.count
                print("waits: \(waits.count) unblocked, total \(total), average \(average / 100).\(String(format: "%02d", average % 100))")
            }
        default: try processCommand(a)
        }
    }
    func processCommand(_ a: [String]) throws {
        let cmd = a[0], resource = ["ADD", "REMOVE"].contains(a[0])
        let hasVector = resource || ["PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE"].contains(cmd)
        let id = resource ? 0 : Int(a[1])!
        let v = hasVector ? a.dropFirst(resource ? 1 : 2).map { Int($0)! } : Array(repeating: 0, count: state.total.count)
        if hasVector && v.count != state.total.count { try fail("wrong vector length") }
        if !resource && cmd != "PROCESS" && state.processes[id] == nil { try fail("unknown process P\(id)") }
        if cmd == "PROCESS" {
            if state.processes[id] != nil { try fail("duplicate process P\(id)") }
            if !le(v, state.total) { try fail("max exceeds total") }
            state.processes[id] = Process(maximum: v, allocation: Array(repeating: 0, count: v.count), created: time)
            print("process P\(id) max \(vector(v))"); return
        }
        if cmd == "REQUEST" || cmd == "WHATIF" {
            if let reason = reject(id, v) {
                if cmd == "REQUEST" { try fail(reason) }
                print("whatif P\(id) \(vector(v)): rejected (\(reason))"); return
            }
            let result = decision(id, v, trace: trace)
            if cmd == "WHATIF" {
                if let reason = result.reason { print("whatif P\(id) \(vector(v)): blocked (\(reason))") }
                else { print("whatif P\(id) \(vector(v)): granted" + (mode == "AVOID" ? ", safe sequence \(list(result.sequence))" : "")) }
            } else if let reason = result.reason {
                state.queue.append(Waiting(id: id, vector: v, since: time))
                print("blocked P\(id) \(vector(v)): \(reason)"); record("blocked", id, v)
                if automatic {
                    let dead = check(state, detect: true, trace: trace).left
                    if !dead.isEmpty { print("deadlock detected: \(list(dead))") }
                }
            } else { allocate(id, v); print("granted P\(id) \(vector(v))"); record("granted", id, v) }
            return
        }
        if !resource && cmd != "ABORT" && cmd != "CANCEL" && blocked(id) != nil { try fail("process P\(id) is blocked") }
        switch cmd {
        case "FINISH", "ABORT": terminate(id, kind: cmd == "FINISH" ? "finished" : "aborted", retry: true)
        case "CANCEL":
            guard let index = blocked(id) else { try fail("process P\(id) is not blocked"); return }
            let q = state.queue.remove(at: index)
            print("cancelled P\(id) \(vector(q.vector))"); record("cancelled", id, q.vector)
        case "MAXGRANT":
            var answer = Array(repeating: 0, count: state.total.count)
            for j in answer.indices {
                let bound = need(state.processes[id]!)[j]
                if bound == 0 { continue }
                for x in stride(from: bound, through: 1, by: -1) {
                    var request = Array(repeating: 0, count: answer.count); request[j] = x
                    if reject(id, request) == nil && decision(id, request, trace: false).reason == nil { answer[j] = x; break }
                }
            }
            print("maxgrant P\(id): \(vector(answer))")
        case "CLAIM":
            if !le(state.processes[id]!.allocation, v) { try fail("claim below allocation") }
            if !le(v, state.total) { try fail("max exceeds total") }
            var candidate = state; candidate.processes[id]!.maximum = v
            if mode == "AVOID" && !check(candidate, detect: false, trace: trace).left.isEmpty { try fail("claim makes state unsafe") }
            state.processes[id]!.maximum = v
            print("claim P\(id) max \(vector(v))"); retry()
        default:
            if v.allSatisfy({ $0 == 0 }) { try fail("zero vector") }
            if cmd == "RELEASE" {
                if !le(v, state.processes[id]!.allocation) { try fail("release exceeds allocation") }
                state.processes[id]!.allocation = sub(state.processes[id]!.allocation, v)
                state.available = add(state.available, v)
                print("released P\(id) \(vector(v))"); record("released", id, v); retry()
            } else if cmd == "ADD" {
                state.total = add(state.total, v); state.available = add(state.available, v)
                print("added \(vector(v)) total \(vector(state.total))"); retry()
            } else {
                if !le(v, state.available) { try fail("remove exceeds available") }
                let total = sub(state.total, v)
                if total.contains(0) { try fail("total must stay positive") }
                if state.processes.values.contains(where: { !le($0.maximum, total) }) { try fail("max exceeds total") }
                var candidate = state; candidate.available = sub(candidate.available, v)
                if mode == "AVOID" && !check(candidate, detect: false, trace: trace).left.isEmpty { try fail("removal makes state unsafe") }
                state.total = total; state.available = candidate.available
                print("removed \(vector(v)) total \(vector(total))")
            }
        }
    }
}
let count = Int(readLine()!)!
let manager = Manager()
for time in 1...count {
    manager.time = time
    do { try manager.execute(readLine()!.split(separator: " ").map(String.init)) }
    catch let error as CommandError { print("error: \(error.message)") }
    catch { fatalError("Unexpected internal error") }
}
