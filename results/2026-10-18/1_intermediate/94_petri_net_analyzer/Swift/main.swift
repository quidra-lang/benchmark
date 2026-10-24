import Foundation

struct InputError: Error { let reason: String }
func bad(_ reason: String) throws -> Never { throw InputError(reason: reason) }
func yes(_ value: Bool) -> String { value ? "yes" : "no" }
func mark(_ m: [Int]) -> String { "(" + m.map { $0 < 0 ? "w" : String($0) }.joined(separator: ",") + ")" }
func listed(_ a: [String]) -> String { a.isEmpty ? "none" : a.joined(separator: " ") }
func number(_ s: String, _ low: Int, _ high: Int) -> Int? {
    let bytes = Array(s.utf8)
    guard !bytes.isEmpty, bytes.count <= 10, bytes.count == 1 || bytes[0] != 48, bytes.allSatisfy({ $0 >= 48 && $0 <= 57 }), let n = Int(s), n >= low, n <= high else { return nil }
    return n
}
func visit(_ adj: [[Int]], _ start: Int) -> [Bool] {
    var seen = Array(repeating: false, count: adj.count), queue = [start], cursor = 0; seen[start] = true
    while cursor < queue.count { for v in adj[queue[cursor]] where !seen[v] { seen[v] = true; queue.append(v) }; cursor += 1 }
    return seen
}
func gcd(_ x: Int, _ y: Int) -> Int { var a = x, b = y; while b != 0 { (a,b) = (b,a % b) }; return abs(a) }
func flows(_ matrix: [[Int]]) -> [[Int]] {
    let n = matrix.count, m = matrix[0].count
    var rows = matrix.enumerated().map { i,r in r + (0..<n).map { i == $0 ? 1 : 0 } }
    for j in 0..<m {
        var unique = Set(rows.filter { $0[j] == 0 })
        for r in rows where r[j] > 0 { for s in rows where s[j] < 0 { var v = (0..<m+n).map { -s[j]*r[$0]+r[j]*s[$0] }; let d = v.reduce(0,gcd); for k in v.indices { v[k] /= d }; unique.insert(v) } }
        let candidates = Array(unique)
        let supports = candidates.map { r in (0..<n).reduce(0) { $0 | (r[m+$1] > 0 ? 1 << $1 : 0) } }
        rows = candidates.enumerated().compactMap { i,r in supports.contains { $0 != supports[i] && ($0 & supports[i]) == $0 } ? nil : r }
    }
    return rows.map { Array($0[m...]) }.sorted { $1.lexicographicallyPrecedes($0) }
}
struct Graph {
    var states: [[Int]], parent: [Int], via: [Int], edges: [[(Int,Int)]]
    var found = -1, aborted = false
    init(_ start: [Int]) { states = [start]; parent = [-1]; via = [-1]; edges = [[]] }
    mutating func add(_ m: [Int], _ p: Int, _ t: Int) { states.append(m); parent.append(p); via.append(t); edges.append([]) }
}
final class Net {
    let name: String
    var places = [String](), transitions = [String](), initial = [Int](), capacity = [Int](), priority = [Int](), current = [Int](), history = [[Int]]()
    var pre = Array(repeating: Array(repeating: 0, count: 16), count: 16), post = Array(repeating: Array(repeating: 0, count: 16), count: 16), inhibitor = Array(repeating: Array(repeating: 0, count: 16), count: 16)
    var arcs = 0, inhibitors = 0
    init(_ name: String) { self.name = name }
    func define(_ w: [String]) throws {
        let cmd = w[0], n = w.count - 1
        guard ["place","transition","arc","inhibit"].contains(cmd) else { try bad("unknown definition \(cmd)") }
        guard cmd == "place" ? (n == 2 || n == 3) : cmd == "transition" ? (n == 1 || n == 2) : n == 3 else { try bad("wrong number of arguments") }
        let a = w[1]
        if cmd == "place" || cmd == "transition" {
            if places.contains(a) || transitions.contains(a) { try bad("duplicate name \(a)") }
            if cmd == "place" { if n == 3 && Int(w[2])! > Int(w[3])! { try bad("tokens exceed capacity of \(a)") }; places.append(a); initial.append(Int(w[2])!); capacity.append(n == 3 ? Int(w[3])! : 0) }
            else { transitions.append(a); priority.append(n == 2 ? Int(w[2])! : 0) }
        } else if cmd == "arc" {
            let b = w[2]; for x in [a,b] where !places.contains(x) && !transitions.contains(x) { try bad("unknown node \(x)") }
            let pa = places.firstIndex(of: a), pb = places.firstIndex(of: b)
            if (pa != nil) == (pb != nil) { try bad("arc must connect a place and a transition") }
            let p = pa ?? pb!, t = transitions.firstIndex(of: pa != nil ? b : a)!, weight = Int(w[3])!
            if pa != nil { if pre[p][t] > 0 { try bad("duplicate arc \(a) \(b)") }; pre[p][t] = weight }
            else { if post[p][t] > 0 { try bad("duplicate arc \(a) \(b)") }; post[p][t] = weight }; arcs += 1
        } else {
            guard let p = places.firstIndex(of: a) else { try bad("unknown place \(a)") }
            guard let t = transitions.firstIndex(of: w[2]) else { try bad("unknown transition \(w[2])") }
            if inhibitor[p][t] > 0 { try bad("duplicate inhibitor \(a) \(w[2])") }; inhibitor[p][t] = Int(w[3])!; inhibitors += 1
        }
    }
    func reason(_ m: [Int], _ t: Int) -> String? {
        for p in places.indices where m[p] >= 0 && m[p] < pre[p][t] { return "insufficient tokens in \(places[p])" }
        for p in places.indices where inhibitor[p][t] > 0 && (m[p] < 0 || m[p] >= inhibitor[p][t]) { return "inhibited by \(places[p])" }
        for p in places.indices where capacity[p] > 0 && (m[p] < 0 || m[p]-pre[p][t]+post[p][t] > capacity[p]) { return "capacity of \(places[p]) exceeded" }
        return nil
    }
    func enabled(_ m: [Int]) -> [Int] { transitions.indices.filter { reason(m,$0) == nil } }
    func fire(_ m: [Int], _ t: Int) -> [Int] { m.indices.map { m[$0] < 0 ? -1 : m[$0]-pre[$0][t]+post[$0][t] } }
    func commit(_ t: Int) { history.append(current); current = fire(current,t) }
    func names(_ ts: [Int]) -> [String] { ts.map { transitions[$0] } }
    func graph(_ start: [Int], _ limit: Int, _ target: [(Int,Int)]? = nil) -> Graph {
        var g = Graph(start), index = [start:0]
        func matches(_ m: [Int]) -> Bool { guard let target else { return false }; return m.indices.allSatisfy { m[$0] >= target[$0].0 && (target[$0].1 < 0 || m[$0] == target[$0].1) } }
        if matches(start) { g.found = 0; return g }; var q = 0
        while q < g.states.count { for t in enabled(g.states[q]) { let m = fire(g.states[q],t); let k: Int
            if let existing = index[m] { k = existing } else { if g.states.count == limit { g.aborted = true; return g }; k = g.states.count; index[m] = k; g.add(m,q,t); if matches(m) { g.found = k; return g } }; g.edges[q].append((t,k))
        }; q += 1 }; return g
    }
    func path(_ g: Graph, _ target: Int) -> [Int] { var k = target, a = [Int](); while g.parent[k] >= 0 { a.append(g.via[k]); k = g.parent[k] }; return Array(a.reversed()) }
    func reach(_ limit: Int, _ display: Bool) {
        let g = graph(current,limit); if g.aborted { print("reachability graph limit \(limit) exceeded"); return }; let n = g.states.count
        if display { for i in 0..<n { let a = g.edges[i].map { "\(transitions[$0.0])->M\($0.1)" }; print("M\(i) \(mark(g.states[i])): \(a.isEmpty ? "dead" : a.joined(separator: " "))") }; return }
        let adj = g.edges.map { $0.map { $0.1 } }
        let closure = (0..<n).map { visit(adj,$0) }
        var comp = Array(repeating: -1, count: n), components = 0
        for i in 0..<n where comp[i] < 0 { for j in i..<n where closure[i][j] && closure[j][i] { comp[j] = components }; components += 1 }
        var terminal = Array(repeating: true, count: components), home = Array(repeating: true, count: n), maximum = Array(repeating: 0, count: places.count), dead = [Int](), edgeCount = 0, persistent = true
        for i in 0..<n { if g.edges[i].isEmpty { dead.append(i) }; edgeCount += g.edges[i].count; for p in places.indices { maximum[p] = max(maximum[p],g.states[i][p]) }; for j in 0..<n { home[j] = home[j] && closure[i][j] }; for (t,k) in g.edges[i] { if comp[i] != comp[k] { terminal[comp[i]] = false }; for (u,_) in g.edges[i] where t != u && reason(g.states[k],u) != nil { persistent = false } } }
        print("reachable markings: \(n)\nedges: \(edgeCount)\ncomponents: \(components) (terminal \(terminal.filter { $0 }.count))\ndead markings: \(dead.count)")
        for i in dead { let a = names(path(g,i)); print("  M\(i) \(mark(g.states[i])) path \(a.isEmpty ? "empty" : a.joined(separator: " "))") }
        let bound = maximum.max()!; print("max tokens: \(mark(maximum))\nbound: \(bound)\nsafe: \(yes(bound<=1))\nhome markings: \(home.filter { $0 }.count)\nreversible: \(yes(home[0]))\npersistent: \(yes(persistent))")
        var levels = [String]()
        for t in transitions.indices { var present = Array(repeating: false, count: components), used = false, cycle = false; for i in 0..<n { for (u,k) in g.edges[i] where u == t { used = true; present[comp[i]] = true; if comp[i] == comp[k] { cycle = true } } }; let live = terminal.indices.allSatisfy { !terminal[$0] || present[$0] }; levels.append(transitions[t]+"="+(live ? "L4" : cycle ? "L3" : used ? "L1" : "L0")) }; print("liveness: " + levels.joined(separator: " "))
    }
    func rank(_ v: Int) -> Int { v < 0 ? Int.max : v }
    func cover(_ limit: Int) {
        var g = Graph(current), old = [false], dead = [false], seen: Set<[Int]> = [current], q = 0
        while q < g.states.count { if !old[q] { let es = enabled(g.states[q]); dead[q] = es.isEmpty; var ancestors = [Int](), a = q; while a >= 0 { ancestors.insert(a,at:0); a = g.parent[a] }
            for t in es { var m = fire(g.states[q],t); for a in ancestors { if m.indices.allSatisfy({ rank(m[$0]) >= rank(g.states[a][$0]) }) && m.indices.contains(where: { rank(m[$0]) > rank(g.states[a][$0]) }) { for p in m.indices where capacity[p] == 0 && rank(m[p]) > rank(g.states[a][p]) { m[p] = -1 } } }; if g.states.count == limit { print("coverability tree limit \(limit) exceeded"); return }; old.append(!seen.insert(m).inserted); dead.append(false); g.add(m,q,t) }
        }; q += 1 }
        print("coverability tree nodes: \(g.states.count)"); var maximum = Array(repeating: 0,count: places.count)
        for i in g.states.indices { let prefix = i == 0 ? "root" : "<- \(g.parent[i]) \(transitions[g.via[i]])"; print("  \(i) \(mark(g.states[i])) \(prefix)\(old[i] ? " old" : "")\(dead[i] ? " dead" : "")"); for p in places.indices where rank(g.states[i][p]) > rank(maximum[p]) { maximum[p] = g.states[i][p] } }
        print("bounds: \(mark(maximum))\nunbounded: \(listed(places.indices.filter { maximum[$0] < 0 }.map { places[$0] }))")
    }
    func bits(_ mask: Int) -> [Int] { places.indices.filter { mask & (1 << $0) != 0 } }
    func sets(_ trap: Bool) -> [Int] {
        let found = (1..<(1 << places.count)).filter { mask in transitions.indices.allSatisfy { t in let input = bits(mask).contains { post[$0][t] > 0 }, output = bits(mask).contains { pre[$0][t] > 0 }; return trap ? !output || input : !input || output } }
        return found.filter { m in !found.contains { $0 != m && ($0 & m) == $0 } }.sorted { a,b in let x = bits(a), y = bits(b); return x.count != y.count ? x.count < y.count : x.lexicographicallyPrecedes(y) }
    }
    func setText(_ mask: Int) -> String { "{" + bits(mask).map { places[$0] }.joined(separator: ",") + "}" }
    func realize(_ counts: [Int]) -> [Int]? {
        var used = Array(repeating: 0,count: counts.count), stack = [current], choices = [0], result = [Int](), seen = Set<[Int]>()
        let total = counts.reduce(0,+)
        while !stack.isEmpty { let d = result.count; if d == total { return result }; var chosen = -1
            for t in choices[d]..<counts.count { choices[d] = t+1; if used[t] >= counts[t] || reason(stack[d],t) != nil { continue }; used[t] += 1; let fresh = seen.insert(used).inserted; used[t] -= 1; if fresh { chosen = t; break } }
            if chosen >= 0 { used[chosen] += 1; result.append(chosen); stack.append(fire(stack[d],chosen)); choices.append(0) } else { stack.removeLast(); choices.removeLast(); if let t = result.popLast() { used[t] -= 1 } }
        }; return nil
    }
    func invariants(_ transpose: Bool) {
        let matrix = transpose ? transitions.indices.map { t in places.indices.map { post[$0][t]-pre[$0][t] } } : places.indices.map { p in transitions.indices.map { post[p][$0]-pre[p][$0] } }, ns = transpose ? transitions : places
        let f = flows(matrix); var covered = Array(repeating: false,count: ns.count), bounds = Array(repeating: -1,count: ns.count)
        print("\(transpose ? "T" : "P")-semiflows: \(f.count)")
        for c in f { let terms = c.indices.filter { c[$0] > 0 }.map { (c[$0] == 1 ? "" : "\(c[$0])*") + ns[$0] }.joined(separator: " + "); for i in c.indices where c[i] > 0 { covered[i] = true }
            if transpose { let sequence = realize(c); print("  \(terms): \(sequence.map { "realizable " + names($0).joined(separator: " ") } ?? "not realizable")") }
            else { let value = c.indices.reduce(0) { $0+c[$1]*current[$1] }; print("  \(terms) = \(value)"); for p in c.indices where c[p] > 0 { bounds[p] = bounds[p] < 0 ? value/c[p] : min(bounds[p],value/c[p]) } }
        }
        if !transpose { print("bounds: (" + bounds.map { $0 < 0 ? "-" : String($0) }.joined(separator: ",") + ")") }; print("\(transpose ? "consistent" : "conservative"): \(yes(covered.allSatisfy { $0 }))")
    }
    func classify() {
        let inputs = transitions.indices.map { t in places.indices.filter { pre[$0][t] > 0 } }, outputs = places.indices.map { p in transitions.indices.filter { pre[p][$0] > 0 } }
        let ordinary = places.indices.allSatisfy { p in transitions.indices.allSatisfy { pre[p][$0] <= 1 && post[p][$0] <= 1 } }, pure = places.indices.allSatisfy { p in transitions.indices.allSatisfy { pre[p][$0] == 0 || post[p][$0] == 0 } }
        let sm = ordinary && transitions.indices.allSatisfy { t in inputs[t].count == 1 && places.indices.filter { post[$0][t] > 0 }.count == 1 }, mg = ordinary && places.indices.allSatisfy { p in outputs[p].count == 1 && transitions.indices.filter { post[p][$0] > 0 }.count == 1 }
        let fc = ordinary && outputs.allSatisfy { a in a.allSatisfy { a.count == 1 || inputs[$0].count == 1 } }, efc = ordinary && outputs.allSatisfy { a in outputs.allSatisfy { b in !a.contains { b.contains($0) } || a == b } }
        for (label,value) in [("ordinary",ordinary),("pure",pure),("state machine",sm),("marked graph",mg),("free choice",fc),("extended free choice",efc)] { print("\(label): \(yes(value))") }
        var verdict = !fc ? "not applicable" : places.count > 12 ? "too many places" : "holds"
        if fc && places.count <= 12 { let traps = sets(true); for s in sets(false) where !traps.contains(where: { q in (s & q) == q && bits(q).contains { current[$0] > 0 } }) { verdict = "fails at " + setText(s); break } }; print("commoner: " + verdict)
    }
    func workflow(_ limit: Int) {
        let sources = places.indices.filter { p in transitions.indices.allSatisfy { post[p][$0] == 0 } }, sinks = places.indices.filter { p in transitions.indices.allSatisfy { pre[p][$0] == 0 } }
        if sources.count != 1 { print("workflow: no (\(sources.count) source places)"); return }; if sinks.count != 1 { print("workflow: no (\(sinks.count) sink places)"); return }
        let i = sources[0], o = sinks[0], P = places.count, ns = places+transitions
        var adj = Array(repeating: [Int](),count: ns.count), rev = adj
        for p in places.indices { for t in transitions.indices { if pre[p][t] > 0 { adj[p].append(P+t); rev[P+t].append(p) }; if post[p][t] > 0 { adj[P+t].append(p); rev[p].append(P+t) } } }
        let f = visit(adj,i), b = visit(rev,o); for v in ns.indices where !f[v] || !b[v] { print("workflow: no (\(ns[v]) is not on a path from \(places[i]) to \(places[o]))"); return }
        print("workflow: source \(places[i]) sink \(places[o])"); var start = Array(repeating: 0,count: P), goal = start; start[i] = 1; goal[o] = 1
        let g = graph(start,limit); if g.aborted { print("reachability graph limit \(limit) exceeded"); return }; let finish = g.states.firstIndex(of: goal); rev = Array(repeating: [],count: g.states.count); var used = Array(repeating: false,count: transitions.count)
        for u in g.states.indices { for (t,v) in g.edges[u] { rev[v].append(u); used[t] = true } }; let option = finish.map { visit(rev,$0).allSatisfy { $0 } } ?? false, proper = g.states.allSatisfy { $0[o] < 1 || $0 == goal }, live = used.allSatisfy { $0 }
        print("option to complete: \(yes(option))\nproper completion: \(yes(proper))\nno dead transitions: \(yes(live))\nsound: \(yes(option && proper && live))")
    }
    func execute(_ w: [String]) throws {
        let arity = ["MARKING":0,"RESET":0,"SET":2,"ENABLED":0,"FIRE":-1,"UNDO":1,"SIMULATE":3,"CONFLICTS":0,"REACH":1,"GRAPH":1,"COVER":1,"PATH":2,"INCIDENCE":0,"PINV":0,"TINV":0,"SIPHONS":0,"TRAPS":0,"CLASSIFY":0,"WORKFLOW":1,"SHOW":0], cmd = w[0]
        guard let expected = arity[cmd] else { try bad("unknown command \(cmd)") }; if expected < 0 ? w.count < 2 : w.count != expected+1 { try bad("wrong number of arguments") }
        var limit = 0; if ["REACH","GRAPH","COVER","PATH","WORKFLOW"].contains(cmd) { guard let n = number(w[1],1,2000) else { try bad("invalid limit \(w[1])") }; limit = n }
        switch cmd {
        case "MARKING", "RESET": if cmd == "RESET" { current = initial; history.removeAll() }; print("marking " + mark(current))
        case "SET": guard let p = places.firstIndex(of: w[1]) else { try bad("unknown place \(w[1])") }; guard let v = number(w[2],0,999) else { try bad("invalid tokens \(w[2])") }; if capacity[p] > 0 && v > capacity[p] { try bad("tokens exceed capacity of \(w[1])") }; current[p] = v; history.removeAll(); print("marking " + mark(current))
        case "ENABLED": print("enabled: " + listed(names(enabled(current))))
        case "FIRE": var ts = [Int](); for name in w.dropFirst() { guard let t = transitions.firstIndex(of: name) else { try bad("unknown transition \(name)") }; ts.append(t) }; for (i,t) in ts.enumerated() { if let reason = reason(current,t) { print("step \(i+1): \(transitions[t]) not enabled (\(reason)) at \(mark(current))"); return }; commit(t) }; print("fired \(ts.count) -> \(mark(current))")
        case "UNDO": guard let k = number(w[1],1,1000) else { try bad("invalid count \(w[1])") }; if k > history.count { try bad("cannot undo \(k): history size \(history.count)") }; current = history[history.count-k]; history.removeLast(k); print("marking " + mark(current))
        case "SIMULATE": guard let steps = number(w[1],1,1000) else { try bad("invalid steps \(w[1])") }; guard var x = number(w[2],1,2147483646) else { try bad("invalid seed \(w[2])") }; if !["PRIORITY","RANDOM"].contains(w[3]) { try bad("invalid mode \(w[3])") }; var counts = Array(repeating: 0,count: transitions.count), done = 0
            while done < steps { let es = enabled(current); if es.isEmpty { print("dead (steps=\(done))"); break }; var t = es[0]; if w[3] == "RANDOM" { x = x*48271%2147483647; t = es[x%es.count] } else { for u in es where priority[u] > priority[t] { t = u } }; commit(t); counts[t] += 1; done += 1; print("step \(done): \(transitions[t]) -> \(mark(current))") }; if done == steps { print("completed (steps=\(steps))") }; print("counts: " + transitions.indices.map { "\(transitions[$0])=\(counts[$0])" }.joined(separator: " "))
        case "CONFLICTS": var s = [String](), e = [String](); for u in transitions.indices { for v in u+1..<transitions.count { let pair = transitions[u]+"/"+transitions[v]; if places.indices.contains(where: { pre[$0][u] > 0 && pre[$0][v] > 0 }) { s.append(pair) }; if reason(current,u) == nil && reason(current,v) == nil && (reason(fire(current,u),v) != nil || reason(fire(current,v),u) != nil) { e.append(pair) } } }; print("structural: \(listed(s))\neffective: \(listed(e))")
        case "REACH", "GRAPH": reach(limit,cmd == "GRAPH")
        case "COVER": cover(limit)
        case "PATH": let entries = w[2].split(separator: ",",omittingEmptySubsequences: false).map(String.init); if entries.count != places.count { try bad("target needs \(places.count) entries") }; var target = [(Int,Int)](); for s in entries { if s == "*" { target.append((0,-1)); continue }; let plus = s.hasSuffix("+"); guard let v = number(plus ? String(s.dropLast()) : s,0,9999999999) else { try bad("invalid target entry \(s)") }; target.append((v,plus ? -1 : v)) }; let g = graph(current,limit,target); if g.found >= 0 { let a = names(path(g,g.found)); print("reached \(mark(g.states[g.found])) length=\(a.count)\(a.isEmpty ? "" : ": " + a.joined(separator: " "))") } else if g.aborted { print("search limit \(limit) exceeded") } else { print("unreachable (markings explored: \(g.states.count))") }
        case "INCIDENCE":
            let rows = [[""]+transitions] + places.indices.map { p in [places[p]] + transitions.indices.map { String(post[p][$0]-pre[p][$0]) } }
            let widths = rows[0].indices.map { i in rows.map { $0[i].count }.max()! }
            for r in rows {
                let a = r.indices.map { i in let pad = String(repeating: " ",count: widths[i]-r[i].count); return i == 0 ? r[i]+pad : pad+r[i] }
                var line = a.joined(separator: "  "); while line.last == " " { line.removeLast() }; print(line)
            }
        case "PINV", "TINV": invariants(cmd == "TINV")
        case "SIPHONS", "TRAPS": if places.count > 12 { try bad("more than 12 places") }; let ss = sets(cmd == "TRAPS"); print("minimal \(cmd == "TRAPS" ? "traps" : "siphons"): \(ss.count)"); for s in ss { print("  \(setText(s)) tokens=\(bits(s).reduce(0) { $0+current[$1] })") }
        case "CLASSIFY": classify()
        case "WORKFLOW": workflow(limit)
        case "SHOW": for p in places.indices { print("place \(places[p]) tokens=\(initial[p]) capacity=\(capacity[p] == 0 ? "none" : String(capacity[p]))") }; for t in transitions.indices { func list(_ matrix: [[Int]]) -> String { let a = places.indices.filter { matrix[$0][t] > 0 }.map { "\(places[$0]):\(matrix[$0][t])" }; return a.isEmpty ? "-" : a.joined(separator: ",") }; print("transition \(transitions[t]) priority=\(priority[t]) pre=\(list(pre)) post=\(list(post)) inhibit=\(list(inhibitor))") }
        default: break
        }
    }
}
let blocks = Int(readLine()!)!
for _ in 0..<blocks {
    let net = Net(readLine()!.components(separatedBy: " ")[1])
    while let line = readLine(), line != "END NET" { do { try net.define(line.components(separatedBy: " ")) } catch let error as InputError { print("error: " + error.reason) } }
    net.current = net.initial; print("net \(net.name): places=\(net.places.count) transitions=\(net.transitions.count) arcs=\(net.arcs) inhibitors=\(net.inhibitors)")
    let count = Int(readLine()!)!; for _ in 0..<count { do { try net.execute(readLine()!.components(separatedBy: " ")) } catch let error as InputError { print("error: " + error.reason) } }
}
