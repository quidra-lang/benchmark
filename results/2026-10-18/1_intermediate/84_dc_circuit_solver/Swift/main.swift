import Foundation

struct Problem: Error {
    let reason: String
}

func fail(_ reason: String) throws -> Never {
    throw Problem(reason: reason)
}

struct Q: Comparable, CustomStringConvertible {
    let p: Int
    let q: Int

    init(_ numerator: Int, _ denominator: Int = 1) {
        var a = abs(numerator)
        var b = abs(denominator)
        while b != 0 {
            let r = a % b
            a = b
            b = r
        }
        p = (denominator < 0 ? -numerator : numerator) / a
        q = abs(denominator) / a
    }
    static func + (a: Q, b: Q) -> Q {
        Q(a.p * b.q + b.p * a.q, a.q * b.q)
    }
    static func - (a: Q, b: Q) -> Q {
        Q(a.p * b.q - b.p * a.q, a.q * b.q)
    }
    static func * (a: Q, b: Q) -> Q {
        Q(a.p * b.p, a.q * b.q)
    }
    static func / (a: Q, b: Q) -> Q {
        Q(a.p * b.q, a.q * b.p)
    }
    static prefix func - (a: Q) -> Q {
        Q(-a.p, a.q)
    }
    static func < (a: Q, b: Q) -> Bool {
        a.p * b.q < b.p * a.q
    }
    var description: String {
        q == 1 ? String(p) : "\(p)/\(q)"
    }
    var value: String {
        let h = abs(p) * 1000000 / q
        return "\(description) (\(p < 0 ? "-" : "")\(h / 1000000)." + String(format: "%06d", h % 1000000) + ")"
    }
}
let zero = Q(0)
let one = Q(1)

func digits(_ s: String) -> Bool {
    !s.isEmpty && s.utf8.allSatisfy {
        $0 >= 48 && $0 <= 57
    }
}

func number(_ raw: String) throws -> Q {
    var s = raw
    var factor = one
    for (suffix, multiplier) in [("meg", Q(1000000)), ("k", Q(1000)), ("m", Q(1, 1000)), ("u", Q(1, 1000000))] {
        if s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            factor = multiplier
            break
        }
    }
    if s.hasPrefix("-") {
        s = String(s.dropFirst())
        factor = -factor
    }
    let value: Q
    if digits(s) {
        value = Q(Int(s)!)
    } else if s.contains(".") {
        let p = s.components(separatedBy: ".")
        if p.count != 2 || !digits(p[0]) || !digits(p[1]) {
            try fail("invalid value \(raw)")
        }
        value = Q(Int(p[0] + p[1])!, p[1].reduce(1) {
            n, _ in n * 10
        })
    } else if s.contains("/") {
        let p = s.components(separatedBy: "/")
        if p.count != 2 || !digits(p[0]) || !digits(p[1]) || Int(p[1])! == 0 {
            try fail("invalid value \(raw)")
        }
        value = Q(Int(p[0])!, Int(p[1])!)
    } else {
        try fail("invalid value \(raw)")
    }
    return value * factor
}

func validNode(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return s == "0" || !b.isEmpty && b.count <= 8 && b[0] >= 97 && b[0] <= 122 && b.allSatisfy {
        $0 >= 97 && $0 <= 122 || $0 >= 48 && $0 <= 57
    }
}

struct Element {
    let name: String
    let nodes: [String]
    let reference: String
    var value: Q
    var kind: Character {
        name.first!
    }
    var a: String {
        nodes[0]
    }
    var b: String {
        nodes[1]
    }
    var voltage: Bool {
        "VEH".contains(kind)
    }
    var independent: Bool {
        "VI".contains(kind)
    }
}

final class Union {
    var parent: [String: String]

    init(_ nodes: [String]) {
        parent = Dictionary(nodes.map {
            ($0, $0)
        }, uniquingKeysWith: {
            a, _ in a
        })
    }

    func root(_ x: String) -> String {
        var p = x
        while parent[p]! != p {
            p = parent[p]!
        }
        return p
    }

    func join(_ a: String, _ b: String) {
        let x = root(a)
        let y = root(b)
        if x < y {
            parent[y] = x
        } else {
            parent[x] = y
        }
    }
}

func reach(_ start: String, _ edges: [(String, String)]) -> Set<String> {
    var found: Set<String> = [start]
    var queue = [start]
    var at = 0
    while at < queue.count {
        let a = queue[at]
        at += 1
        for (u, v) in edges {
            let b: String
            if a == u {
                b = v
            } else if a == v {
                b = u
            } else {
                continue
            }
            if found.insert(b).inserted {
                queue.append(b)
            }
        }
    }
    return found
}

func solve(_ a: [[Q]], _ b: [Q]) -> [Q]? {
    let n = b.count
    var m = a.enumerated().map {
        i, row in row + [b[i]]
    }
    for k in 0..<n {
        guard let r = (k..<n).first(where: {
            m[$0][k].p != 0
        }) else {
            return nil
        }
        m.swapAt(k, r)
        let pivot = m[k][k]
        for j in 0...n {
            m[k][j] = m[k][j] / pivot
        }
        for i in 0..<n where i != k && m[i][k].p != 0 {
            let f = m[i][k]
            for j in 0...n {
                m[i][j] = m[i][j] - f * m[k][j]
            }
        }
    }
    return m.map {
        $0[n]
    }
}

final class Equations {
    var nodes = [String]()
    var sources = [Element]()
    var labels = [String]()
    var index = [String: Int]()
    var a = [[Q]]()
    var b = [Q]()

    init(_ elements: [Element]) {
        nodes = Set(elements.flatMap(\.nodes).filter {
            $0 != "0"
        }).sorted()
        sources = elements.filter(\.voltage)
        labels = nodes + sources.map(\.name)
        index = Dictionary(uniqueKeysWithValues: labels.enumerated().map {
            ($0.element, $0.offset)
        })
        a = Array(repeating: Array(repeating: zero, count: labels.count), count: labels.count)
        b = Array(repeating: zero, count: labels.count)
        for e in elements {
            let w = e.value
            switch e.kind {
            case "R":
                let g = one / w
                add(e.a, e.a, g)
                add(e.b, e.b, g)
                add(e.a, e.b, -g)
                add(e.b, e.a, -g)
            case "I":
                rhs(e.a, -w)
                rhs(e.b, w)
            case "G":
                add(e.a, e.nodes[2], w)
                add(e.b, e.nodes[3], w)
                add(e.a, e.nodes[3], -w)
                add(e.b, e.nodes[2], -w)
            case "F":
                add(e.a, e.reference, w)
                add(e.b, e.reference, -w)
            default:
                add(e.a, e.name, one)
                add(e.name, e.a, one)
                add(e.b, e.name, -one)
                add(e.name, e.b, -one)
                switch e.kind {
                case "V":
                    rhs(e.name, w)
                case "E":
                    add(e.name, e.nodes[2], -w)
                    add(e.name, e.nodes[3], w)
                default:
                    add(e.name, e.reference, -w)
                }
            }
        }
    }

    func add(_ row: String, _ column: String, _ value: Q) {
        if row != "0" && column != "0" {
            let i = index[row]!
            let j = index[column]!
            a[i][j] = a[i][j] + value
        }
    }

    func addRHS(_ rhs: inout [Q], _ row: String, _ value: Q) {
        if row != "0" {
            let i = index[row]!
            rhs[i] = rhs[i] + value
        }
    }

    func rhs(_ row: String, _ value: Q) {
        if row != "0" {
            let i = index[row]!
            b[i] = b[i] + value
        }
    }

    func v(_ y: [Q], _ node: String) -> Q {
        node == "0" ? zero : y[index[node]!]
    }

    func injection(_ a: String, _ b: String) -> [Q] {
        var rhs = Array(repeating: zero, count: labels.count)
        addRHS(&rhs, a, one)
        addRHS(&rhs, b, -one)
        return solve(self.a, rhs)!
    }

    func alone(_ e: Element, _ unit: Bool = false) -> [Q] {
        var rhs = Array(repeating: zero, count: labels.count)
        let w = unit ? one : e.value
        if e.kind == "V" {
            addRHS(&rhs, e.name, w)
        } else {
            addRHS(&rhs, e.a, -w)
            addRHS(&rhs, e.b, w)
        }
        return solve(a, rhs)!
    }

    func current(_ e: Element, _ y: [Q]) -> Q {
        switch e.kind {
        case "R":
            return (v(y, e.a) - v(y, e.b)) / e.value
        case "I":
            return e.value
        case "G":
            return e.value * (v(y, e.nodes[2]) - v(y, e.nodes[3]))
        case "F":
            return e.value * y[index[e.reference]!]
        default:
            return y[index[e.name]!]
        }
    }
}

struct Resistor {
    let name: String
    let a: String
    let b: String
    let value: Q
}

final class Circuit {
    var elements = [Element]()
    var nodes: [String] {
        Set(elements.flatMap(\.nodes).filter {
            $0 != "0"
        }).sorted()
    }

    func get(_ name: String) throws -> Int {
        guard let i = elements.firstIndex(where: {
            $0.name == name
        }) else {
            try fail("unknown element \(name)")
        }
        return i
    }

    func node(_ name: String) throws {
        if name != "0" && !nodes.contains(name) {
            try fail("unknown node \(name)")
        }
    }

    func floating() -> [String] {
        let reached = reach("0", elements.filter {
            "RVEH".contains($0.kind)
        }.map {
            ($0.a, $0.b)
        })
        return nodes.filter {
            !reached.contains($0)
        }
    }

    func loops() -> [String] {
        let u = Union(nodes + ["0"])
        var out = [String]()
        for e in elements where e.voltage {
            if u.root(e.a) == u.root(e.b) {
                out.append(e.name)
            }
            u.join(e.a, e.b)
        }
        return out
    }

    func structure() throws {
        if nodes.isEmpty {
            try fail("no nodes")
        }
        if let n = floating().first {
            try fail("floating node \(n)")
        }
        if let n = loops().first {
            try fail("voltage source loop at \(n)")
        }
    }

    func add(_ w: [String]) throws {
        let name = w[0]
        let kind = name.first!
        if !"RVIEGFH".contains(kind) {
            try fail("unknown element type \(name)")
        }
        let count = "RVI".contains(kind) ? 4 : "EG".contains(kind) ? 6 : 5
        if w.count != count {
            try fail("wrong field count for \(name)")
        }
        if elements.contains(where: {
            $0.name == name
        }) {
            try fail("duplicate element \(name)")
        }
        let ns = Array(w[1..<("EG".contains(kind) ? 5 : 3)])
        for n in ns {
            if !validNode(n) {
                try fail("invalid node \(n)")
            }
        }
        let reference = "FH".contains(kind) ? w[3] : ""
        if "FH".contains(kind) && !elements.contains(where: {
            $0.name == reference && $0.kind == "V"
        }) {
            try fail("unknown voltage source \(reference)")
        }
        let value = try number(w.last!)
        if kind == "R" && value <= zero {
            try fail("nonpositive resistance \(name)")
        }
        elements.append(Element(name: name, nodes: ns, reference: reference, value: value))
    }

    func resistance(_ a: String, _ b: String) -> [String] {
        let u = Union(nodes + ["0"])
        for e in elements where e.kind == "V" {
            u.join(e.a, e.b)
        }
        let x = u.root(a)
        let y = u.root(b)
        if x == y {
            return ["Req = \(zero.value)"]
        }
        let edges = elements.filter {
            $0.kind == "R" && u.root($0.a) != u.root($0.b)
        }
        let connected = reach(x, edges.map {
            (u.root($0.a), u.root($0.b))
        })
        if !connected.contains(y) {
            return ["Req = INFINITE"]
        }
        let groups = connected.filter {
            $0 != y
        }.sorted()
        let index = Dictionary(uniqueKeysWithValues: groups.enumerated().map {
            ($0.element, $0.offset)
        })
        var matrix = Array(repeating: Array(repeating: zero, count: groups.count), count: groups.count)
        var rhs = Array(repeating: zero, count: groups.count)

        func stamp(_ p: String, _ q: String, _ v: Q) {
            if p != y && q != y {
                let i = index[p]!
                let j = index[q]!
                matrix[i][j] = matrix[i][j] + v
            }
        }
        for e in edges where connected.contains(u.root(e.a)) {
            let p = u.root(e.a)
            let q = u.root(e.b)
            let g = one / e.value
            stamp(p, p, g)
            stamp(q, q, g)
            stamp(p, q, -g)
            stamp(q, p, -g)
        }
        rhs[index[x]!] = one
        return ["Req = \(solve(matrix, rhs)![index[x]!].value)"]
    }

    func reduce(_ a: String, _ b: String) -> [String] {
        if a == b {
            return ["Req = \(zero.value)"]
        }
        var list = elements.filter {
            $0.kind == "R"
        }.map {
            Resistor(name: $0.name, a: $0.a, b: $0.b, value: $0.value)
        }
        let connected = reach(a, list.map {
            ($0.a, $0.b)
        })
        if !connected.contains(b) {
            return ["Req = INFINITE"]
        }
        list = list.filter {
            connected.contains($0.a)
        }
        var out = [String]()
        var created = 0
        while true {
            if let i = list.firstIndex(where: {
                $0.a == $0.b
            }) {
                out.append("remove \(list.remove(at: i).name)")
                continue
            }
            var degree = [String: Int]()
            for r in list {
                degree[r.a, default: 0] += 1
                degree[r.b, default: 0] += 1
            }
            if let p = degree.keys.sorted().first(where: {
                $0 != a && $0 != b && degree[$0] == 1
            }) {
                let i = list.firstIndex {
                    $0.a == p || $0.b == p
                }!
                out.append("remove \(list.remove(at: i).name)")
                continue
            }
            var pair: (Int, Int)?
            pairs: for i in list.indices {
                for j in (i + 1)..<list.count {
                    let x = list[i]
                    let y = list[j]
                    if x.a == y.a && x.b == y.b || x.a == y.b && x.b == y.a {
                        pair = (i, j)
                        break pairs
                    }
                }
            }
            let parallel = pair != nil
            var p: String?
            if !parallel {
                p = degree.keys.sorted().first {
                    $0 != a && $0 != b && degree[$0] == 2
                }
                if let p = p {
                    let indices = list.indices.filter {
                        list[$0].a == p || list[$0].b == p
                    }
                    pair = (indices[0], indices[1])
                }
            }
            guard let (i, j) = pair else {
                break
            }
            let x = list[i]
            let y = list[j]
            let value = parallel ? x.value * y.value / (x.value + y.value) : x.value + y.value
            created += 1
            let r = Resistor(name: "#\(created)", a: parallel || x.a != p! ? x.a : x.b, b: parallel ? x.b : y.a != p! ? y.a : y.b, value: value)
            out.append("\(r.name) = \(x.name) \(parallel ? "||" : "+") \(y.name) = \(value.value)")
            list.remove(at: j)
            list.remove(at: i)
            list.append(r)
        }
        out.append(list.count == 1 ? "Req = \(list[0].value.value)" : "not series-parallel: \(list.count) resistors remain")
        return out
    }

    func command(_ w: [String]) throws -> [String] {
        let c = w[0]
        let counts = [".OP": 0, ".CURRENT": 1, ".VOLTAGE": 2, ".POWER": 0, ".KCL": 1, ".THEVENIN": 2, ".NORTON": 2, ".MAXPOWER": 2, ".TF": 2, ".SENS": 1, ".ZPARAM": 4, ".SUPERPOSITION": 1, ".SWEEP": 5, ".MATRIX": 0, ".REQ": 2, ".REDUCE": 2, ".CHECK": 0, ".ALTER": 2, ".DELETE": 1, ".CLEAR": 0, ".NODES": 0, ".PRINT": 0]
        guard let count = counts[c] else {
            try fail("unknown command \(c)")
        }
        if w.count != count + 1 {
            try fail("wrong argument count for \(c)")
        }
        switch c {
        case ".CLEAR":
            let n = elements.count
            elements = []
            return ["cleared \(n) elements"]
        case ".PRINT":
            return elements.isEmpty ? ["empty netlist"] : elements.map {
                e in ([e.name] + e.nodes + (e.reference.isEmpty ? [] : [e.reference]) + [e.value.description]).joined(separator: " ")
            }
        case ".NODES":
            let ns = Set(elements.flatMap(\.nodes)).sorted()
            return ns.isEmpty ? ["no nodes"] : ns.map {
                n in n + ": " + elements.filter {
                    $0.nodes.contains(n)
                }.map(\.name).joined(separator: " ")
            }
        case ".DELETE":
            let i = try get(w[1])
            if let e = elements.first(where: {
                "FH".contains($0.kind) && $0.reference == w[1]
            }) {
                try fail("\(w[1]) is referenced by \(e.name)")
            }
            elements.remove(at: i)
            return ["deleted \(w[1])"]
        case ".ALTER":
            let i = try get(w[1])
            let v = try number(w[2])
            if elements[i].kind == "R" && v <= zero {
                try fail("nonpositive resistance \(w[1])")
            }
            let old = elements[i].value
            elements[i].value = v
            return ["altered \(w[1]): \(old) -> \(v)"]
        case ".CHECK":
            if nodes.isEmpty {
                return ["no nodes"]
            }
            var out = [String]()
            for n in nodes {
                if elements.reduce(0, {
                    $0 + ($1.a == n ? 1 : 0) + ($1.b == n ? 1 : 0)
                }) < 2 {
                    out.append("dangling node \(n)")
                }
            }
            out += floating().map {
                "floating node \($0)"
            }
            out += loops().map {
                "voltage source loop at \($0)"
            }
            if out.isEmpty {
                let eq = Equations(elements)
                if solve(eq.a, eq.b) == nil {
                    out.append("singular matrix")
                }
            }
            return out.isEmpty ? ["ok"] : out
        case ".REQ", ".REDUCE":
            try node(w[1])
            try node(w[2])
            return c == ".REQ" ? resistance(w[1], w[2]) : reduce(w[1], w[2])
        case ".SWEEP":
            let i = try get(w[1])
            let from = try number(w[2])
            let to = try number(w[3])
            let step = try number(w[4])
            try node(w[5])
            if step <= zero {
                try fail("invalid sweep step")
            }
            if from > to {
                try fail("invalid sweep range")
            }
            let ratio = (to - from) / step
            let k = ratio.p / ratio.q + 1
            if k > 20 {
                try fail("too many sweep points")
            }
            if elements[i].kind == "R" && from <= zero {
                try fail("nonpositive resistance \(w[1])")
            }
            try structure()
            return (0..<k).map {
                j in
                var es = elements
                let x = from + Q(j) * step
                es[i].value = x
                let eq = Equations(es)
                return "\(w[1]) = \(x): " + (solve(eq.a, eq.b).map {
                    "V(\(w[5])) = \(eq.v($0, w[5]).value)"
                } ?? "singular matrix")
            }
        default:
            break
        }
        switch c {
        case ".CURRENT":
            _ = try get(w[1])
        case ".VOLTAGE", ".THEVENIN", ".NORTON", ".MAXPOWER":
            try node(w[1])
            try node(w[2])
        case ".KCL", ".SENS", ".SUPERPOSITION":
            try node(w[1])
        case ".ZPARAM":
            for n in w.dropFirst() {
                try node(n)
            }
        case ".TF":
            try node(w[1])
            let e = elements[try get(w[2])]
            if !e.independent {
                try fail("not an independent source \(e.name)")
            }
        default:
            break
        }
        try structure()
        let eq = Equations(elements)
        if c == ".MATRIX" {
            return ["unknowns: " + (eq.nodes.map {
                "V(\($0))"
            } + eq.sources.map {
                "I(\($0.name))"
            }).joined(separator: " ")] + eq.labels.indices.map {
                i in eq.labels[i] + ": " + eq.a[i].map(\.description).joined(separator: " ") + " | \(eq.b[i])"
            }
        }
        guard let y = solve(eq.a, eq.b) else {
            try fail("singular matrix")
        }

        func v(_ n: String) -> Q {
            eq.v(y, n)
        }
        var out = [String]()
        switch c {
        case ".OP":
            for n in eq.nodes {
                out.append("V(\(n)) = \(v(n).value)")
            }
            for e in eq.sources {
                out.append("I(\(e.name)) = \(eq.current(e, y).value)")
            }
        case ".CURRENT":
            out.append("I(\(w[1])) = \(eq.current(elements[try get(w[1])], y).value)")
        case ".VOLTAGE":
            out.append("V(\(w[1]),\(w[2])) = \((v(w[1]) - v(w[2])).value)")
        case ".POWER":
            var absorbed = zero
            var delivered = zero
            var total = zero
            for e in elements {
                let p = (v(e.a) - v(e.b)) * eq.current(e, y)
                out.append("P(\(e.name)) = \(p.value)")
                if p > zero {
                    absorbed = absorbed + p
                }
                if p < zero {
                    delivered = delivered - p
                }
                total = total + p
            }
            out += ["absorbed = \(absorbed.value)", "delivered = \(delivered.value)", "total = \(total.value)"]
        case ".KCL":
            var sum = zero
            for e in elements where e.a == w[1] || e.b == w[1] {
                let i = e.a == w[1] && e.b == w[1] ? zero : e.a == w[1] ? eq.current(e, y) : -eq.current(e, y)
                sum = sum + i
                out.append("I(\(e.name)) leaving \(w[1]) = \(i.value)")
            }
            out.append("sum = \(sum.value)")
        case ".THEVENIN", ".NORTON", ".MAXPOWER":
            let z = eq.injection(w[1], w[2])
            let voltage = v(w[1]) - v(w[2])
            let resistance = eq.v(z, w[1]) - eq.v(z, w[2])
            if c == ".NORTON" && resistance.p == 0 {
                try fail("zero thevenin resistance")
            }
            if c == ".MAXPOWER" && resistance <= zero {
                try fail("nonpositive thevenin resistance")
            }
            if c == ".THEVENIN" {
                out += ["Vth = \(voltage.value)", "Rth = \(resistance.value)"]
            } else if c == ".NORTON" {
                out += ["In = \((voltage / resistance).value)", "Rn = \(resistance.value)"]
            } else {
                out += ["RL = \(resistance.value)", "Pmax = \((voltage * voltage / (Q(4) * resistance)).value)"]
            }
        case ".TF":
            let e = elements[try get(w[2])]
            let z = eq.alone(e, true)
            out.append("gain = \(eq.v(z, w[1]).value)")
            if e.kind == "V" {
                let i = z[eq.index[e.name]!]
                out.append("input resistance = " + (i.p == 0 ? "INFINITE" : (-one / i).value))
            } else {
                out.append("input resistance = \((eq.v(z, e.b) - eq.v(z, e.a)).value)")
            }
            out.append("output resistance = \(eq.v(eq.injection(w[1], "0"), w[1]).value)")
        case ".SENS":
            for e in elements {
                var d = Array(repeating: zero, count: eq.labels.count)
                switch e.kind {
                case "R":
                    let t = eq.current(e, y) / e.value
                    eq.addRHS(&d, e.a, t)
                    eq.addRHS(&d, e.b, -t)
                case "I":
                    eq.addRHS(&d, e.a, -one)
                    eq.addRHS(&d, e.b, one)
                case "G", "F":
                    let t = e.kind == "G" ? v(e.nodes[2]) - v(e.nodes[3]) : y[eq.index[e.reference]!]
                    eq.addRHS(&d, e.a, -t)
                    eq.addRHS(&d, e.b, t)
                case "V":
                    eq.addRHS(&d, e.name, one)
                case "E":
                    eq.addRHS(&d, e.name, v(e.nodes[2]) - v(e.nodes[3]))
                default:
                    eq.addRHS(&d, e.name, y[eq.index[e.reference]!])
                }
                out.append("dV(\(w[1]))/d\(e.name) = \(eq.v(solve(eq.a, d)!, w[1]).value)")
            }
        case ".ZPARAM":
            let z1 = eq.injection(w[1], w[2])
            let z2 = eq.injection(w[3], w[4])
            for (name, z, a, b) in [("z11", z1, w[1], w[2]), ("z12", z2, w[1], w[2]), ("z21", z1, w[3], w[4]), ("z22", z2, w[3], w[4])] {
                out.append("\(name) = \((eq.v(z, a) - eq.v(z, b)).value)")
            }
        case ".SUPERPOSITION":
            var total = zero
            for e in elements where e.independent {
                let value = eq.v(eq.alone(e), w[1])
                total = total + value
                out.append("\(e.name): V(\(w[1])) = \(value.value)")
            }
            out.append("total: V(\(w[1])) = \(total.value)")
        default:
            break
        }
        return out
    }
}
let circuit = Circuit()
var lineNumber = 0
while let line = readLine() {
    lineNumber += 1
    if line == ".END" {
        break
    }
    if line.hasPrefix("*") {
        continue
    }
    let words = line.components(separatedBy: " ")
    do {
        if line.hasPrefix(".") {
            for result in try circuit.command(words) {
                print(result)
            }
        } else {
            try circuit.add(words)
        }
    } catch let e as Problem {
        print("error: line \(lineNumber): \(e.reason)")
    } catch {
    }
}
