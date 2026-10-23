import Foundation

struct Problem: Error {
    let text: String
}

func fail(_ reason: String) throws -> Never {
    throw Problem(text: "ERROR " + reason)
}

struct Edge {
    var from: Int
    var to: Int
    var capacity: Int
    var cost = 0
    var lower = 0
    var flow = 0
}

struct Arc {
    let edge: Int
    let forward: Bool
}

enum Owner: Equatable {
    case none, flow(Int, Int), circulation
}

struct Pushed {
    let arcs: [Arc]
    let amount: Int
    var phase = 0
    var delta = 1
    var cost = 0
}

struct Component {
    let start: Int
    let edges: [Int]
    let amount: Int
    let cycle: Bool
}

final class Network {
    var names = [String]()
    var demands = [Int]()
    var edges = [Edge]()
    var owner = Owner.none
    func copy() -> Network {
        let n = Network()
        n.names = names
        n.demands = demands
        n.edges = edges
        n.owner = owner
        return n
    }
    func node(_ name: String) throws -> Int {
        guard let i = names.firstIndex(of: name) else {
            try fail("UNKNOWN NODE \(name)")
        }
        return i
    }
    func endpoints(_ a: String, _ b: String) throws -> (Int, Int) {
        let s = try node(a)
        let t = try node(b)
        if s == t {
            try fail("SAME NODE")
        }
        return (s,t)
    }
    func edgeNumber(_ text: String) throws -> Int {
        let i = Int(text)!
        if i < 1 || i > edges.count {
            try fail("UNKNOWN EDGE \(text)")
        }
        return i-1
    }
    // Forward arcs precede all backward arcs, including in every vertex list.
    func globalArcs() -> [Arc] {
        [true,false].flatMap {
            forward in edges.indices.map {
                Arc(edge: $0,forward: forward)
            }
        }
    }
    func arcs(_ node: Int) -> [Arc] {
        globalArcs().filter {
            start($0) == node
        }
    }
    func start(_ a: Arc) -> Int {
        a.forward ? edges[a.edge].from : edges[a.edge].to
    }
    func end(_ a: Arc) -> Int {
        a.forward ? edges[a.edge].to : edges[a.edge].from
    }
    func residual(_ a: Arc) -> Int {
        a.forward ? edges[a.edge].capacity-edges[a.edge].flow : edges[a.edge].flow
    }
    func arcCost(_ a: Arc) -> Int {
        a.forward ? edges[a.edge].cost : -edges[a.edge].cost
    }
    func push(_ path: [Arc], _ amount: Int) {
        for a in path {
            edges[a.edge].flow += a.forward ? amount : -amount
        }
    }
    func bottleneck(_ path: [Arc]) -> Int {
        path.map {
            residual($0)
        }.min()!
    }
    func balances() -> [Int] {
        var b = Array(repeating: 0,count: names.count)
        for e in edges {
            b[e.from] += e.flow
            b[e.to] -= e.flow
        }
        return b
    }
    func cost() -> Int {
        edges.reduce(0) {
            $0+$1.flow*$1.cost
        }
    }
    func zero() {
        for i in edges.indices {
            edges[i].flow = 0
        }
    }
    func begin(_ s: Int, _ t: Int) -> Int {
        if owner != .flow(s,t) {
            zero()
        }
        owner = .flow(s,t)
        return balances()[s]
    }
    func bfs(_ s: Int, _ delta: Int = 1) -> ([Int],[Arc?]) {
        var levels = Array(repeating: -1,count: names.count)
        var parent = [Arc?](repeating: nil,count: names.count)
        var queue = [s]
        var head = 0
        levels[s] = 0
        while head < queue.count {
            let u = queue[head]
            head += 1
            for a in arcs(u) {
                let v = end(a)
                if residual(a) >= delta && levels[v] < 0 {
                    levels[v] = levels[u]+1
                    parent[v] = a
                    queue.append(v)
                }
            }
        }
        return (levels,parent)
    }
    func path(_ s: Int, _ t: Int, _ parent: [Arc?]) -> [Arc] {
        var result = [Arc]()
        var u = t
        while u != s {
            let a = parent[u]!
            result.append(a)
            u = start(a)
        }
        return Array(result.reversed())
    }
    func augment(_ s: Int, _ t: Int, _ delta: Int = 1) -> Pushed? {
        let (level,parent) = bfs(s,delta)
        if level[t] < 0 {
            return nil
        }
        let p = path(s,t,parent)
        let amount = bottleneck(p)
        push(p,amount)
        return Pushed(arcs: p,amount: amount,delta: delta)
    }
    @discardableResult func maxflow(_ s: Int, _ t: Int) -> [Pushed] {
        var result = [Pushed]()
        while let p = augment(s,t) {
            result.append(p)
        }
        return result
    }
    func dinic(_ s: Int, _ t: Int) -> (Int,[Pushed]) {
        var phases = 0
        var result = [Pushed]()
        while true {
            let (level,_) = bfs(s)
            if level[t] < 0 {
                return (phases,result)
            }
            phases += 1
            let lists = names.indices.map {
                arcs($0)
            }
            var pointers = Array(repeating: 0,count: names.count)
            var p = [Arc]()
            var u = s
            while true {
                if u == t {
                    let amount = bottleneck(p)
                    push(p,amount)
                    result.append(Pushed(arcs: p,amount: amount,phase: phases))
                    p = []
                    u = s
                } else if pointers[u] == lists[u].count {
                    if u == s {
                        break
                    }
                    let a = p.removeLast()
                    u = start(a)
                    pointers[u] += 1
                } else {
                    let a = lists[u][pointers[u]]
                    let v = end(a)
                    if residual(a) > 0 && level[v] >= 0 && level[v] == level[u]+1 {
                        p.append(a)
                        u = v
                    } else {
                        pointers[u] += 1
                    }
                }
            }
        }
    }
    func scaling(_ s: Int, _ t: Int) -> [Pushed] {
        let maximum = edges.map(\.capacity).max() ?? 0
        var delta = 1
        while delta*2 <= maximum {
            delta *= 2
        }
        var result = [Pushed]()
        while delta >= 1 {
            while let p = augment(s,t,delta) {
                result.append(p)
            }
            delta /= 2
        }
        return result
    }
    func negativeCycle(_ lower: Bool) -> Bool {
        var distance = Array(repeating: 0,count: names.count)
        for pass in names.indices {
            var changed = false
            for e in edges where e.capacity-(lower ? e.lower : 0) > 0 {
                if distance[e.to] > distance[e.from]+e.cost {
                    distance[e.to] = distance[e.from]+e.cost
                    changed = true
                }
            }
            if !changed {
                return false
            }
            if pass == names.count-1 {
                return true
            }
        }
        return false
    }
    // Keep the usable arc sequence fixed and apply each relaxation immediately.
    func shortest(_ s: Int) -> ([Int?],[Arc?]) {
        let q = globalArcs().filter {
            residual($0) > 0
        }
        var distance = [Int?](repeating: nil,count: names.count)
        var parent = [Arc?](repeating: nil,count: names.count)
        distance[s] = 0
        while true {
            var changed = false
            for a in q {
                let u = start(a)
                let v = end(a)
                if let d = distance[u] {
                    let next = d+arcCost(a)
                    if distance[v] == nil || next < distance[v]! {
                        distance[v] = next
                        parent[v] = a
                        changed = true
                    }
                }
            }
            if !changed {
                return (distance,parent)
            }
        }
    }
    func mincost(_ s: Int, _ t: Int, _ target: Int? = nil) -> (Int,Int,[Pushed]) {
        var amount = 0
        var cost = 0
        var result = [Pushed]()
        while target == nil || amount < target! {
            let (distance,parent) = shortest(s)
            guard let unit = distance[t] else {
                break
            }
            let p = path(s,t,parent)
            let delta = min(bottleneck(p),target.map {
                $0-amount
            } ?? Int.max)
            push(p,delta)
            amount += delta
            cost += delta*unit
            result.append(Pushed(arcs: p,amount: delta,cost: unit))
        }
        return (amount,cost,result)
    }
    func notation(_ s: Int, _ path: [Arc]) -> String {
        names[s]+path.map {
            " \($0.forward ? "+" : "-")\($0.edge+1) \(names[end($0)])"
        }.joined()
    }
    func flows() -> [String] {
        edges.enumerated().map {
            i,e in "FLOW \(i+1) \(names[e.from]) \(names[e.to]) \(e.flow)/\(e.capacity)"
        }
    }
    func decompose() -> [Component] {
        var g = edges.map(\.flow)
        var balance = balances()
        var result = [Component]()
        while let first = g.firstIndex(where: {
            $0 > 0
        }) {
            let initial = balance.firstIndex(where: {
                $0 > 0
            }) ?? edges[first].from
            var vertices = [initial]
            var p = [Int]()
            while true {
                let u = vertices.last!
                let i = edges.indices.first {
                    edges[$0].from == u && g[$0] > 0
                }!
                let v = edges[i].to
                p.append(i)
                if let q = vertices.firstIndex(of: v) {
                    let cycle = Array(p.dropFirst(q))
                    let delta = cycle.map {
                        g[$0]
                    }.min()!
                    for e in cycle {
                        g[e] -= delta
                    }
                    result.append(Component(start: v,edges: cycle,amount: delta,cycle: true))
                    break
                }
                vertices.append(v)
                if balance[v] < 0 {
                    let delta = min(p.map {
                        g[$0]
                    }.min()!,balance[initial],-balance[v])
                    for e in p {
                        g[e] -= delta
                    }
                    balance[initial] -= delta
                    balance[v] += delta
                    result.append(Component(start: initial,edges: p,amount: delta,cycle: false))
                    break
                }
            }
        }
        return result
    }
    func command(_ w: [String]) throws -> [String] {
        let c = w[0]
        let a = Array(w.dropFirst())
        func num(_ i: Int) -> Int {
            Int(a[i])!
        }
        var out = [String]()
        switch c {
        case "NODE":
            var seen = Set(names)
            for name in a {
                if !seen.insert(name).inserted {
                    try fail("DUPLICATE NODE \(name)")
                }
            }
            if names.count+a.count > 20 {
                try fail("TOO MANY NODES")
            }
            names += a
            demands += Array(repeating: 0,count: a.count)
            out.append("NODE added=\(a.count) total=\(names.count)")
        case "EDGE":
            let u = try node(a[0])
            let v = try node(a[1])
            if u == v {
                try fail("SELF LOOP")
            }
            if edges.count == 60 {
                try fail("TOO MANY EDGES")
            }
            let cost = a.count == 4 ? num(3) : 0
            edges.append(Edge(from: u,to: v,capacity: num(2),cost: cost))
            out.append("EDGE \(edges.count) \(a[0]) \(a[1]) cap=\(num(2)) cost=\(cost)")
        case "LOWER","CAP","COST":
            let i = try edgeNumber(a[0])
            let n = num(1)
            if c == "LOWER" {
                if n > edges[i].capacity {
                    try fail("BAD BOUND")
                }
                edges[i].lower = n
                out.append("LOWER \(a[0]) low=\(n) cap=\(edges[i].capacity)")
            } else if c == "CAP" {
                if n < edges[i].lower {
                    try fail("BAD BOUND")
                }
                if n < edges[i].flow {
                    try fail("BELOW FLOW")
                }
                edges[i].capacity = n
                out.append("CAP \(a[0]) low=\(edges[i].lower) cap=\(n)")
            } else {
                edges[i].cost = n
                out.append("COST \(a[0]) cost=\(n)")
            }
        case "DEMAND":
            let i = try node(a[0])
            demands[i] = num(1)
            out.append("DEMAND \(a[0]) \(num(1)) total=\(demands.reduce(0,+))")
        case "RESET":
            out.append("RESET edges=\(edges.filter { $0.flow != 0 }.count)")
            zero()
            owner = .none
        case "CLEAR":
            out.append("CLEAR nodes=\(names.count) edges=\(edges.count)")
            names = []
            demands = []
            edges = []
            owner = .none
        case "SHOW":
            let balance = balances()
            out.append("NETWORK nodes=\(names.count) edges=\(edges.count)")
            switch owner {
            case .none:
                out.append("STATE none")
            case .circulation:
                out.append("STATE circulation cost=\(cost())")
            case let .flow(s,t):
                out.append("STATE flow \(names[s]) \(names[t]) value=\(balance[s]) cost=\(cost())")
            }
            for (i,name) in names.enumerated() {
                out.append("NODE \(name) demand=\(demands[i]) out=\(edges.filter { $0.from == i }.reduce(0) { $0+$1.flow }) in=\(edges.filter { $0.to == i }.reduce(0) { $0+$1.flow })")
            }
            for (i,e) in edges.enumerated() {
                out.append("EDGE \(i+1) \(names[e.from]) \(names[e.to]) cap=\(e.capacity) cost=\(e.cost) low=\(e.lower) flow=\(e.flow)")
            }
        case "AUGMENT","MAXFLOW","DINIC","SCALING","MINCUT":
            let (s,t) = try endpoints(a[0],a[1])
            let initial = begin(s,t)
            if c == "AUGMENT" {
                if let p = augment(s,t) {
                    out.append("AUGMENT \(a[0]) \(a[1]) value=\(balances()[s]) amount=\(p.amount) \(notation(s,p.arcs))")
                } else {
                    out.append("AUGMENT \(a[0]) \(a[1]) value=\(balances()[s]) none")
                }
            } else if c == "MINCUT" {
                maxflow(s,t)
                let (level,_) = bfs(s)
                let cut = edges.indices.filter {
                    level[edges[$0].from] >= 0 && level[edges[$0].to] < 0
                }
                out.append("MINCUT \(a[0]) \(a[1]) value=\(balances()[s]) edges=\(cut.count)")
                out.append("SOURCE "+names.indices.filter {
                    level[$0] >= 0
                }.map {
                    names[$0]
                }.joined(separator: " "))
                out.append("SINK "+names.indices.filter {
                    level[$0] < 0
                }.map {
                    names[$0]
                }.joined(separator: " "))
                for i in cut {
                    let e = edges[i]
                    out.append("CUT \(i+1) \(names[e.from]) \(names[e.to]) \(e.capacity)")
                }
            } else {
                let (phases,paths) = c == "DINIC" ? dinic(s,t) : (0,c == "SCALING" ? scaling(s,t) : maxflow(s,t))
                out.append("\(c) \(a[0]) \(a[1]) value=\(balances()[s]) start=\(initial)"+(c == "DINIC" ? " phases=\(phases)" : "")+" paths=\(paths.count)")
                for (i,p) in paths.enumerated() {
                    out.append("AUG \(i+1)"+(c == "DINIC" ? " phase=\(p.phase)" : c == "SCALING" ? " delta=\(p.delta)" : "")+" amount=\(p.amount) \(notation(s,p.arcs))")
                }
                out += flows()
            }
        case "SENSITIVITY":
            let (s,t) = try endpoints(a[0],a[1])
            let base = copy()
            base.zero()
            base.maxflow(s,t)
            let value = base.balances()[s]
            var up = 0
            var down = 0
            var details = [String]()
            for i in edges.indices {
                let work = copy()
                work.zero()
                work.edges[i].capacity += 1
                work.maxflow(s,t)
                let effectiveUp = work.balances()[s] > value
                var effectiveDown = false
                if edges[i].capacity > 0 {
                    let reduced = copy()
                    reduced.zero()
                    reduced.edges[i].capacity -= 1
                    reduced.maxflow(s,t)
                    effectiveDown = reduced.balances()[s] < value
                }
                if effectiveUp {
                    up += 1
                }
                if effectiveDown {
                    down += 1
                }
                if effectiveUp || effectiveDown {
                    let e = edges[i]
                    details.append("CRITICAL \(i+1) \(names[e.from]) \(names[e.to]) up=\(effectiveUp ? "yes" : "no") down=\(effectiveDown ? "yes" : "no")")
                }
            }
            out.append("SENSITIVITY \(a[0]) \(a[1]) value=\(value) up=\(up) down=\(down)")
            out += details
        case "MINCOST":
            let (s,t) = try endpoints(a[0],a[1])
            if negativeCycle(false) {
                try fail("NEGATIVE CYCLE")
            }
            let target = a[2] == "MAX" ? nil : Int(a[2])
            let work = copy()
            work.zero()
            let (amount,cost,paths) = work.mincost(s,t,target)
            if let target = target, amount < target {
                out.append("MINCOST \(a[0]) \(a[1]) k=\(a[2]) infeasible max=\(amount)")
            } else {
                for i in edges.indices {
                    edges[i].flow = work.edges[i].flow
                }
                owner = .flow(s,t)
                out.append("MINCOST \(a[0]) \(a[1]) k=\(a[2]) flow=\(amount) cost=\(cost)")
                for (i,p) in paths.enumerated() {
                    out.append("AUG \(i+1) amount=\(p.amount) cost=\(p.cost) \(notation(s,p.arcs))")
                }
                out += flows()
            }
        case "DISJOINT":
            let (s,t) = try endpoints(a[0],a[1])
            let original = edges.count
            let work = copy()
            work.zero()
            var exits = Array(names.indices)
            if a[2] == "VERTEX" {
                for v in names.indices where v != s && v != t {
                    exits[v] = work.names.count
                    work.names.append(names[v])
                    work.demands.append(0)
                }
            }
            for i in work.edges.indices {
                work.edges[i].from = exits[work.edges[i].from]
                work.edges[i].capacity = work.edges[i].capacity > 0 ? 1 : 0
                work.edges[i].cost = 0
            }
            if a[2] == "VERTEX" {
                for v in names.indices where v != s && v != t {
                    work.edges.append(Edge(from: v,to: exits[v],capacity: 1))
                }
            }
            work.maxflow(s,t)
            let paths = work.decompose().filter {
                !$0.cycle
            }
            out.append("DISJOINT \(a[0]) \(a[1]) \(a[2]) count=\(paths.count)")
            for (i,p) in paths.enumerated() {
                out.append("PATH \(i+1) \(notation(s,p.edges.filter { $0 < original }.map { Arc(edge: $0,forward: true) }))")
            }
        case "DECOMPOSE":
            let parts = decompose()
            out.append("DECOMPOSE paths=\(parts.filter { !$0.cycle }.count) cycles=\(parts.filter { $0.cycle }.count)")
            var counts = [0,0]
            for p in parts {
                let kind = p.cycle ? 1 : 0
                counts[kind] += 1
                out.append("\(p.cycle ? "CYCLE" : "PATH") \(counts[kind]) amount=\(p.amount) \(notation(p.start,p.edges.map { Arc(edge: $0,forward: true) }))")
            }
        case "VERIFY":
            var violations = [String]()
            for (i,e) in edges.enumerated() where e.flow < e.lower {
                violations.append("LOW \(i+1) flow=\(e.flow) low=\(e.lower)")
            }
            let balance = balances()
            for i in names.indices {
                var need: Int? = demands[i]
                if case let .flow(s,t) = owner {
                    need = i == s || i == t ? nil : 0
                }
                if let need = need, -balance[i] != need {
                    violations.append("BALANCE \(names[i]) net=\(-balance[i]) need=\(need)")
                }
            }
            if violations.isEmpty {
                out.append("VERIFY ok")
            } else {
                out.append("VERIFY violations=\(violations.count)")
                out += violations
            }
        case "CIRCULATION":
            if a[0] == "MINCOST" && negativeCycle(true) {
                try fail("NEGATIVE CYCLE")
            }
            let sum = demands.reduce(0,+)
            if sum != 0 {
                return ["CIRCULATION infeasible unbalanced=\(sum)"]
            }
            let n = names.count
            let work = copy()
            work.names += ["super source","super sink"]
            work.demands += [0,0]
            var required = demands
            for i in work.edges.indices {
                let e = work.edges[i]
                required[e.to] -= e.lower
                required[e.from] += e.lower
                work.edges[i].capacity -= e.lower
                work.edges[i].flow = 0
            }
            for v in required.indices where required[v] < 0 {
                work.edges.append(Edge(from: n,to: v,capacity: -required[v]))
            }
            let sinkStart = work.edges.count
            for v in required.indices where required[v] > 0 {
                work.edges.append(Edge(from: v,to: n+1,capacity: required[v]))
            }
            if a[0] == "ANY" {
                work.maxflow(n,n+1)
            } else {
                _ = work.mincost(n,n+1)
            }
            let total = required.filter {
                $0 > 0
            }.reduce(0,+)
            let achieved = work.edges.dropFirst(sinkStart).reduce(0) {
                $0+$1.flow
            }
            if achieved < total {
                let (level,_) = work.bfs(n)
                out.append("CIRCULATION infeasible required=\(total) achieved=\(achieved)")
                out.append("CUT "+names.indices.filter {
                    level[$0] >= 0
                }.map {
                    names[$0]
                }.joined(separator: " "))
            } else {
                for i in edges.indices {
                    edges[i].flow = edges[i].lower+work.edges[i].flow
                }
                owner = .circulation
                out.append("CIRCULATION feasible required=\(total) cost=\(cost())")
                out += flows()
            }
        case "MATCH":
            out += try matching(a)
        case "ASSIGN":
            out += try assignment(a)
        default:
            break
        }
        return out
    }
}

func matching(_ a: [String]) throws -> [String] {
    let left = a[0].split(separator: ",").map(String.init)
    let right = a[1].split(separator: ",").map(String.init)
    var seen = Set<String>()
    for n in left+right {
        if !seen.insert(n).inserted {
            try fail("DUPLICATE VERTEX \(n)")
        }
    }
    var pairs = [(Int,Int)]()
    if a[2] != "-" {
        for p in a[2].split(separator: ",").map(String.init) {
            let words = p.split(separator: "-").map(String.init)
            guard let u = left.firstIndex(of: words[0]) else {
                try fail("UNKNOWN VERTEX \(words[0])")
            }
            guard let v = right.firstIndex(of: words[1]) else {
                try fail("UNKNOWN VERTEX \(words[1])")
            }
            if pairs.contains(where: {
                $0.0 == u && $0.1 == v
            }) {
                try fail("DUPLICATE PAIR \(p)")
            }
            pairs.append((u,v))
        }
    }
    var lp = Array(repeating: -1,count: left.count)
    var rp = Array(repeating: -1,count: right.count)
    func attempt(_ u: Int, _ examined: inout [Bool]) -> Bool {
        for (x,b) in pairs where x == u && !examined[b] {
            examined[b] = true
            if rp[b] < 0 || attempt(rp[b],&examined) {
                lp[u] = b
                rp[b] = u
                return true
            }
        }
        return false
    }
    for u in left.indices {
        var examined = Array(repeating: false,count: right.count)
        _ = attempt(u,&examined)
    }
    var zl = lp.map {
        $0 < 0
    }
    var zr = Array(repeating: false,count: right.count)
    while true {
        var changed = false
        for (u,v) in pairs where zl[u] && lp[u] != v && !zr[v] {
            zr[v] = true
            changed = true
        }
        for v in right.indices where zr[v] && rp[v] >= 0 && !zl[rp[v]] {
            zl[rp[v]] = true
            changed = true
        }
        if !changed {
            break
        }
    }
    let size = lp.filter {
        $0 >= 0
    }.count
    var out = ["MATCH size=\(size) left=\(left.count) right=\(right.count)"]
    for u in left.indices where lp[u] >= 0 {
        out.append("PAIR \(left[u]) \(right[lp[u]])")
    }
    func list(_ values: [String]) -> String {
        values.isEmpty ? "-" : values.joined(separator: ",")
    }
    out.append("FREE \(list(left.indices.filter { lp[$0] < 0 }.map { left[$0] })) \(list(right.indices.filter { rp[$0] < 0 }.map { right[$0] }))")
    let cover = left.indices.filter {
        !zl[$0]
    }.map {
        left[$0]
    }+right.indices.filter {
        zr[$0]
    }.map {
        right[$0]
    }
    out.append("COVER size=\(cover.count)"+cover.map {
        " "+$0
    }.joined())
    if lp.contains(-1) {
        out.append("HALL \(list(left.indices.filter { zl[$0] }.map { left[$0] })) \(list(right.indices.filter { zr[$0] }.map { right[$0] }))")
    }
    return out
}

func assignment(_ a: [String]) throws -> [String] {
    let n = Int(a[1])!
    if n < 1 || n > 8 {
        try fail("BAD SIZE")
    }
    if a.count-2 != n*n {
        try fail("BAD LENGTH")
    }
    let values = a.dropFirst(2).map {
        Int($0)
    }
    var best: Int?
    var count = 0
    var first = [Int]()
    var chosen = [Int]()
    func visit(_ used: Int, _ sum: Int) {
        let row = chosen.count
        if row == n {
            if best == nil || (a[0] == "MAX" ? sum > best! : sum < best!) {
                best = sum
                count = 1
                first = chosen
            } else if sum == best! {
                count += 1
            }
            return
        }
        for col in 0..<n where used & (1 << col) == 0 {
            if let v = values[row*n+col] {
                chosen.append(col)
                visit(used | (1 << col),sum+v)
                chosen.removeLast()
            }
        }
    }
    visit(0,0)
    guard let best = best else {
        return ["ASSIGN \(a[0]) n=\(n) infeasible"]
    }
    return ["ASSIGN \(a[0]) n=\(n) total=\(best) optimal=\(count)"]+first.enumerated().map {
        row,col in "MATE \(row+1) \(col+1) \(values[row*n+col]!)"
    }
}

let network = Network()
if let first = readLine(), let count = Int(first) {
    for _ in 0..<count {
        do {
            for line in try network.command(readLine()!.split(separator: " ").map(String.init)) {
                print(line)
            }
        } catch let problem as Problem {
            print(problem.text)
        } catch {
        }
    }
}
