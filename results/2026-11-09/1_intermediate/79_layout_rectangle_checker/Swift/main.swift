import Foundation

struct Problem: Error {
    let text: String
}

func fail(_ s: String) throws -> Never {
    throw Problem(text: "error: " + s)
}

func names(_ values: [String]) -> String {
    values.isEmpty ? "none" : values.sorted().joined(separator: " ")
}

func decimal(_ n: Int, _ d: Int) -> String {
    let v = n * 100 / d
    return "\(v / 100)." + String(format: "%02d", v % 100)
}

struct Rect {
    var name: String
    var layer: String
    var x1: Int
    var y1: Int
    var x2: Int
    var y2: Int

    init(_ name: String, _ layer: String, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
        self.name = name
        self.layer = layer
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }
    var width: Int {
        x2 - x1
    }
    var height: Int {
        y2 - y1
    }
    var area: Int {
        width * height
    }
    var text: String {
        "(\(x1),\(y1))-(\(x2),\(y2))"
    }

    func contains(_ b: Rect) -> Bool {
        x1 <= b.x1 && y1 <= b.y1 && x2 >= b.x2 && y2 >= b.y2
    }

    func margins(_ b: Rect) -> [Int] {
        [b.x1 - x1, b.y1 - y1, x2 - b.x2, y2 - b.y2]
    }

    func moved(_ dx: Int, _ dy: Int) -> Rect {
        Rect(name, layer, x1 + dx, y1 + dy, x2 + dx, y2 + dy)
    }

    func checkBounds() throws {
        if [x1, y1, x2, y2].contains(where: {
            abs($0) > 10000
        }) {
            try fail("out of bounds")
        }
    }
}

struct Relation {
    let common: Rect
    let ox: Int
    let oy: Int
    let kind: Int
    let gap: Int

    init(_ a: Rect, _ b: Rect) {
        let overlap = Rect("", "", max(a.x1, b.x1), max(a.y1, b.y1), min(a.x2, b.x2), min(a.y2, b.y2))
        common = overlap
        let x = overlap.width
        let y = overlap.height
        ox = x
        oy = y
        kind = x > 0 && y > 0 ? 0 : x >= 0 && y >= 0 && x + y > 0 ? 1 : x == 0 && y == 0 ? 2 : 3
        gap = max(0, max(-x, -y))
    }
    var direction: String {
        kind == 2 ? "corner" : ox < 0 && oy < 0 ? "diagonal" : ox < 0 ? "x" : "y"
    }
}

func connected(_ a: Rect, _ b: Rect) -> Bool {
    Relation(a, b).kind <= 1
}

func bbox(_ rs: [Rect]) -> Rect {
    Rect("", "", rs.map(\.x1).min()!, rs.map(\.y1).min()!, rs.map(\.x2).max()!, rs.map(\.y2).max()!)
}

struct Interval: Hashable {
    let left: Int
    let right: Int
}

final class Grid {
    let xs: [Int]
    let ys: [Int]
    let count: [[Int]]
    var nx: Int {
        xs.count - 1
    }
    var ny: Int {
        ys.count - 1
    }

    init(_ rs: [Rect]) {
        let xs = Set(rs.flatMap {
            [$0.x1, $0.x2]
        }).sorted()
        let ys = Set(rs.flatMap {
            [$0.y1, $0.y2]
        }).sorted()
        self.xs = xs
        self.ys = ys
        count = (0..<(ys.count - 1)).map {
            y in (0..<(xs.count - 1)).map {
                x in rs.filter {
                    $0.x1 <= xs[x] && $0.x2 > xs[x] && $0.y1 <= ys[y] && $0.y2 > ys[y]
                }.count
            }
        }
    }

    func area(_ k: Int = 1, _ window: Rect? = nil) -> Int {
        var sum = 0
        for y in 0..<ny {
            for x in 0..<nx where count[y][x] >= k {
                let w = max(0, min(xs[x + 1], window?.x2 ?? xs[x + 1]) - max(xs[x], window?.x1 ?? xs[x]))
                let h = max(0, min(ys[y + 1], window?.y2 ?? ys[y + 1]) - max(ys[y], window?.y1 ?? ys[y]))
                sum += w * h
            }
        }
        return sum
    }

    func perimeter() -> Int {
        var sum = 0
        for y in 0..<ny {
            for x in 0..<nx where count[y][x] > 0 {
                if x == 0 || count[y][x - 1] == 0 {
                    sum += ys[y + 1] - ys[y]
                }
                if x + 1 == nx || count[y][x + 1] == 0 {
                    sum += ys[y + 1] - ys[y]
                }
                if y == 0 || count[y - 1][x] == 0 {
                    sum += xs[x + 1] - xs[x]
                }
                if y + 1 == ny || count[y + 1][x] == 0 {
                    sum += xs[x + 1] - xs[x]
                }
            }
        }
        return sum
    }

    func empty() -> Rect? {
        var best: Rect?
        for bottom in 0..<ny {
            var free = Array(repeating: true, count: nx)
            for top in bottom..<ny {
                for x in 0..<nx {
                    free[x] = free[x] && count[top][x] == 0
                }
                var x = 0
                while x < nx {
                    if !free[x] {
                        x += 1
                        continue
                    }
                    let start = x
                    while x < nx && free[x] {
                        x += 1
                    }
                    let r = Rect("", "", xs[start], ys[bottom], xs[x], ys[top + 1])
                    if best == nil || (-r.area, r.x1, r.y1, r.width) < (-best!.area, best!.x1, best!.y1, best!.width) {
                        best = r
                    }
                }
            }
        }
        return best
    }

    func holes() -> [(Int, Rect)] {
        var seen = Array(repeating: Array(repeating: false, count: nx), count: ny)
        var result = [(Int, Int, Int, Rect)]()
        for y in 0..<ny {
            for x in 0..<nx {
                if count[y][x] > 0 || seen[y][x] {
                    continue
                }
                var queue = [(x, y)]
                var at = 0
                seen[y][x] = true
                var boundary = false
                var area = 0
                var r = Rect("", "", xs[x], ys[y], xs[x + 1], ys[y + 1])
                var anchor = (ys[y], xs[x])
                while at < queue.count {
                    let (cx, cy) = queue[at]
                    at += 1
                    boundary = boundary || cx == 0 || cy == 0 || cx + 1 == nx || cy + 1 == ny
                    area += (xs[cx + 1] - xs[cx]) * (ys[cy + 1] - ys[cy])
                    r.x1 = min(r.x1, xs[cx])
                    r.y1 = min(r.y1, ys[cy])
                    r.x2 = max(r.x2, xs[cx + 1])
                    r.y2 = max(r.y2, ys[cy + 1])
                    if (ys[cy], xs[cx]) < anchor {
                        anchor = (ys[cy], xs[cx])
                    }
                    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let xx = cx + dx
                        let yy = cy + dy
                        if xx >= 0 && xx < nx && yy >= 0 && yy < ny && !seen[yy][xx] && count[yy][xx] == 0 {
                            seen[yy][xx] = true
                            queue.append((xx, yy))
                        }
                    }
                }
                if !boundary {
                    result.append((anchor.0, anchor.1, area, r))
                }
            }
        }
        return result.sorted {
            ($0.0, $0.1) < ($1.0, $1.1)
        }.map {
            ($0.2, $0.3)
        }
    }

    func pieces() -> [Rect] {
        var active = [Interval: Rect]()
        var result = [Rect]()
        for y in 0..<ny {
            var next = [Interval: Rect]()
            var x = 0
            while x < nx {
                if count[y][x] == 0 {
                    x += 1
                    continue
                }
                let start = x
                while x < nx && count[y][x] > 0 {
                    x += 1
                }
                let key = Interval(left: xs[start], right: xs[x])
                var r = active[key] ?? Rect("", "", xs[start], ys[y], xs[x], ys[y + 1])
                r.y2 = ys[y + 1]
                next[key] = r
            }
            for (key, r) in active where next[key] == nil {
                result.append(r)
            }
            active = next
        }
        result.append(contentsOf: active.values)
        return result.sorted {
            ($0.y1, $0.x1) < ($1.y1, $1.x1)
        }
    }
}

struct Violation {
    let a: Rect
    let b: Rect
    let relation: Relation
    var text: String {
        "\(a.name) \(b.name) gap \(relation.gap) \(relation.direction)"
    }
}

func spacing(_ rs: [Rect], _ s: Int) -> [Violation] {
    var result = [Violation]()
    for i in rs.indices {
        for j in (i + 1)..<rs.count {
            let r = Relation(rs[i], rs[j])
            if r.kind == 2 || r.kind == 3 && r.gap < s {
                result.append(Violation(a: rs[i], b: rs[j], relation: r))
            }
        }
    }
    return result.sorted {
        ($0.relation.gap, $0.a.name, $0.b.name) < ($1.relation.gap, $1.a.name, $1.b.name)
    }
}

func nets(_ rs: [Rect]) -> [[Rect]] {
    var seen = Set<String>()
    var groups = [[Rect]]()
    for r in rs {
        if !seen.insert(r.name).inserted {
            continue
        }
        var queue = [r]
        var at = 0
        while at < queue.count {
            let a = queue[at]
            at += 1
            for b in rs where !seen.contains(b.name) && connected(a, b) {
                seen.insert(b.name)
                queue.append(b)
            }
        }
        groups.append(queue.sorted {
            $0.name < $1.name
        })
    }
    return groups
}

struct RuleKey: Hashable, Comparable {
    let kind: String
    let inner: String
    let outer: String
    static func < (a: RuleKey, b: RuleKey) -> Bool {
        (a.kind, a.inner, a.outer) < (b.kind, b.inner, b.outer)
    }
}

final class Layout {
    var rectangles = [String: Rect]()
    var history = [([String: Rect], String)]()
    var rules = [RuleKey: Int]()
    var all: [Rect] {
        rectangles.values.sorted {
            $0.name < $1.name
        }
    }

    func get(_ name: String) throws -> Rect {
        guard let r = rectangles[name] else {
            try fail("unknown rectangle \(name)")
        }
        return r
    }

    func layer(_ name: String) -> [Rect] {
        all.filter {
            $0.layer == name
        }
    }

    func checkedLayer(_ name: String) throws -> [Rect] {
        let rs = layer(name)
        if rs.isEmpty {
            try fail("no rectangles on \(name)")
        }
        return rs
    }

    func command(_ line: String) throws -> [String] {
        let w = line.components(separatedBy: " ")
        let c = w[0]

        func n(_ i: Int) -> Int {
            Int(w[i])!
        }
        var out = [String]()
        if ["ADD", "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE"].contains(c) {
            var next = rectangles
            let name = w[1]
            switch c {
            case "ADD":
                if rectangles[name] != nil {
                    try fail("duplicate rectangle \(name)")
                }
                let r = Rect(name, w[2], n(3), n(4), n(5), n(6))
                if r.width <= 0 || r.height <= 0 {
                    try fail("invalid rectangle")
                }
                try r.checkBounds()
                next[name] = r
                out.append("added \(name) \(r.layer) \(r.text)")
            case "COPY":
                let old = try get(name)
                if rectangles[w[2]] != nil {
                    try fail("duplicate rectangle \(w[2])")
                }
                var r = old.moved(n(3), n(4))
                r.name = w[2]
                try r.checkBounds()
                next[r.name] = r
                out.append("copied \(name) to \(r.name) \(r.text)")
            case "MOVE":
                let r = try get(name).moved(n(2), n(3))
                try r.checkBounds()
                next[name] = r
                out.append("moved \(name) to \(r.text)")
            case "RESIZE":
                var r = try get(name)
                if n(2) <= 0 || n(3) <= 0 {
                    try fail("invalid size")
                }
                r.x2 = r.x1 + n(2)
                r.y2 = r.y1 + n(3)
                try r.checkBounds()
                next[name] = r
                out.append("resized \(name) to \(r.text)")
            case "SPLIT":
                let old = try get(name)
                if rectangles[w[4]] != nil {
                    try fail("duplicate rectangle \(w[4])")
                }
                let p = n(3)
                let x = w[2] == "x"
                if p <= (x ? old.x1 : old.y1) || p >= (x ? old.x2 : old.y2) {
                    try fail("cut outside \(name)")
                }
                var a = old
                var b = old
                b.name = w[4]
                if x {
                    a.x2 = p
                    b.x1 = p
                } else {
                    a.y2 = p
                    b.y1 = p
                }
                next[name] = a
                next[b.name] = b
                out.append("split \(name) at \(w[2])=\(p): \(name) \(a.text), \(b.name) \(b.text)")
            case "LAYER":
                var r = try get(name)
                if r.layer == w[2] {
                    try fail("already on \(w[2])")
                }
                out.append("layer \(name) \(r.layer) -> \(w[2])")
                r.layer = w[2]
                next[name] = r
            default:
                _ = try get(name)
                next.removeValue(forKey: name)
                out.append("deleted \(name)")
            }
            history.append((rectangles, line))
            rectangles = next
            return out
        }
        switch c {
        case "UNDO":
            guard let (old, text) = history.popLast() else {
                try fail("nothing to undo")
            }
            rectangles = old
            return ["undo: \(text)"]
        case "LIST":
            return ["rectangles: \(rectangles.count)"] + all.map {
                "\($0.name) \($0.layer) \($0.text) \($0.width)x\($0.height)"
            }
        case "INFO":
            let a = try get(w[1])
            let others = all.filter {
                $0.name != a.name
            }
            out.append("\(a.name) \(a.layer) \(a.text) \(a.width)x\(a.height) area \(a.area)")
            for (label, kind) in [("overlaps", 0), ("touches", 1), ("corners", 2)] {
                out.append(label + ": " + names(others.filter {
                    $0.layer == a.layer && Relation(a, $0).kind == kind
                }.map(\.name)))
            }
            out.append("encloses: " + names(others.filter {
                a.contains($0)
            }.map(\.name)))
            out.append("enclosed by: " + names(others.filter {
                $0.contains(a)
            }.map(\.name)))
            return out
        case "LAYERS":
            let layers = Set(all.map(\.layer)).sorted()
            out.append("layers: \(layers.count)")
            for l in layers {
                let rs = layer(l)
                out.append("\(l): \(rs.count) rectangles, area \(Grid(rs).area()), nets \(nets(rs).count)")
            }
            return out
        case "INTERSECT", "ADJACENT", "ENCLOSE", "PATH":
            let a = try get(w[1])
            let b = try get(w[2])
            if a.name == b.name {
                try fail("same rectangle \(a.name)")
            }
            let r = Relation(a, b)
            let q = r.common
            if c == "INTERSECT" {
                let text: String
                switch r.kind {
                case 0:
                    text = "\(q.text) area \(q.area)"
                case 1:
                    text = "segment \(q.text) length \(r.ox + r.oy)"
                case 2:
                    text = "point (\(q.x1),\(q.y1))"
                default:
                    text = "none, gap \(r.gap)"
                }
                return ["intersect \(a.name) \(b.name): \(text)"]
            }
            if c == "ADJACENT" {
                let d = r.ox == 0 ? (a.x2 == q.x1 ? "west" : "east") : (a.y2 == q.y1 ? "south" : "north")
                let text: String
                switch r.kind {
                case 0:
                    text = "overlapping"
                case 1:
                    text = "\(a.name) is \(d) of \(b.name), edge \(q.text), length \(r.ox + r.oy)"
                case 2:
                    text = "corner only at (\(q.x1),\(q.y1))"
                default:
                    text = "not adjacent"
                }
                return ["adjacent \(a.name) \(b.name): \(text)"]
            }
            if c == "ENCLOSE" {
                let m = a.margins(b)
                return ["enclose \(a.name) \(b.name): " + (a.contains(b) ? "yes" : "no") + ", margins left \(m[0]) bottom \(m[1]) right \(m[2]) top \(m[3])" + (a.contains(b) ? ", min \(m.min()!)" : "")]
            }
            if a.layer != b.layer {
                try fail("different layers")
            }
            let rs = layer(a.layer)
            var previous = [String: String]()
            var seen: Set<String> = [a.name]
            var queue = [a]
            var at = 0
            while at < queue.count {
                let p = queue[at]
                at += 1
                for q in rs where !seen.contains(q.name) && connected(p, q) {
                    seen.insert(q.name)
                    previous[q.name] = p.name
                    queue.append(q)
                }
            }
            if !seen.contains(b.name) {
                return ["path \(a.name) \(b.name): none"]
            }
            var path = [b.name]
            while path.last! != a.name {
                path.append(previous[path.last!]!)
            }
            path.reverse()
            return ["path \(a.name) \(b.name): \(path.joined(separator: " -> ")) (\(path.count - 1) steps)"]
        case "AT":
            let x = n(1)
            let y = n(2)
            let found = all.filter {
                $0.x1 <= x && x <= $0.x2 && $0.y1 <= y && y <= $0.y2
            }.map {
                r -> String in let xx = x == r.x1 || x == r.x2
                let yy = y == r.y1 || y == r.y2
                return "\(r.name) \(r.layer) " + (xx && yy ? "corner" : xx || yy ? "edge" : "inside")
            }
            return ["at (\(x),\(y)): " + (found.isEmpty ? "none" : found.joined(separator: ", "))]
        case "NEAREST":
            let a = try get(w[1])
            let b = layer(a.layer).filter {
                $0.name != a.name
            }.min {
                (Relation(a, $0).gap, $0.name) < (Relation(a, $1).gap, $1.name)
            }
            return ["nearest \(a.name): " + (b.map {
                "\($0.name) gap \(Relation(a, $0).gap)"
            } ?? "none")]
        case "OVERLAPS":
            let rs: [Rect]
            if w.count == 2 {
                rs = try checkedLayer(w[1])
            } else {
                rs = all
            }
            var found = [(Rect, Rect, Rect)]()
            for i in rs.indices {
                for j in (i + 1)..<rs.count where rs[i].layer == rs[j].layer {
                    let r = Relation(rs[i], rs[j])
                    if r.kind == 0 {
                        found.append((rs[i], rs[j], r.common))
                    }
                }
            }
            found.sort {
                ($0.0.layer, $0.0.name, $0.1.name) < ($1.0.layer, $1.0.name, $1.1.name)
            }
            out.append("overlaps " + (w.count == 1 ? "all layers" : w[1]) + ": \(found.count)")
            for (a, b, r) in found {
                out.append((w.count == 1 ? "\(a.layer) " : "") + "\(a.name) \(b.name) \(r.text) area \(r.area)")
            }
            return out
        case "RULE":
            let kind = w[1].lowercased()
            if kind == "enclose" && w[2] == w[3] {
                try fail("same layer \(w[2])")
            }
            let outer = kind == "enclose" ? w[3] : ""
            let v = n(kind == "enclose" ? 4 : 3)
            rules[RuleKey(kind: kind, inner: w[2], outer: outer)] = v
            return ["rule \(kind) \(w[2])" + (outer.isEmpty ? "" : " \(outer)") + " \(v)"]
        case "CHECK":
            if rules.isEmpty {
                try fail("no rules")
            }
            var total = 0
            for rule in rules.keys.sorted() {
                let v = rules[rule]!
                let rs = layer(rule.inner)
                var found = [String]()
                if rule.kind == "spacing" {
                    found = spacing(rs, v).map(\.text)
                } else if rule.kind == "width" {
                    found = rs.filter {
                        min($0.width, $0.height) < v
                    }.map {
                        "\($0.name) width \(min($0.width, $0.height))"
                    }
                } else {
                    let outer = layer(rule.outer)
                    for r in rs {
                        let best = outer.map {
                            $0.margins(r).min()!
                        }.max()
                        if best == nil || best! < v {
                            found.append("\(r.name) best margin " + (best.map(String.init) ?? "none"))
                        }
                    }
                }
                total += found.count
                out.append("\(rule.kind) \(rule.inner)" + (rule.kind == "enclose" ? " \(rule.outer)" : "") + " \(v): \(found.count) violations")
                out += found
            }
            out.append("check: \(total) violations in \(rules.count) rules")
            return out
        default:
            break
        }
        let rs = try checkedLayer(c == "COVER" ? w[2] : w[1])
        let l = rs[0].layer
        let g = Grid(rs)
        let b = bbox(rs)
        switch c {
        case "AREA":
            return ["area \(l): \(g.area())"]
        case "COVER":
            return ["cover \(l) >= \(w[1]): \(g.area(n(1)))"]
        case "PERIMETER":
            return ["perimeter \(l): \(g.perimeter())"]
        case "NETS":
            let groups = nets(rs)
            out.append("nets \(l): \(groups.count)")
            for (i, group) in groups.enumerated() {
                out.append("net \(i + 1): \(names(group.map(\.name))) area \(Grid(group).area())")
            }
            return out
        case "DRC":
            let violations = spacing(rs, n(2))
            return ["drc \(l) spacing \(w[2]): \(violations.count) violations"] + violations.map(\.text)
        case "BBOX":
            return ["bbox \(l): \(b.text) \(b.width)x\(b.height), \(rs.count) rectangles, density \(decimal(100 * g.area(), b.area))%"]
        case "DENSITY":
            let size = n(2)
            let cols = (b.width + size - 1) / size
            let rows = (b.height + size - 1) / size
            if cols > 20 || rows > 20 {
                try fail("too many windows")
            }
            let values = (0..<rows).map {
                y in (0..<cols).map {
                    x -> Int in let xx = b.x1 + x * size
                    let yy = b.y1 + y * size
                    return g.area(1, Rect("", "", xx, yy, xx + size, yy + size))
                }
            }
            let denominator = size * size
            out.append("density \(l) window \(size): \(cols)x\(rows)")
            for row in values.reversed() {
                out.append(row.map {
                    String(100 * $0 / denominator)
                }.joined(separator: " "))
            }
            var minX = 0
            var minY = 0
            var maxX = 0
            var maxY = 0
            for y in 0..<rows {
                for x in 0..<cols {
                    if values[y][x] < values[minY][minX] {
                        minX = x
                        minY = y
                    }
                    if values[y][x] > values[maxY][maxX] {
                        maxX = x
                        maxY = y
                    }
                }
            }
            out.append("min \(decimal(100 * values[minY][minX], denominator))% at (\(b.x1 + minX * size),\(b.y1 + minY * size))")
            out.append("max \(decimal(100 * values[maxY][maxX], denominator))% at (\(b.x1 + maxX * size),\(b.y1 + maxY * size))")
            return out
        case "RENDER":
            let r = Rect("", "", n(2), n(3), n(4), n(5))
            if r.width <= 0 || r.height <= 0 {
                try fail("invalid window")
            }
            if r.width > 60 || r.height > 40 {
                try fail("window too large")
            }
            out.append("render \(l) \(r.text)")
            for y in (r.y1..<r.y2).reversed() {
                let row = (r.x1..<r.x2).map {
                    x -> Character in let count = rs.filter {
                        $0.x1 <= x && x < $0.x2 && $0.y1 <= y && y < $0.y2
                    }.count
                    return count == 0 ? "." : count >= 10 ? "*" : Character(String(count))
                }
                out.append(String(row))
            }
            return out
        case "EMPTY":
            return ["empty \(l): " + (g.empty().map {
                "\($0.text) area \($0.area)"
            } ?? "none")]
        case "HOLES":
            let holes = g.holes()
            return ["holes \(l): \(holes.count)"] + holes.enumerated().map {
                i, value in "hole \(i + 1): area \(value.0), bbox \(value.1.text)"
            }
        case "MERGE":
            let pieces = g.pieces()
            return ["merge \(l): \(pieces.count) pieces"] + pieces.map(\.text)
        default:
            return []
        }
    }
}
let layout = Layout()
if let line = readLine(), let n = Int(line) {
    for _ in 0..<n {
        do {
            for result in try layout.command(readLine()!) {
                print(result)
            }
        } catch let e as Problem {
            print(e.text)
        } catch {
        }
    }
}
