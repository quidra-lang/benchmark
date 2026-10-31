import Foundation
struct Problem: Error {
    let text: String
}
func fail(_ reason: String) throws -> Never {
    throw Problem(text: "error: " + reason)
}
func numbers(_ values: [Int]) -> String {
    values.map(String.init).joined(separator: " ")
}
func yes(_ value: Bool) -> String {
    value ? "yes" : "no"
}
func shown(_ value: Int?, _ absent: String) -> String {
    value.map(String.init) ?? absent
}
func colorCount(_ colors: [Int]) -> Int {
    colors.max()! + 1
}
func individualize(_ colors: [Int], _ v: Int) -> [Int] {
    colors.enumerated().map {
        w, c in c < colors[v] || w == v ? c : c + 1
    }
}
func compareLists(_ a: [Int], _ b: [Int]) -> Int {
    for i in 0..<min(a.count, b.count) {
        if a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
    }
    return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
}
struct Canonical {
    var nodes = 0, leaves = 0, text = "", label: [Int] = [], winners: [[Int]] = []
}
struct Invariants {
    let degrees: [Int], triangles: Int, sizes: [Int], girth: Int?, diameter: Int?, radius: Int?, bipartite: Bool
}
final class Graph {
    let n: Int
    var adjacent: [Int]
    init(_ n: Int) {
        self.n = n
        adjacent = Array(repeating: 0, count: n)
    }
    func has(_ u: Int, _ v: Int) -> Bool {
        adjacent[u] & (1 << v) != 0
    }
    func join(_ u: Int, _ v: Int) {
        adjacent[u] |= 1 << v
        adjacent[v] |= 1 << u
    }
    func edges() -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for u in 0..<n {
            for v in (u + 1)..<n {
                if has(u, v) {
                    result.append((u, v))
                }
            }
        }
        return result
    }
    func degrees() -> [Int] {
        adjacent.map(\.nonzeroBitCount)
    }
    func refine(_ input: [Int]) -> ([Int], Int) {
        var colors = input, rounds = 0
        while true {
            let signatures = (0..<n).map {
                v in (colors[v], (0..<n).filter {
                    has(v, $0)
                }.map {
                    colors[$0]
                }.sorted())
            }
            func before(_ a: (Int, [Int]), _ b: (Int, [Int])) -> Bool {
                a.0 == b.0 ? a.1.lexicographicallyPrecedes(b.1) : a.0 < b.0
            }
            var unique: [(Int, [Int])] = []
            for signature in signatures.sorted(by: before) {
                if unique.last.map({
                    $0.0 == signature.0 && $0.1 == signature.1
                }) != true {
                    unique.append(signature)
                }
            }
            if unique.count == colorCount(colors) {
                return (colors, rounds)
            }
            colors = signatures.map {
                s in unique.firstIndex {
                    $0.0 == s.0 && $0.1 == s.1
                }!
            }
            rounds += 1
        }
    }
    func stable() -> ([Int], Int) {
        let d = degrees(), unique = Set(d).sorted()
        return refine(d.map {
            unique.firstIndex(of: $0)!
        })
    }
    func leafString(_ colors: [Int]) -> String {
        var inverse = Array(repeating: 0, count: n), result = ""
        for v in 0..<n {
            inverse[colors[v]] = v
        }
        for i in 0..<n {
            for j in (i + 1)..<n {
                result += has(inverse[i], inverse[j]) ? "1" : "0"
            }
        }
        return result
    }
    func canonical() -> Canonical {
        var result = Canonical()
        func visit(_ colors: [Int]) {
            result.nodes += 1
            let k = colorCount(colors)
            if k == n {
                result.leaves += 1
                let text = leafString(colors)
                if result.winners.isEmpty || text > result.text {
                    result.text = text
                    result.label = colors
                    result.winners = [colors]
                }
                else if text == result.text {
                    result.winners.append(colors)
                }
                return
            }
            let cell = (0..<k).map {
                c in (colors.filter {
                    $0 == c
                }.count, c)
            }.filter {
                $0.0 > 1
            }.min {
                $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0
            }!.1
            for v in 0..<n where colors[v] == cell {
                visit(refine(individualize(colors, v)).0)
            }
        }
        visit(stable().0)
        return result
    }
    func invariants() -> Invariants {
        var seen = Array(repeating: false, count: n), sizes: [Int] = [], eccentricities: [Int] = [], girth: Int? = nil, bipartite = true
        for start in 0..<n {
            var distance = Array(repeating: -1, count: n), parent = Array(repeating: n, count: n), queue = [start], at = 0
            distance[start] = 0
            while at < queue.count {
                let u = queue[at]
                at += 1
                for v in 0..<n where has(u, v) {
                    if distance[v] < 0 {
                        distance[v] = distance[u] + 1
                        parent[v] = u
                        queue.append(v)
                    }
                    else {
                        if distance[u] % 2 == distance[v] % 2 {
                            bipartite = false
                        }
                        if parent[u] != v && parent[v] != u {
                            let length = distance[u] + distance[v] + 1
                            girth = min(girth ?? length, length)
                        }
                    }
                }
            }
            if !seen[start] {
                sizes.append(distance.filter {
                    $0 >= 0
                }.count)
                for v in 0..<n where distance[v] >= 0 {
                    seen[v] = true
                }
            }
            eccentricities.append(distance.max()!)
        }
        var triangles = 0
        for u in 0..<n {
            for v in (u + 1)..<n {
                for w in (v + 1)..<n where has(u, v) && has(v, w) && has(u, w) {
                    triangles += 1
                }
            }
        }
        return Invariants(degrees: degrees().sorted(by: >), triangles: triangles, sizes: sizes.sorted(by: >), girth: girth, diameter: sizes.count == 1 ? eccentricities.max()! : nil, radius: sizes.count == 1 ? eccentricities.min()! : nil, bipartite: bipartite)
    }
    func clique() -> [Int] {
        var best: [Int] = []
        for mask in 1..<(1 << n) {
            let vertices = (0..<n).filter {
                mask & (1 << $0) != 0
            }
            if vertices.count < best.count {
                continue
            }
            if vertices.allSatisfy({
                (mask ^ (1 << $0)) & ~adjacent[$0] == 0
            }) && (vertices.count > best.count || vertices.lexicographicallyPrecedes(best)) {
                best = vertices
            }
        }
        return best
    }
    func coloring() -> (Int, [Int]) {
        var colors: [Int] = []
        func find(_ limit: Int, _ used: Int) -> Bool {
            let v = colors.count
            if v == n {
                return true
            }
            for c in 0..<min(limit, used + 1) {
                if (0..<v).contains(where: {
                    has($0, v) && colors[$0] == c
                }) {
                    continue
                }
                colors.append(c)
                if find(limit, max(used, c + 1)) {
                    return true
                }
                colors.removeLast()
            }
            return false
        }
        for limit in 1...n {
            colors = []
            if find(limit, 0) {
                return (limit, colors)
            }
        }
        fatalError("no coloring")
    }
}
final class UnionFind {
    var parent: [Int]
    init(_ n: Int) {
        parent = Array(0..<n)
    }
    func root(_ v: Int) -> Int {
        if parent[v] != v {
            parent[v] = root(parent[v])
        }
        return parent[v]
    }
    func join(_ u: Int, _ v: Int) {
        let a = root(u), b = root(v)
        parent[a] = b
    }
    func orbits() -> [[Int]] {
        Dictionary(grouping: parent.indices, by: {
            root($0)
        }).values.sorted {
            $0[0] < $1[0]
        }
    }
}
func graphName(_ s: String) -> Bool {
    s.range(of: "\\A[a-z][a-z0-9]{0,7}\\z", options: .regularExpression) != nil
}
func number(_ s: String) -> Int? {
    s.range(of: "\\A(?:0|[1-9][0-9]{0,2})\\z", options: .regularExpression) != nil ? Int(s) : nil
}
func edge(_ s: String) -> (Int, Int)? {
    let p = s.components(separatedBy: "-")
    guard p.count == 2, let u = number(p[0]), let v = number(p[1]) else {
        return nil
    }
    return (u, v)
}
final class Lab {
    var registry: [String: Graph] = [:]
    func command(_ w: [String]) throws -> [String] {
        let c = w[0], a = Array(w.dropFirst()), count = a.count
        let defining = ["GRAPH","CYCLE","PATH","COMPLETE","BIPARTITE","STAR","WHEEL","PETERSEN","HYPERCUBE","CIRCULANT","GRID","COMPLEMENT","LINE","PRODUCT","UNION","RELABEL","INDUCED","CANONIZE"]
        let known = ["DELETE","LIST","SHOW","INVARIANTS","REFINE","CANON","ISO","AUT","SUBISO","CLASSIFY"]
        if !defining.contains(c) && !known.contains(c) {
            try fail("unknown command " + c)
        }
        let shape: Bool
        switch c {
            case "GRAPH","RELABEL": shape = count >= 2
            case "CIRCULANT","INDUCED": shape = count >= 3
            case "REFINE": shape = count >= 1
            case "LIST": shape = count == 0
            case "PETERSEN","DELETE","SHOW","INVARIANTS","CANON","AUT","CLASSIFY": shape = count == 1
            case "BIPARTITE","GRID","PRODUCT","UNION": shape = count == 3
            default: shape = count == 2
        }
        if !shape {
            try fail("bad arguments")
        }
        let references: [Int], numeric: [Int]
        switch c {
            case "COMPLEMENT","LINE","RELABEL","INDUCED","CANONIZE": references = [1]
            case "PRODUCT","UNION": references = [1,2]
            case "ISO","SUBISO": references = [0,1]
            case "DELETE","SHOW","INVARIANTS","REFINE","CANON","AUT": references = [0]
            default: references = []
        }
        switch c {
            case "GRAPH","CYCLE","PATH","COMPLETE","STAR","WHEEL","HYPERCUBE": numeric = [1]
            case "BIPARTITE","GRID": numeric = [1,2]
            case "CIRCULANT","REFINE": numeric = Array(1..<count)
            case "RELABEL","INDUCED": numeric = Array(2..<count)
            case "CLASSIFY": numeric = [0]
            default: numeric = []
        }
        for (i, s) in a.enumerated() {
            let valid = numeric.contains(i) ? number(s) != nil : (c == "GRAPH" && i >= 2 ? edge(s) != nil : graphName(s))
            if !valid {
                try fail("bad arguments")
            }
        }
        for i in references {
            if registry[a[i]] == nil {
                try fail("no graph " + a[i])
            }
        }
        func num(_ i: Int) -> Int {
            number(a[i])!
        }
        func graph(_ i: Int) -> Graph {
            registry[a[i]]!
        }
        func bounded(_ n: Int, _ minimum: Int = 1) throws -> Int {
            if n < minimum {
                try fail("bad value")
            }
            if n > 16 {
                try fail("too large")
            }
            return n
        }
        if defining.contains(c) {
            let g: Graph
            switch c {
                case "GRAPH","CYCLE","PATH","COMPLETE","CIRCULANT": g = Graph(try bounded(num(1), c == "CYCLE" || c == "CIRCULANT" ? 3 : 1))
                case "STAR","WHEEL": if num(1) < (c == "STAR" ? 1 : 3) {
                    try fail("bad value")
                }
                g = Graph(try bounded(num(1) + 1))
                case "BIPARTITE","GRID": if num(1) == 0 || num(2) == 0 {
                    try fail("bad value")
                }
                g = Graph(try bounded(c == "GRID" ? num(1) * num(2) : num(1) + num(2)))
                case "HYPERCUBE": if num(1) == 0 {
                    try fail("bad value")
                }
                if num(1) > 4 {
                    try fail("too large")
                }
                g = Graph(1 << num(1))
                case "PETERSEN": g = Graph(10)
                case "COMPLEMENT","RELABEL","CANONIZE": g = Graph(graph(1).n)
                case "LINE": let m = graph(1).edges().count
                if m == 0 {
                    try fail("no edges")
                }
                g = Graph(try bounded(m))
                case "INDUCED": g = Graph(count - 2)
                case "PRODUCT": g = Graph(try bounded(graph(1).n * graph(2).n))
                case "UNION": g = Graph(try bounded(graph(1).n + graph(2).n))
                default: fatalError("unknown definition")
            }
            let n = g.n
            switch c {
                case "GRAPH":
                for s in a.dropFirst(2) {
                    let (u,v) = edge(s)!
                    if u >= n || v >= n || u == v {
                        try fail("bad edge " + s)
                    }
                    if g.has(u,v) {
                        try fail("duplicate edge " + s)
                    }
                    g.join(u,v)
                }
                case "CYCLE","PATH": for i in 0..<(n - 1) {
                    g.join(i,i + 1)
                }
                if c == "CYCLE" {
                    g.join(n - 1,0)
                }
                case "COMPLETE": for i in 0..<n {
                    for j in (i + 1)..<n {
                        g.join(i,j)
                    }
                }
                case "BIPARTITE": for i in 0..<num(1) {
                    for j in num(1)..<n {
                        g.join(i,j)
                    }
                }
                case "STAR","WHEEL": for i in 1..<n {
                    g.join(0,i)
                }
                if c == "WHEEL" {
                    for i in 1..<(n - 1) {
                        g.join(i,i + 1)
                    }
                    g.join(n - 1,1)
                }
                case "PETERSEN": for i in 0..<5 {
                    g.join(i,(i + 1) % 5)
                    g.join(i,i + 5)
                    g.join(i + 5,5 + (i + 2) % 5)
                }
                case "HYPERCUBE": for u in 0..<n {
                    for bit in 0..<num(1) {
                        g.join(u,u ^ (1 << bit))
                    }
                }
                case "CIRCULANT":
                let jumps = (2..<count).map(num)
                if jumps.contains(where: {
                    $0 == 0 || 2 * $0 > n
                }) || zip(jumps,jumps.dropFirst()).contains(where: {
                    $0.0 >= $0.1
                }) {
                    try fail("bad value")
                }
                for u in 0..<n {
                    for j in jumps {
                        g.join(u,(u + j) % n)
                    }
                }
                case "GRID": for x in 0..<num(1) {
                    for y in 0..<num(2) {
                        let u = x * num(2) + y
                        if y + 1 < num(2) {
                            g.join(u,u + 1)
                        }
                        if x + 1 < num(1) {
                            g.join(u,u + num(2))
                        }
                    }
                }
                case "COMPLEMENT": let old = graph(1)
                for u in 0..<n {
                    for v in (u + 1)..<n where !old.has(u,v) {
                        g.join(u,v)
                    }
                }
                case "LINE": let e = graph(1).edges()
                for i in 0..<n {
                    for j in (i + 1)..<n where e[i].0 == e[j].0 || e[i].0 == e[j].1 || e[i].1 == e[j].0 || e[i].1 == e[j].1 {
                        g.join(i,j)
                    }
                }
                case "PRODUCT": let x = graph(1), y = graph(2)
                for u in 0..<x.n {
                    for (v,w) in y.edges() {
                        g.join(u * y.n + v,u * y.n + w)
                    }
                }
                for (u,v) in x.edges() {
                    for w in 0..<y.n {
                        g.join(u * y.n + w,v * y.n + w)
                    }
                }
                case "UNION": let x = graph(1)
                for (u,v) in x.edges() {
                    g.join(u,v)
                }
                for (u,v) in graph(2).edges() {
                    g.join(u + x.n,v + x.n)
                }
                case "RELABEL","CANONIZE":
                let old = graph(1), p = c == "CANONIZE" ? old.canonical().label : (2..<count).map(num)
                if p.count != n || Set(p) != Set(0..<n) {
                    try fail("bad permutation")
                }
                for (u,v) in old.edges() {
                    g.join(p[u],p[v])
                }
                case "INDUCED":
                let old = graph(1), p = (2..<count).map(num)
                if p.contains(where: {
                    $0 >= old.n
                }) || Set(p).count != p.count {
                    try fail("bad vertices")
                }
                for u in 0..<n {
                    for v in (u + 1)..<n where old.has(p[u],p[v]) {
                        g.join(u,v)
                    }
                }
                default: break
            }
            let output = "\(registry[a[0]] == nil ? "defined" : "redefined") \(a[0]) n \(n) m \(g.edges().count)"
            registry[a[0]] = g
            return [output]
        }
        if c == "LIST" {
            return ["graphs \(registry.count)"] + registry.keys.sorted().map {
                "\($0) n \(registry[$0]!.n) m \(registry[$0]!.edges().count)"
            }
        }
        if c == "DELETE" {
            registry.removeValue(forKey: a[0])
            return ["deleted " + a[0]]
        }
        if c == "CLASSIFY" {
            let n = num(0)
            if n == 0 {
                try fail("bad value")
            }
            if n > 5 {
                try fail("too large")
            }
            let pairs = n * (n - 1) / 2
            var classes = Array(repeating: Set<String>(), count: pairs + 1)
            for mask in 0..<(1 << pairs) {
                let g = Graph(n)
                var bit = 0
                for u in 0..<n {
                    for v in (u + 1)..<n {
                        if mask & (1 << bit) != 0 {
                            g.join(u,v)
                        }
                        bit += 1
                    }
                }
                classes[mask.nonzeroBitCount].insert(g.canonical().text)
            }
            return ["classify \(n) total \(classes.reduce(0) { $0 + $1.count })"] + classes.enumerated().map {
                m, s in "edges \(m) count \(s.count) " + s.sorted().map {
                    $0.isEmpty ? "-" : $0
                }.joined(separator: " ")
            }
        }
        let g = graph(0), n = g.n
        switch c {
            case "SHOW": return ["graph \(a[0]) n \(n) m \(g.edges().count)"] + (0..<n).map {
                u in "\(u):" + (0..<n).filter {
                    g.has(u,$0)
                }.map {
                    " \($0)"
                }.joined()
            }
            case "INVARIANTS":
            let x = g.invariants()
            var out = ["invariants " + a[0],"degrees " + numbers(x.degrees),"edges \(g.edges().count) triangles \(x.triangles)","components \(x.sizes.count) sizes " + numbers(x.sizes),"girth \(shown(x.girth,"none")) diameter \(shown(x.diameter,"INF")) radius \(shown(x.radius,"INF"))","bipartite " + yes(x.bipartite)]
            if n > 12 {
                out += ["clique -","chromatic -"]
            } else {
                let clique = g.clique(), (chi,colors) = g.coloring()
                out += ["clique \(clique.count) " + numbers(clique),"chromatic \(chi) " + numbers(colors)]
            }
            return out
            case "REFINE":
            let vertices = (1..<count).map(num)
            if vertices.contains(where: {
                $0 >= n
            }) {
                try fail("bad vertices")
            }
            var (colors,rounds) = g.stable()
            for v in vertices {
                if colors.filter({
                    $0 == colors[v]
                }).count == 1 {
                    try fail("singleton \(v)")
                }
                let (next,r) = g.refine(individualize(colors,v))
                colors = next
                rounds += r
            }
            let k = colorCount(colors)
            return ["refine \(a[0]) rounds \(rounds) cells \(k)"] + (0..<k).map {
                cell in "\(cell): " + numbers((0..<n).filter {
                    colors[$0] == cell
                })
            }
            case "CANON": let x = g.canonical()
            return ["canon \(a[0]) nodes \(x.nodes) leaves \(x.leaves)","labels " + numbers(x.label),"string " + (x.text.isEmpty ? "-" : x.text)]
            case "ISO":
            let h = graph(1), x = g.invariants(), y = h.invariants()
            let difference: String?
            if n != h.n {
                difference = "vertices \(n) \(h.n)"
            }
            else if g.edges().count != h.edges().count {
                difference = "edges \(g.edges().count) \(h.edges().count)"
            }
            else if x.degrees != y.degrees {
                difference = "degrees"
            }
            else if x.triangles != y.triangles {
                difference = "triangles \(x.triangles) \(y.triangles)"
            }
            else if x.sizes.count != y.sizes.count {
                difference = "components \(x.sizes.count) \(y.sizes.count)"
            }
            else if x.girth != y.girth {
                difference = "girth \(shown(x.girth,"none")) \(shown(y.girth,"none"))"
            }
            else if x.diameter != y.diameter {
                difference = "diameter \(shown(x.diameter,"INF")) \(shown(y.diameter,"INF"))"
            }
            else if x.bipartite != y.bipartite {
                difference = "bipartite \(yes(x.bipartite)) \(yes(y.bipartite))"
            }
            else {
                difference = nil
            }
            if let difference {
                return ["not isomorphic " + difference]
            }
            let (p,r) = g.stable(), (q,s) = h.stable()
            func sizes(_ colors: [Int]) -> [Int] {
                (0..<colorCount(colors)).map {
                    c in colors.filter {
                        $0 == c
                    }.count
                }
            }
            if r != s || sizes(p) != sizes(q) {
                return ["not isomorphic refinement"]
            }
            let ca = g.canonical(), cb = h.canonical()
            if ca.text != cb.text {
                return ["not isomorphic canonical"]
            }
            return ["isomorphic","mapping " + numbers(ca.label.map {
                cb.label.firstIndex(of: $0)!
            })]
            case "AUT":
            let result = g.canonical(), e = g.edges(), vertices = UnionFind(n), edgeSets = UnionFind(e.count)
            var inverse = Array(repeating: 0, count: n)
            for v in 0..<n {
                inverse[result.label[v]] = v
            }
            for label in result.winners {
                let map = label.map {
                    inverse[$0]
                }
                for v in 0..<n {
                    vertices.join(v,map[v])
                }
                for (i,(u,v)) in e.enumerated() {
                    let a = min(map[u],map[v]), b = max(map[u],map[v])
                    edgeSets.join(i,e.firstIndex {
                        $0.0 == a && $0.1 == b
                    }!)
                }
            }
            let vo = vertices.orbits(), eo = edgeSets.orbits()
            var out = ["aut \(a[0]) order \(result.winners.count)","vertex orbits \(vo.count)"] + vo.map {
                "orbit " + numbers($0)
            }
            out += ["edge orbits \(eo.count)"] + eo.map {
                orbit in "orbit " + orbit.map {
                    "\(e[$0].0)-\(e[$0].1)"
                }.joined(separator: " ")
            }
            out.append("transitive vertex \(yes(vo.count == 1)) edge \(yes(eo.count == 1))")
            return out
            case "SUBISO":
            let target = graph(1)
            var mapping: [Int] = [], embeddings = 0, inducedCount = 0, first: [([Int],Bool)] = []
            func enumerate(_ used: Int, _ induced: Bool) {
                let v = mapping.count
                if v == n {
                    embeddings += 1
                    if induced {
                        inducedCount += 1
                    }
                    if first.count < 5 {
                        first.append((mapping,induced))
                    }
                    return
                }
                for w in 0..<target.n {
                    if used & (1 << w) != 0 || (0..<v).contains(where: {
                        g.has($0,v) && !target.has(mapping[$0],w)
                    }) {
                        continue
                    }
                    let next = induced && (0..<v).allSatisfy {
                        g.has($0,v) == target.has(mapping[$0],w)
                    }
                    mapping.append(w)
                    enumerate(used | (1 << w),next)
                    mapping.removeLast()
                }
            }
            if n <= target.n {
                enumerate(0,true)
            }
            let order = g.canonical().winners.count
            return ["subiso \(a[0]) \(a[1]) embeddings \(embeddings) induced \(inducedCount)","copies \(embeddings / order) induced \(inducedCount / order)"] + first.map {
                map, induced in "embedding " + numbers(map) + (induced ? " induced" : "")
            }
            default: fatalError("unknown command")
        }
    }
}
let lab = Lab()
for _ in 0..<Int(readLine()!)! {
    do {
        for line in try lab.command(readLine()!.components(separatedBy: " ")) {
            print(line)
        }
    }
    catch let p as Problem {
        print(p.text)
    }
    catch {
        fatalError("unexpected error")
    }
}
