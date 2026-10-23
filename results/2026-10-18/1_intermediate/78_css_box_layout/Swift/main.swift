import Foundation

let sides = ["top", "right", "bottom", "left"]

let initial: [String: String] = {
    var values = [
        "display": "block", "position": "static", "box-sizing": "content-box",
        "width": "auto", "height": "auto", "min-width": "0", "min-height": "0",
        "max-width": "none", "max-height": "none", "flex-direction": "row",
        "flex-wrap": "nowrap", "justify-content": "start", "align-items": "stretch",
        "align-self": "auto", "row-gap": "0", "column-gap": "0", "order": "0",
        "flex-grow": "0", "flex-shrink": "1", "flex-basis": "auto",
        "grid-template-columns": "none", "grid-template-rows": "none",
        "grid-column": "auto", "grid-row": "auto"
    ]
    for side in sides {
        values[side] = "auto"
        for kind in ["margin", "padding", "border"] {
            values["\(kind)-\(side)"] = "0"
        }
    }
    return values
}()

let shorthands: Set<String> = ["margin", "padding", "border", "gap"]

func natural(_ s: String) -> Bool {
    (1...3).contains(s.utf8.count) && s.utf8.allSatisfy {
        $0 >= 48 && $0 <= 57
    }
}

func positive(_ s: String) -> Bool {
    natural(s) && Int(s)! > 0
}

func signed(_ s: String) -> Bool {
    natural(s.hasPrefix("-") ? String(s.dropFirst()) : s)
}

func percent(_ s: String) -> Bool {
    s.hasSuffix("%") && natural(String(s.dropLast()))
}

func fraction(_ s: String) -> Bool {
    s.hasSuffix("fr") && positive(String(s.dropLast(2)))
}

func gridValue(_ t: [String]) -> Bool {
    if t == ["auto"] {
        return true
    }
    if t.count == 1 {
        return positive(t[0])
    }
    if t.count == 2 {
        return t[0] == "span" && positive(t[1])
    }
    if t.count == 3 {
        return positive(t[0]) && t[1] == "/" && positive(t[2]) && Int(t[0])! < Int(t[2])!
    }
    if t.count == 4 {
        return positive(t[0]) && t[1] == "/" && t[2] == "span" && positive(t[3])
    }
    return false
}

func valid(_ prop: String, _ t: [String]) -> Bool {
    if prop.hasPrefix("grid-template-") {
        return t == ["none"] || t.allSatisfy {
            $0 == "auto" || natural($0) || fraction($0)
        }
    }
    if prop == "grid-column" || prop == "grid-row" {
        return gridValue(t)
    }
    if t.count != 1 {
        return false
    }
    let v = t[0]
    switch prop {
    case "display":
        return ["block", "flex", "grid", "none"].contains(v)
    case "position":
        return ["static", "relative", "absolute"].contains(v)
    case "box-sizing":
        return ["content-box", "border-box"].contains(v)
    case "width", "height", "flex-basis":
        return v == "auto" || natural(v) || percent(v)
    case "min-width", "min-height":
        return natural(v) || percent(v)
    case "max-width", "max-height":
        return v == "none" || natural(v) || percent(v)
    case "top", "right", "bottom", "left":
        return v == "auto" || signed(v)
    case "order":
        return signed(v)
    case "flex-direction":
        return ["row", "row-reverse", "column", "column-reverse"].contains(v)
    case "flex-wrap":
        return ["nowrap", "wrap"].contains(v)
    case "justify-content":
        return ["start", "end", "center", "space-between", "space-around", "space-evenly"].contains(v)
    case "align-items":
        return ["stretch", "start", "end", "center"].contains(v)
    case "align-self":
        return ["auto", "stretch", "start", "end", "center"].contains(v)
    default:
        return prop.hasPrefix("border-") ? v == "0" || v == "1" : natural(v)
    }
}

func declaration(_ prop: String, _ value: String) -> [(String, String)]? {
    let t = value.components(separatedBy: " ")
    if initial[prop] != nil {
        return valid(prop, t) ? [(prop, value)] : nil
    }
    if prop == "gap" {
        if !(1...2).contains(t.count) || !t.allSatisfy(natural) {
            return nil
        }
        return [("row-gap", t[0]), ("column-gap", t.last!)]
    }
    if shorthands.contains(prop) && (1...4).contains(t.count) && t.allSatisfy({
        valid("\(prop)-top", [$0])
    }) {
        let pick: [Int]
        switch t.count {
        case 1:
            pick = [0, 0, 0, 0]
        case 2:
            pick = [0, 1, 0, 1]
        case 3:
            pick = [0, 1, 2, 1]
        default:
            pick = [0, 1, 2, 3]
        }
        return sides.indices.map {
            ("\(prop)-\(sides[$0])", t[pick[$0]])
        }
    }
    return nil
}

struct Rule {
    let selectors: [String]
    let values: [(String, String)]
}

struct Rect: Equatable, CustomStringConvertible {
    let x: Int
    let y: Int
    let w: Int
    let h: Int
    var description: String {
        "\(x) \(y) \(w) \(h)"
    }
    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= self.x && x < self.x + w && y >= self.y && y < self.y + h
    }
    func contains(_ r: Rect) -> Bool {
        r.x >= x && r.y >= y && r.x + r.w <= x + w && r.y + r.h <= y + h
    }
}

final class Element {
    let kind: String
    let id: String
    let classes: Set<String>
    let text: String?
    let parent: Element?
    let index: Int
    let depth: Int
    var children = [Element]()
    var overrides = [String: String]()
    var style = initial
    var displayed = false
    var cw = 0
    var ch = 0
    var rx = 0
    var ry = 0
    var x = 0
    var y = 0
    var lines = [String]()
    init(_ kind: String, _ id: String, _ classes: Set<String>, _ text: String?, _ parent: Element?, _ index: Int) {
        self.kind = kind
        self.id = id
        self.classes = classes
        self.text = text
        self.parent = parent
        self.index = index
        depth = parent.map {
            $0.depth + 1
        } ?? 0
    }
    func s(_ p: String) -> String {
        style[p]!
    }
    func n(_ p: String) -> Int {
        Int(s(p))!
    }
    func edge(_ kind: String, _ i: Int) -> Int {
        n("\(kind)-\(sides[i])")
    }
    func frame(_ horizontal: Bool) -> Int {
        let a = horizontal ? 1 : 0
        let b = horizontal ? 3 : 2
        return edge("padding", a) + edge("padding", b) + edge("border", a) + edge("border", b)
    }
    func margin(_ horizontal: Bool) -> Int {
        edge("margin", horizontal ? 1 : 0) + edge("margin", horizontal ? 3 : 2)
    }
    var borderWidth: Int {
        cw + frame(true)
    }
    var borderHeight: Int {
        ch + frame(false)
    }
    var border: Rect {
        Rect(x: x, y: y, w: borderWidth, h: borderHeight)
    }
    var content: Rect {
        Rect(x: x + edge("border", 3) + edge("padding", 3), y: y + edge("border", 0) + edge("padding", 0), w: cw, h: ch)
    }
    var padding: Rect {
        Rect(x: x + edge("border", 3), y: y + edge("border", 0), w: cw + edge("padding", 1) + edge("padding", 3), h: ch + edge("padding", 0) + edge("padding", 2))
    }
    var marginBox: Rect {
        Rect(x: x - edge("margin", 3), y: y - edge("margin", 0), w: borderWidth + margin(true), h: borderHeight + margin(false))
    }
    var flow: [Element] {
        children.filter {
            $0.displayed && $0.s("position") != "absolute"
        }
    }
    var items: [Element] {
        flow.sorted {
            ($0.n("order"), $0.index) < ($1.n("order"), $1.index)
        }
    }
    func align(_ child: Element) -> String {
        let value = child.s("align-self")
        return value == "auto" ? s("align-items") : value
    }
    func resolve(_ prop: String, _ reference: Int?, _ horizontal: Bool) -> Int? {
        let v = s(prop)
        if v == "auto" || v == "none" {
            return nil
        }
        let r: Int
        if v.hasSuffix("%") {
            guard let ref = reference else {
                return nil
            }
            r = ref * Int(v.dropLast())! / 100
        } else {
            r = Int(v)!
        }
        return s("box-sizing") == "border-box" ? max(0, r - frame(horizontal)) : r
    }
    func clamp(_ value: Int, _ reference: Int?, _ horizontal: Bool) -> Int {
        let axis = horizontal ? "width" : "height"
        let lo = resolve("min-\(axis)", reference, horizontal) ?? 0
        let hi = resolve("max-\(axis)", reference, horizontal)
        return max(lo, hi.map {
            min(value, $0)
        } ?? value)
    }
    func place(_ child: Element, _ x: Int, _ y: Int) {
        child.rx = x + edge("border", 3) + edge("padding", 3)
        child.ry = y + edge("border", 0) + edge("padding", 0)
    }
}

struct Cell: Hashable {
    let row: Int
    let col: Int
}

struct Area {
    var row: Int
    var col: Int
    let rows: Int
    let cols: Int
}

struct Grid {
    let items: [Element]
    let areas: [Area]
    let columns: [String]
    let rows: [String]
    let nc: Int
    let nr: Int
}

func distribution(_ total: Int, _ weights: [Int]) -> [Int] {
    let sum = weights.reduce(0, +)
    if sum == 0 {
        return Array(repeating: 0, count: weights.count)
    }
    var out = weights.map {
        total * $0 / sum
    }
    var rest = total - out.reduce(0, +)
    for i in weights.indices where rest > 0 && weights[i] > 0 {
        out[i] += 1
        rest -= 1
    }
    return out
}

func placement(_ value: String) -> (Int, Int) {
    let t = value.components(separatedBy: " ")
    if t[0] == "auto" {
        return (0, 1)
    }
    if t[0] == "span" {
        return (0, Int(t[1])!)
    }
    if t.count == 1 {
        return (Int(t[0])!, 1)
    }
    if t.count == 3 {
        return (Int(t[0])!, Int(t[2])! - Int(t[0])!)
    }
    return (Int(t[0])!, Int(t[3])!)
}

func grid(_ e: Element) -> Grid {
    let items = e.items
    let columns = e.s("grid-template-columns") == "none" ? ["auto"] : e.s("grid-template-columns").components(separatedBy: " ")
    let rows = e.s("grid-template-rows") == "none" ? [] : e.s("grid-template-rows").components(separatedBy: " ")
    var areas = items.map {
        child -> Area in let (c, cs) = placement(child.s("grid-column"))
        let (r, rs) = placement(child.s("grid-row"))
        return Area(row: r, col: c, rows: rs, cols: cs)
    }
    let nc = max(columns.count, areas.map {
        $0.col == 0 ? $0.cols : $0.col + $0.cols - 1
    }.max() ?? 0)
    var occupied = Set<Cell>()
    func mark(_ a: Area) {
        for r in a.row..<(a.row + a.rows) {
            for c in a.col..<(a.col + a.cols) {
                occupied.insert(Cell(row: r, col: c))
            }
        }
    }
    func overlaps(_ a: Area, _ row: Int, _ col: Int) -> Bool {
        (row..<(row + a.rows)).contains {
            r in (col..<(col + a.cols)).contains {
                c in occupied.contains(Cell(row: r, col: c))
            }
        }
    }
    for a in areas where a.row != 0 && a.col != 0 {
        mark(a)
    }
    var cr = 1
    var cc = 1
    for i in areas.indices {
        var a = areas[i]
        if a.row != 0 && a.col != 0 {
            continue
        }
        if a.row != 0 {
            a.col = (1...(nc - a.cols + 1)).first {
                !overlaps(a, a.row, $0)
            } ?? 1
        } else if a.col != 0 {
            if a.col < cc {
                cr += 1
            }
            var r = cr
            while overlaps(a, r, a.col) {
                r += 1
            }
            a.row = r
            cr = r
            cc = a.col + a.cols
        } else {
            var r = cr
            var c = cc
            while true {
                if c + a.cols - 1 > nc {
                    r += 1
                    c = 1
                } else if overlaps(a, r, c) {
                    c += 1
                } else {
                    break
                }
            }
            a.row = r
            a.col = c
            cr = r
            cc = c + a.cols
        }
        areas[i] = a
        mark(a)
    }
    let nr = max(rows.count, areas.map {
        $0.row + $0.rows - 1
    }.max() ?? 0)
    return Grid(items: items, areas: areas, columns: columns, rows: rows, nc: nc, nr: nr)
}

func tracks(_ g: Grid, _ horizontal: Bool, _ available: Int?, _ gap: Int, _ contributions: [Int]) -> [Int] {
    let count = horizontal ? g.nc : g.nr
    let explicit = horizontal ? g.columns : g.rows
    let specs = (0..<count).map {
        $0 < explicit.count ? explicit[$0] : "auto"
    }
    var sizes = specs.enumerated().map {
        i, spec -> Int in
        if natural(spec) {
            return Int(spec)!
        }
        if fraction(spec) && available != nil {
            return 0
        }
        return g.areas.indices.filter {
            j in let a = g.areas[j]
            return (horizontal ? a.col : a.row) == i + 1 && (horizontal ? a.cols : a.rows) == 1
        }.map {
            contributions[$0]
        }.max() ?? 0
    }
    if let u = available {
        let left = u - sizes.reduce(0, +) - gap * max(0, count - 1)
        if left > 0 {
            let hasFr = specs.contains(where: fraction)
            let weights = specs.map {
                v -> Int in if hasFr {
                    return fraction(v) ? Int(v.dropLast(2))! : 0
                }
                return v == "auto" ? 1 : 0
            }
            let extra = distribution(left, weights)
            for i in sizes.indices {
                sizes[i] += extra[i]
            }
        }
    }
    return sizes
}

func contribution(_ e: Element) -> Int {
    e.clamp(e.resolve("width", nil, true) ?? maxContent(e), nil, true) + e.frame(true) + e.margin(true)
}

func maxContent(_ e: Element) -> Int {
    if let text = e.text {
        return text.count
    }
    let children = e.flow
    if e.s("display") == "flex" && e.s("flex-direction").hasPrefix("row") {
        return children.map(contribution).reduce(0, +) + e.n("column-gap") * max(0, children.count - 1)
    }
    if e.s("display") == "grid" {
        let g = grid(e)
        return tracks(g, true, nil, e.n("column-gap"), g.items.map(contribution)).reduce(0, +) + e.n("column-gap") * (g.nc - 1)
    }
    return children.map(contribution).max() ?? 0
}

func wrap(_ text: String, _ width: Int) -> [String] {
    var lines = [String]()
    for word in text.components(separatedBy: " ") {
        if lines.isEmpty || lines.last!.count + 1 + word.count > width {
            lines.append(word)
        } else {
            lines[lines.count - 1] += " \(word)"
        }
    }
    return lines
}
@discardableResult
func layout(_ e: Element, _ cwRef: Int, _ chRef: Int?, _ fw: Int? = nil, _ givenHeight: Int? = nil) -> Int {
    e.cw = fw ?? e.clamp(e.resolve("width", cwRef, true) ?? max(0, cwRef - e.margin(true) - e.frame(true)), cwRef, true)
    let fh = givenHeight ?? e.resolve("height", chRef, false).map {
        e.clamp($0, chRef, false)
    }
    let a: Int
    if let text = e.text {
        e.lines = wrap(text, e.cw)
        a = e.lines.count
    } else if e.s("display") == "flex" {
        a = flex(e, fh, chRef)
    } else if e.s("display") == "grid" {
        a = gridLayout(e, fh)
    } else {
        var bottom = 0
        var previous = 0
        var first = true
        for child in e.flow {
            layout(child, e.cw, fh)
            let y = bottom + (first ? child.edge("margin", 0) : max(previous, child.edge("margin", 0)))
            e.place(child, child.edge("margin", 3), y)
            bottom = y + child.borderHeight
            previous = child.edge("margin", 2)
            first = false
        }
        a = bottom + previous
    }
    e.ch = fh ?? e.clamp(a, chRef, false)
    return a
}

func offset(_ remaining: Int, _ align: String) -> Int {
    remaining <= 0 ? 0 : align == "end" ? remaining : align == "center" ? remaining / 2 : 0
}

func flex(_ e: Element, _ k: Int?, _ heightReference: Int?) -> Int {
    let items = e.items
    let horizontal = e.s("flex-direction").hasPrefix("row")
    let reverse = e.s("flex-direction").hasSuffix("reverse")
    let gap = e.n(horizontal ? "column-gap" : "row-gap")
    let lineGap = e.n("row-gap")
    let reference: Int? = horizontal ? e.cw : k
    var cross = Array(repeating: 0, count: items.count)
    var base = cross
    var hypothetical = cross
    let outer = items.map {
        $0.frame(horizontal) + $0.margin(horizontal)
    }
    for (i, child) in items.enumerated() {
        if !horizontal {
            let r = max(0, e.cw - child.margin(true) - child.frame(true))
            cross[i] = child.clamp(child.resolve("width", e.cw, true) ?? (e.align(child) == "stretch" ? r : min(maxContent(child), r)), e.cw, true)
        }
        base[i] = child.resolve("flex-basis", reference, horizontal) ?? child.resolve(horizontal ? "width" : "height", reference, horizontal) ?? (horizontal ? maxContent(child) : layout(child, e.cw, k, cross[i]))
        hypothetical[i] = child.clamp(base[i], reference, horizontal)
    }
    let intrinsic = items.indices.map {
        hypothetical[$0] + outer[$0]
    }.reduce(0, +) + gap * max(0, items.count - 1)
    let length = horizontal ? e.cw : k ?? e.clamp(intrinsic, heightReference, false)
    var lines = [[Int]]()
    var used = 0
    for i in items.indices {
        let size = hypothetical[i] + outer[i]
        if lines.isEmpty || (horizontal && e.s("flex-wrap") == "wrap" && used + gap + size > length) {
            lines.append([i])
            used = size
        } else {
            lines[lines.count - 1].append(i)
            used += gap + size
        }
    }
    var lineStart = 0
    for line in lines {
        let totalGap = gap * (line.count - 1)
        let grow = line.map {
            hypothetical[$0] + outer[$0]
        }.reduce(0, +) + totalGap < length
        let weights = line.map {
            grow ? items[$0].n("flex-grow") : items[$0].n("flex-shrink") * base[$0]
        }
        var target = line.map {
            hypothetical[$0]
        }
        var frozen = line.enumerated().map {
            j, i in weights[j] == 0 || (grow ? base[i] > hypothetical[i] : base[i] < hypothetical[i])
        }
        while frozen.contains(false) {
            let free = length - totalGap - line.indices.map {
                (frozen[$0] ? target[$0] : base[line[$0]]) + outer[line[$0]]
            }.reduce(0, +)
            let assignments = distribution(max(0, grow ? free : -free), line.indices.map {
                frozen[$0] ? 0 : weights[$0]
            })
            var violations = Array(repeating: 0, count: line.count)
            for j in line.indices where !frozen[j] {
                let tentative = base[line[j]] + (grow ? assignments[j] : -assignments[j])
                target[j] = items[line[j]].clamp(tentative, reference, horizontal)
                violations[j] = target[j] - tentative
            }
            let violation = violations.reduce(0, +)
            for j in line.indices where violation == 0 || violation > 0 && violations[j] > 0 || violation < 0 && violations[j] < 0 {
                frozen[j] = true
            }
        }
        if horizontal {
            for j in line.indices {
                let i = line[j]
                layout(items[i], e.cw, k, target[j])
                cross[i] = items[i].ch
            }
        }
        var lineCross = horizontal ? line.map {
            cross[$0] + items[$0].frame(false) + items[$0].margin(false)
        }.max()! : e.cw
        if horizontal && lines.count == 1 {
            lineCross = k ?? e.clamp(lineCross, heightReference, false)
        }
        let remaining = length - line.indices.map {
            target[$0] + outer[line[$0]]
        }.reduce(0, +) - totalGap
        var spaces = Array(repeating: 0, count: line.count)
        if remaining > 0 {
            let mode = e.s("justify-content")
            if mode == "end" {
                spaces[0] = remaining
            } else if mode == "center" {
                spaces[0] = remaining / 2
            } else if mode.hasPrefix("space-") {
                let w = (0...line.count).map {
                    j -> Int in
                    if mode == "space-evenly" {
                        return 1
                    }
                    if j == 0 || j == line.count {
                        return mode == "space-between" ? 0 : 1
                    }
                    return mode == "space-around" ? 2 : 1
                }
                spaces = Array(distribution(remaining, w).prefix(line.count))
            }
        }
        var cursor = 0
        for j in line.indices {
            let i = line[j]
            let child = items[i]
            let align = e.align(child)
            if horizontal {
                if align == "stretch" && child.s("height") == "auto" {
                    cross[i] = child.clamp(max(0, lineCross - child.margin(false) - child.frame(false)), k, false)
                    layout(child, e.cw, k, target[j], cross[i])
                } else {
                    layout(child, e.cw, k, target[j])
                    cross[i] = child.ch
                }
            } else {
                layout(child, e.cw, k, cross[i], target[j])
            }
            cursor += spaces[j]
            let main = reverse ? length - cursor - target[j] - outer[i] : cursor
            let crossPosition = lineStart + offset(lineCross - cross[i] - child.frame(!horizontal) - child.margin(!horizontal), align)
            if horizontal {
                e.place(child, main + child.edge("margin", 3), crossPosition + child.edge("margin", 0))
            } else {
                e.place(child, crossPosition + child.edge("margin", 3), main + child.edge("margin", 0))
            }
            cursor += target[j] + outer[i] + gap
        }
        lineStart += lineCross + lineGap
    }
    return horizontal ? (lines.isEmpty ? 0 : lineStart - lineGap) : length
}

func gridLayout(_ e: Element, _ k: Int?) -> Int {
    let g = grid(e)
    let colGap = e.n("column-gap")
    let rowGap = e.n("row-gap")
    let columns = tracks(g, true, e.cw, colGap, g.items.map(contribution))
    var widths = Array(repeating: 0, count: g.items.count)
    var areaWidths = widths
    let contributions = g.items.indices.map {
        i -> Int in
        let a = g.areas[i]
        let child = g.items[i]
        let aw = columns[(a.col - 1)..<(a.col - 1 + a.cols)].reduce(0, +) + colGap * (a.cols - 1)
        areaWidths[i] = aw
        widths[i] = child.clamp(child.resolve("width", aw, true) ?? max(0, aw - child.margin(true) - child.frame(true)), aw, true)
        layout(child, aw, nil, widths[i])
        return child.borderHeight + child.margin(false)
    }
    let rows = tracks(g, false, k, rowGap, contributions)
    for i in g.items.indices {
        let a = g.areas[i]
        let child = g.items[i]
        let align = e.align(child)
        let ah = rows[(a.row - 1)..<(a.row - 1 + a.rows)].reduce(0, +) + rowGap * (a.rows - 1)
        let ax = columns.prefix(a.col - 1).reduce(0, +) + colGap * (a.col - 1)
        let ay = rows.prefix(a.row - 1).reduce(0, +) + rowGap * (a.row - 1)
        let fh: Int? = align == "stretch" && child.s("height") == "auto" ? child.clamp(max(0, ah - child.margin(false) - child.frame(false)), ah, false) : nil
        layout(child, areaWidths[i], ah, widths[i], fh)
        let dy = offset(ah - child.borderHeight - child.margin(false), align)
        e.place(child, ax + child.edge("margin", 3), ay + dy + child.edge("margin", 0))
    }
    return rows.reduce(0, +) + rowGap * max(0, g.nr - 1)
}

final class Document {
    var width: Int
    var height: Int
    let rules: [Rule]
    let elements: [Element]
    let byId: [String: Element]
    init(_ width: Int, _ height: Int, _ rules: [Rule], _ elements: [Element]) {
        self.width = width
        self.height = height
        self.rules = rules
        self.elements = elements
        byId = Dictionary(uniqueKeysWithValues: elements.map {
            ($0.id, $0)
        })
    }
    func containing(_ e: Element) -> Element? {
        var p = e.parent
        while let node = p {
            if node.s("position") != "static" {
                return node
            }
            p = node.parent
        }
        return nil
    }
    func reflow() {
        for e in elements {
            e.style = initial
            var specificity = [String: Int]()
            for rule in rules {
                let best = rule.selectors.compactMap {
                    s -> Int? in
                    if s.hasPrefix("#") {
                        return String(s.dropFirst()) == e.id ? 2 : nil
                    }
                    if s.hasPrefix(".") {
                        return e.classes.contains(String(s.dropFirst())) ? 1 : nil
                    }
                    return s == e.kind ? 0 : nil
                }.max()
                if let best = best {
                    for (p, v) in rule.values where best >= (specificity[p] ?? -1) {
                        e.style[p] = v
                        specificity[p] = best
                    }
                }
            }
            for (p, v) in e.overrides {
                e.style[p] = v
            }
            e.displayed = e.s("display") != "none" && (e.parent?.displayed ?? true)
        }
        let root = elements[0]
        if root.displayed && root.s("position") != "absolute" {
            layout(root, width, height)
            root.rx = root.edge("margin", 3)
            root.ry = root.edge("margin", 0)
        }
        for e in elements where e.displayed && e.s("position") == "absolute" {
            let block = containing(e)
            let cbw = block.map {
                $0.cw + $0.edge("padding", 1) + $0.edge("padding", 3)
            } ?? width
            let cbh = block.map {
                $0.ch + $0.edge("padding", 0) + $0.edge("padding", 2)
            } ?? height
            func side(_ s: String) -> Int? {
                e.s(s) == "auto" ? nil : e.n(s)
            }
            let left = side("left")
            let right = side("right")
            let top = side("top")
            let bottom = side("bottom")
            let r = max(0, cbw - (left ?? 0) - (right ?? 0) - e.margin(true) - e.frame(true))
            let w = e.resolve("width", cbw, true) ?? (left != nil && right != nil ? r : min(maxContent(e), r))
            let fw = e.clamp(w, cbw, true)
            let fh: Int? = e.s("height") == "auto" && top != nil && bottom != nil ? e.clamp(max(0, cbh - top! - bottom! - e.margin(false) - e.frame(false)), cbh, false) : nil
            layout(e, cbw, cbh, fw, fh)
            e.rx = left.map {
                $0 + e.edge("margin", 3)
            } ?? right.map {
                cbw - $0 - e.edge("margin", 1) - e.borderWidth
            } ?? e.edge("margin", 3)
            e.ry = top.map {
                $0 + e.edge("margin", 0)
            } ?? bottom.map {
                cbh - $0 - e.edge("margin", 2) - e.borderHeight
            } ?? e.edge("margin", 0)
        }
        for e in elements where e.displayed {
            let absolute = e.s("position") == "absolute"
            let ref = absolute ? containing(e) : e.parent
            let bx = ref.map {
                $0.x + (absolute ? $0.edge("border", 3) : 0)
            } ?? 0
            let by = ref.map {
                $0.y + (absolute ? $0.edge("border", 0) : 0)
            } ?? 0
            var dx = 0
            var dy = 0
            if e.s("position") == "relative" {
                dx = e.s("left") != "auto" ? e.n("left") : e.s("right") != "auto" ? -e.n("right") : 0
                dy = e.s("top") != "auto" ? e.n("top") : e.s("bottom") != "auto" ? -e.n("bottom") : 0
            }
            e.x = bx + e.rx + dx
            e.y = by + e.ry + dy
        }
    }
    func snapshot() -> [Rect?] {
        elements.map {
            $0.displayed ? $0.border : nil
        }
    }
    func changed(_ old: [Rect?]) -> String {
        let now = snapshot()
        let ids = elements.indices.filter {
            old[$0] != now[$0]
        }.map {
            elements[$0].id
        }
        return ids.isEmpty ? "no change" : ids.joined(separator: " ")
    }
    func render() -> [String] {
        var screen = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        for e in elements where e.displayed {
            let b = e.border
            let ymin = max(0, b.y)
            let ymax = min(height, b.y + b.h)
            let xmin = max(0, b.x)
            let xmax = min(width, b.x + b.w)
            if ymin < ymax && xmin < xmax {
                for y in ymin..<ymax {
                    for x in xmin..<xmax {
                        let horizontal = e.edge("border", 0) == 1 && y == b.y || e.edge("border", 2) == 1 && y == b.y + b.h - 1
                        let vertical = e.edge("border", 3) == 1 && x == b.x || e.edge("border", 1) == 1 && x == b.x + b.w - 1
                        screen[y][x] = horizontal && vertical ? "+" : horizontal ? "-" : vertical ? "|" : " "
                    }
                }
            }
            if e.text != nil {
                let c = e.content
                for (i, line) in e.lines.enumerated() {
                    for (j, ch) in line.enumerated() {
                        let x = c.x + j
                        let y = c.y + i
                        if x >= 0 && x < width && y >= 0 && y < height {
                            screen[y][x] = ch
                        }
                    }
                }
            }
        }
        let frame = String(repeating: "#", count: width + 2)
        return ["render \(width)x\(height)", frame] + screen.map {
            "#" + String($0) + "#"
        } + [frame]
    }
    func command(_ line: String) -> [String] {
        let a = line.components(separatedBy: " ")
        switch a[0] {
        case "LAYOUT":
            return ["layout \(width)x\(height)"] + elements.map {
                String(repeating: "  ", count: $0.depth) + $0.id + ($0.displayed ? " \($0.border)" : " none")
            }
        case "BOX":
            guard let e = byId[a[1]] else {
                return ["error: unknown element \(a[1])"]
            }
            if !e.displayed {
                return ["box \(e.id): none"]
            }
            return ["box \(e.id)", "margin \(e.marginBox)", "border \(e.border)", "padding \(e.padding)", "content \(e.content)"]
        case "RENDER":
            return render()
        case "HIT":
            let x = Int(a[1])!
            let y = Int(a[2])!
            if x >= width || y >= height {
                return ["error: point \(x) \(y) outside viewport"]
            }
            var e = elements.last {
                $0.displayed && $0.border.contains(x, y)
            }
            var path = [String]()
            while let node = e {
                path.append(node.id)
                e = node.parent
            }
            return ["hit \(x) \(y): " + (path.isEmpty ? "none" : path.reversed().joined(separator: " > "))]
        case "SET":
            let id = a[1]
            let p = a[2]
            let value = a.dropFirst(3).joined(separator: " ")
            guard let e = byId[id] else {
                return ["error: unknown element \(id)"]
            }
            if initial[p] == nil && !shorthands.contains(p) {
                return ["error: unknown property \(p)"]
            }
            guard let values = declaration(p, value) else {
                return ["error: invalid value for \(p): \(value)"]
            }
            let old = snapshot()
            for (p, v) in values {
                e.overrides[p] = v
            }
            reflow()
            return ["set \(id) \(p) \(value): \(changed(old))"]
        case "VIEWPORT":
            let w = Int(a[1])!
            let h = Int(a[2])!
            if !(1...80).contains(w) || !(1...40).contains(h) {
                return ["error: invalid viewport \(w) \(h)"]
            }
            let old = snapshot()
            width = w
            height = h
            reflow()
            return ["viewport \(w) \(h): \(changed(old))"]
        case "OVERFLOW":
            let ids = elements.filter {
                e in e.displayed && (e.text != nil ? e.lines.contains {
                    $0.count > e.cw
                } || e.lines.count > e.ch : e.flow.contains {
                    !e.content.contains($0.marginBox)
                })
            }.map {
                $0.id
            }
            return ["overflow: " + (ids.isEmpty ? "none" : ids.joined(separator: " "))]
        default:
            return ["error: unknown command \(a[0])"]
        }
    }
}

let size = readLine()!.split(separator: " ").map {
    Int($0)!
}

var rules = [Rule]()
while let line = readLine(), line != "---" {
    let range = line.range(of: " { ")!
    let selectors = String(line[..<range.lowerBound]).components(separatedBy: ", ")
    let body = String(line[range.upperBound...].dropLast(2))
    let values = body.components(separatedBy: "; ").flatMap {
        d -> [(String, String)] in let colon = d.range(of: ": ")!
        return declaration(String(d[..<colon.lowerBound]), String(d[colon.upperBound...])) ?? []
    }
    rules.append(Rule(selectors: selectors, values: values))
}

var elements = [Element]()

var ancestors = [Element]()
while let line = readLine(), line != "===" {
    let spaces = line.prefix {
        $0 == " "
    }.count
    let depth = spaces / 2
    let body = String(line.dropFirst(spaces))
    let head: String
    let text: String?
    if let at = body.firstIndex(of: " ") {
        head = String(body[..<at])
        text = String(body[body.index(at, offsetBy: 2)...].dropLast())
    } else {
        head = body
        text = nil
    }
    let hash = head.firstIndex(of: "#")!
    let parts = String(head[head.index(after: hash)...]).components(separatedBy: ".")
    let e = Element(String(head[..<hash]), parts[0], Set(parts.dropFirst()), text, depth == 0 ? nil : ancestors[depth - 1], elements.count)
    e.parent?.children.append(e)
    elements.append(e)
    ancestors = Array(ancestors.prefix(depth))
    ancestors.append(e)
}

let document = Document(size[0], size[1], rules, elements)
document.reflow()

var output = ""
while let line = readLine(), line != "END" {
    for result in document.command(line) {
        output += result + "\n"
    }
}
print(output, terminator: "")
