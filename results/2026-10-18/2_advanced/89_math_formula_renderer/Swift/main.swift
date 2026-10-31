import Foundation
typealias B = BoxNode
func display(_ kind: String, _ value: String, _ references: [String: String]) -> String {
    kind == "command" ? Lexer.symbol(String(value.dropFirst()))!.0 : kind == "eqref" ? references[value] ?? "(??)" : value
}
func typeset(_ node: Node, _ script: Bool, _ p: Params, _ references: [String: String]) -> B {
    switch node {
        case .atom(let kind, let value, _):
        let description = (kind == "text" ? "text" : kind == "eqref" ? "eqref" : "atom") + " \"\(value)\""
        if !script && kind == "command" && ["\\sum", "\\prod", "\\int"].contains(value) {
            let glyph = Boxes.large(String(value.dropFirst())), result = B(glyph[0].count, 3, 1, description)
            for (y, line) in glyph.enumerated() {
                result.string(0, y, line)
            }
            return result
        }
        return B.text(display(kind, value, references), description)
        case .row(let nodes):
        let gaps = Layout.spacing(nodes, script, p).1
        return Layout.row(nodes.map {
            typeset($0, script, p, references)
        }, gaps, "row")
        case .script(let base, let sub, let sup):
        let b = typeset(base, script, p, references), s = sub.map {
            typeset($0, true, p, references)
        }, u = sup.map {
            typeset($0, true, p, references)
        }
        let sw = s?.width ?? 0, sh = s?.height ?? 0, uw = u?.width ?? 0, uh = u?.height ?? 0
        let stacked: Bool
        switch base {
            case .atom(let kind, let value, _): stacked = !script && kind == "command" && ["\\sum", "\\prod", "\\lim", "\\max", "\\min"].contains(value)
            case .accent(let name, _): stacked = !script && (name == "overbrace" || name == "underbrace")
            default: stacked = false
        }
        if stacked {
            let width = max(b.width, max(sw, uw)), result = B(width, uh + b.height + sh, uh + b.baseline, "limits")
            result.child(b, (width - b.width) / 2, uh, "base: ")
            if let s {
                result.child(s, (width - sw) / 2, uh + b.height, "sub: ")
            }
            if let u {
                result.child(u, (width - uw) / 2, 0, "sup: ")
            }
            return result
        }
        let tp = (b.baseline == 0 ? -1 : 0) - uh + 1, ts = b.height - 1 - b.baseline == 0 ? b.height : b.height - 1
        let top = u == nil ? 0 : min(0, tp), bottom = s == nil ? b.height - 1 : max(b.height - 1, ts + sh - 1), shift = -top
        let result = B(b.width + max(sw, uw), bottom - top + 1, b.baseline + shift, "scripts")
        result.child(b, 0, shift, "base: ")
        if let s {
            result.child(s, b.width, ts + shift, "sub: ")
        }
        if let u {
            result.child(u, b.width, tp - top, "sup: ")
        }
        return result
        case .binary(let name, let first, let second):
        if name == "frac" && script {
            func part(_ node: Node) -> B {
                let wrap: Bool
                switch node {
                    case .row: wrap = true;
                    case .binary(let name, _, _) where name == "frac": wrap = true;
                    default: wrap = false
                }
                return typeset(wrap ? .delimited("(", ")", node, 0) : node, true, p, references)
            }
            return Layout.row([part(first), B.text("/", "atom \"/\""), part(second)], [0, 0], "slash", ["num: ", "", "den: "])
        }
        let placed = name == "overset" || name == "underset", a = typeset(first, placed ? true : script, p, references), b = typeset(second, script, p, references)
        switch name {
            case "frac":
            let width = max(a.width, b.width) + 2, result = B(width, a.height + 1 + b.height, a.height, "frac")
            result.string(0, a.height, String(repeating: "-", count: width));
            result.child(a, (width - a.width) / 2, 0, "num: ");
            result.child(b, (width - b.width) / 2, a.height + 1, "den: ")
            return result
            case "binom":
            let width = max(a.width, b.width), result = B(width + 2, a.height + 1 + b.height, a.height, "binom")
            result.delimiter("(", 0);
            result.delimiter(")", width + 1)
            result.child(a, 1 + (width - a.width) / 2, 0, "upper: ");
            result.child(b, 1 + (width - b.width) / 2, a.height + 1, "lower: ")
            return result
            case "overset":
            let width = max(a.width, b.width), result = B(width, a.height + b.height, a.height + b.baseline, "overset")
            result.child(a, (width - a.width) / 2, 0, "over: ");
            result.child(b, (width - b.width) / 2, a.height, "base: ")
            return result
            default:
            let width = max(a.width, b.width), result = B(width, a.height + b.height, b.baseline, "underset")
            result.child(b, (width - b.width) / 2, 0, "base: ");
            result.child(a, (width - a.width) / 2, b.height, "under: ")
            return result
        }
        case .root(let rootIndex, let bodyNode):
        let body = typeset(bodyNode, script, p, references), index = rootIndex.map {
            typeset($0, true, p, references)
        }, k = body.height
        let extra = max(0, (index?.width ?? 0) - 1), top = max(0, (index?.height ?? 0) - k)
        let result = B(extra + k + 1 + body.width, k + 1 + top, body.baseline + 1 + top, index == nil ? "sqrt" : "root")
        result.string(extra + k + 1, top, String(repeating: "_", count: body.width));
        result.string(extra, k + top, "\\")
        for r in 1...k {
            result.string(extra + k - r + 1, r + top, "/")
        }
        if let index {
            result.child(index, 0, k + top - index.height, "index: ");
            result.child(body, extra + k + 1, 1 + top, "body: ")
        }
        else {
            result.child(body, extra + k + 1, 1 + top)
        }
        return result
        case .delimited(let left, let right, let bodyNode, _):
        let body = typeset(bodyNode, script, p, references), wl = left == "." ? 0 : 1, wr = right == "." ? 0 : 1
        let result = B(wl + body.width + wr, body.height, body.baseline, "delim \(left) \(right)")
        result.delimiter(left, 0);
        result.delimiter(right, wl + body.width);
        result.child(body, wl, 0)
        return result
        case .matrix(let environment, let rows):
        let cells = rows.map {
            $0.map {
                typeset($0, script, p, references)
            }
        }, columns = rows[0].count
        let widths = (0..<columns).map {
            j in cells.map {
                $0[j].width
            }.max()!
        }, ascents = cells.map {
            $0.map(\.baseline).max()!
        }, descents = cells.map {
            $0.map {
                $0.height - 1 - $0.baseline
            }.max()!
        }
        let heights = zip(ascents, descents).map {
            pair in pair.0 + pair.1 + 1
        }, bodyWidth = widths.reduce(0, +) + p.colGap * (columns - 1), bodyHeight = heights.reduce(0, +) + p.rowGap * (rows.count - 1)
        let shift = environment == "matrix" ? 0 : 2, width = bodyWidth + (environment == "matrix" ? 0 : environment == "cases" ? 2 : 4)
        let result = B(width, bodyHeight, (bodyHeight - 1) / 2, "\(environment) rows=\(rows.count) cols=\(columns)")
        switch environment {
            case "pmatrix": result.delimiter("(", 0);
            result.delimiter(")", bodyWidth + 3)
            case "bmatrix": result.delimiter("[", 0);
            result.delimiter("]", bodyWidth + 3)
            case "vmatrix": result.delimiter("|", 0);
            result.delimiter("|", bodyWidth + 3)
            case "cases": result.delimiter("\\{", 0)
            default: break
        }
        var y = 0
        for (i, row) in cells.enumerated() {
            var x = shift
            for (j, box) in row.enumerated() {
                let offset = environment == "cases" ? 0 : (widths[j] - box.width) / 2
                result.child(box, x + offset, y + ascents[i] - box.baseline, "cell \(i + 1),\(j + 1): ");
                x += widths[j] + p.colGap
            }
            y += heights[i] + p.rowGap
        }
        return result
        case .accent(let name, let node):
        let body = typeset(node, script, p, references), width: Int
        switch name {
            case "hat", "dot", "tilde": width = max(body.width, 1);
            case "vec": width = max(body.width, 2);
            case "overbrace", "underbrace": width = body.width + 2;
            default: width = body.width
        }
        let result = B(width, body.height + 1, name == "underbrace" ? body.baseline : body.baseline + 1, name)
        switch name {
            case "overline": result.string(0, 0, String(repeating: "_", count: width))
            case "hat", "dot", "tilde": result.string((width - 1) / 2, 0, name == "hat" ? "^" : name == "dot" ? "." : "~")
            case "vec": result.string(0, 0, String(repeating: "-", count: width - 1) + ">")
            case "overbrace": result.string(0, 0, "/" + String(repeating: "-", count: body.width) + "\\")
            default: result.string(0, body.height, "\\" + String(repeating: "-", count: body.width) + "/")
        }
        result.child(body, name == "overbrace" || name == "underbrace" ? 1 : 0, name == "underbrace" ? 0 : 1)
        return result
    }
}
func tree(_ node: Node) -> String {
    switch node {
        case .atom(let kind, let value, _): return kind == "symbol" ? "'\(value)'" : kind == "text" ? "\"\(value)\"" : kind == "eqref" ? "(eqref \"\(value)\")" : value
        case .row(let nodes): return "(row" + nodes.map {
            " " + tree($0)
        }.joined() + ")"
        case .binary(let name, let a, let b): return "(\(name) \(tree(a)) \(tree(b)))"
        case .root(let index, let body): return index.map {
            "(root \(tree($0)) \(tree(body)))"
        } ?? "(sqrt \(tree(body)))"
        case .script(let base, let sub, let sup):
        if let sub, let sup {
            return "(subsup \(tree(base)) \(tree(sub)) \(tree(sup)))"
        }
        if let sub {
            return "(sub \(tree(base)) \(tree(sub)))"
        }
        return "(sup \(tree(base)) \(tree(sup!)))"
        case .delimited(let left, let right, let body, _):
        func delimiter(_ text: String) -> String {
            text.count == 1 ? "'\(text)'" : text
        }
        return "(delim \(delimiter(left)) \(delimiter(right)) \(tree(body)))"
        case .matrix(let name, let rows): return "(" + name + rows.map {
            " [" + $0.map(tree).joined(separator: " ") + "]"
        }.joined() + ")"
        case .accent(let name, let body): return "(\(name) \(tree(body)))"
    }
}
func linear(_ node: Node, _ script: Bool, _ p: Params, _ references: [String: String]) -> String {
    func child(_ node: Node) -> String {
        linear(node, script, p, references)
    }
    func parenthesize(_ node: Node, _ style: Bool, _ base: Bool = false) -> String {
        let text = linear(node, style, p, references), wrap: Bool
        switch node {
            case .row: wrap = true;
            case .binary(let name, _, _) where name == "frac": wrap = true;
            case .script where base: wrap = true;
            default: wrap = false
        }
        return wrap ? "(\(text))" : text
    }
    switch node {
        case .atom(let kind, let value, _): return display(kind, value, references)
        case .row(let nodes):
        let gaps = Layout.spacing(nodes, script, p).1
        return nodes.enumerated().map {
            (i, node) in (i > 0 ? String(repeating: " ", count: gaps[i - 1]) : "") + child(node)
        }.joined()
        case .binary(let name, let a, let b):
        if name == "frac" {
            return parenthesize(a, script) + "/" + parenthesize(b, script)
        }
        if name == "binom" {
            return "binom(\(child(a)), \(child(b)))"
        }
        return "\(name)(\(linear(a, true, p, references)), \(child(b)))"
        case .root(let index, let body): return index.map {
            "root(\(linear($0, true, p, references)), \(child(body)))"
        } ?? "sqrt(\(child(body)))"
        case .script(let base, let sub, let sup): return parenthesize(base, script, true) + (sub.map {
            "_" + parenthesize($0, true)
        } ?? "") + (sup.map {
            "^" + parenthesize($0, true)
        } ?? "")
        case .delimited(let left, let right, let body, _):
        func delimiter(_ text: String) -> String {
            text == "." ? "" : text == "\\{" ? "{" : text == "\\}" ? "}" : text
        }
        return delimiter(left) + child(body) + delimiter(right)
        case .matrix(let name, let rows): return name + "[" + rows.map {
            $0.map(child).joined(separator: ", ")
        }.joined(separator: "; ") + "]"
        case .accent(let name, let body): return "\(name)(\(child(body)))"
    }
}
func warnings(_ node: Node, _ references: [String: String], _ out: inout [(Int, String)]) {
    switch node {
        case .atom(let kind, let value, let column):
        if kind == "identifier" && Lexer.commandName(value) {
            out.append((column, "\(value) is a command name; write \\\(value)"))
        }
        if kind == "eqref" && references[value] == nil {
            out.append((column, "undefined reference \"\(value)\""))
        }
        case .row(let nodes): for node in nodes {
            warnings(node, references, &out)
        }
        case .binary(_, let a, let b): warnings(a, references, &out);
        warnings(b, references, &out)
        case .root(let index, let body): if let index {
            warnings(index, references, &out)
        };
        warnings(body, references, &out)
        case .script(let base, let sub, let sup): warnings(base, references, &out);
        if let sub {
            warnings(sub, references, &out)
        };
        if let sup {
            warnings(sup, references, &out)
        }
        case .delimited(let left, let right, let body, let column):
        if left != "." && right != "." && ![("(", ")"), ("[", "]"), ("|", "|"), ("\\{", "\\}")].contains(where: {
            $0.0 == left && $0.1 == right
        }) {
            out.append((column, "\\left\(left) closed by \\right\(right)"))
        }
        warnings(body, references, &out)
        case .matrix(_, let rows): for node in rows.flatMap({
            $0
        }) {
            warnings(node, references, &out)
        }
        case .accent(_, let body): warnings(body, references, &out)
    }
}
struct Line {
    let start: Int, end: Int, indent: Int, width: Int
}
func buildLines(_ nodes: [Node], _ boxes: [B], _ types: [(Int, Int)], _ gaps: [Int], _ p: Params, _ stage: Int) -> [Line] {
    let n = nodes.count
    var breaks: [Int] = []
    for i in 1..<n {
        let relation = types[i].0 == 3, binary: Bool
        if case .atom(let kind, let value, _) = nodes[i] {
            binary = stage >= 1 && types[i].0 == 2 && kind == "symbol" && (value == "+" || value == "-")
        }
        else {
            binary = false
        }
        if relation || binary || stage >= 2 && types[i - 1].1 == 6 {
            breaks.append(i)
        }
    }
    breaks.append(n)
    var lines: [Line] = [], start = 0, alignment: (Int, Int)?
    while start < n {
        let indent = start == 0 ? 0 : alignment.map {
            types[start].0 == 3 ? $0.0 : $0.0 + $0.1 + p.rel
        } ?? p.indent
        func width(_ end: Int) -> Int {
            boxes[start..<end].reduce(0) {
                $0 + $1.width
            } + gaps[start..<(end - 1)].reduce(0, +)
        }
        let candidates = breaks.filter {
            $0 > start
        }, end = candidates.last {
            indent + width($0) <= p.width
        } ?? candidates[0]
        if start == 0, let relation = (start..<end).first(where: {
            types[$0].0 == 3
        }) {
            let column = boxes[..<relation].reduce(0) {
                $0 + $1.width
            } + gaps[..<relation].reduce(0, +)
            alignment = (column, boxes[relation].width)
        }
        lines.append(Line(start: start, end: end, indent: indent, width: width(end)));
        start = end
    }
    return lines
}
struct Placed {
    let node: B, x: Int, y: Int
}
struct Composition {
    let placed: [Placed], width: Int, height: Int, lines: Int, overfull: [(Int, Int)]
}
func compose(_ elements: [Node], _ tag: String?, _ p: Params, _ references: [String: String]) -> Composition {
    let (types, gaps) = Layout.spacing(elements, false, p), boxes = elements.map {
        typeset($0, false, p, references)
    }
    var lines: [Line] = []
    for stage in 0..<3 {
        lines = buildLines(elements, boxes, types, gaps, p, stage);
        if lines.allSatisfy({
            $0.indent + $0.width <= p.width
        }) {
            break
        }
    }
    var placed: [Placed] = [], overfull: [(Int, Int)] = [], width = 0, y = 0
    for (k, line) in lines.enumerated() {
        if line.indent + line.width > p.width {
            overfull.append((k + 1, line.indent + line.width))
        }
        let box = Layout.row(Array(boxes[line.start..<line.end]), Array(gaps[line.start..<(line.end - 1)]), "line \(k + 1)")
        width = max(width, line.indent + box.width);
        placed.append(Placed(node: box, x: line.indent, y: y));
        y += box.height
    }
    if let tag {
        let x = p.width - tag.count, last = placed.last!, tagY: Int
        if x >= last.x + last.node.width + 2 {
            tagY = last.y + last.node.baseline
        }
        else {
            tagY = y;
            y += 1
        }
        let box = B.text(tag, "tag \"\(tag)\"")
        width = max(width, x + box.width);
        placed.append(Placed(node: box, x: x, y: tagY))
    }
    return Composition(placed: placed, width: width, height: y, lines: lines.count, overfull: overfull)
}
final class Record {
    let text: String, formula: Formula?, error: FormulaError?
    var tag: String?, warnings: [(Int, String)] = []
    init(_ text: String) {
        self.text = text
        do {
            formula = try Parser.parse(Lexer.lex(text), text.count + 1);
            error = nil
        }
        catch let failure as FormulaError {
            formula = nil;
            error = failure
        }
        catch {
            preconditionFailure()
        }
    }
}
func readParams() -> Params {
    var values: [String: Int] = [:]
    for line in (try! String(contentsOfFile: "input/params.txt", encoding: .ascii)).split(separator: "\n") {
        let a = line.split(separator: " ").map(String.init);
        values[a[0]] = Int(a[1])!
    }
    return Params(width: values["width"]!, indent: values["indent"]!, rel: values["rel_space"]!, binary: values["bin_space"]!, punctuation: values["punct_space"]!, colGap: values["col_gap"]!, rowGap: values["row_gap"]!)
}
func diagnostic(_ number: Int, _ text: String, _ column: Int, _ message: String, _ out: inout [String]) {
    out += ["formula \(number), column \(column): \(message)", "  " + text, String(repeating: " ", count: column + 1) + "^"]
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func runProgram() {
    let params = readParams(), text = try! String(contentsOfFile: "input/formulas.txt", encoding: .ascii)
    let records = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map {
        Record(String($0))
    }
    var counter = 0, references: [String: String] = [:]
    for record in records {
        if let formula = record.formula {
            if let tag = formula.tag {
                record.tag = "(\(tag.0))"
            }
            else if formula.label != nil {
                counter += 1;
                record.tag = "(\(counter))"
            }
        }
    }
    for record in records {
        if let label = record.formula?.label {
            if references[label.0] != nil {
                record.warnings.append((label.1, "duplicate label \"\(label.0)\""))
            }
            else {
                references[label.0] = record.tag!
            }
        }
    }
    var rendered: [String] = [], boxes: [String] = [], trees: [String] = [], errors: [String] = [], kinds: [String: Int] = [:]
    var valid = 0, totalBoxes = 0, maxDepth = 0, warningCount = 0, overfullCount = 0
    for (i, record) in records.enumerated() {
        let number = i + 1
        if i > 0 {
            rendered.append("")
        }
        rendered.append("formula \(number)")
        if let error = record.error {
            rendered.append("(error)");
            boxes.append("formula \(number): error");
            trees.append("formula \(number): error")
            diagnostic(number, record.text, error.column, error.message, &errors)
            continue
        }
        let formula = record.formula!
        valid += 1
        for node in formula.elements {
            warnings(node, references, &record.warnings)
        }
        record.warnings.sort {
            $0.0 < $1.0
        };
        warningCount += record.warnings.count
        for (column, message) in record.warnings {
            diagnostic(number, record.text, column, "warning: " + message, &errors)
        }
        let composition = compose(formula.elements, record.tag, params, references)
        overfullCount += composition.overfull.count
        for (line, width) in composition.overfull {
            errors.append("formula \(number): line \(line) is overfull (width \(width) > \(params.width))")
        }
        var grid = Array(repeating: Array<UInt8>(repeating: 32, count: composition.width), count: composition.height), boxLines: [String] = [], depth = 0
        for placed in composition.placed {
            Canvas.paint(placed.node, placed.x, placed.y, &grid);
            Canvas.describe(placed.node, placed.x, placed.y, 0, "", &boxLines, &kinds, &depth)
        }
        totalBoxes += boxLines.count;
        maxDepth = max(maxDepth, depth)
        boxes.append("formula \(number): lines=\(composition.lines) width=\(composition.width) height=\(composition.height) boxes=\(boxLines.count) depth=\(depth)");
        boxes += boxLines
        rendered += Canvas.lines(grid)
        trees.append("formula \(number): " + formula.elements.map(tree).joined(separator: " "))
        let text = Canvas.trim(linear(.row(formula.elements), false, params, references))
        trees.append(text.isEmpty ? "  linear:" : "  linear: " + text)
        if let tag = record.tag {
            trees.append("  tag: \(tag)")
        }
    }
    boxes.append("summary: boxes=\(totalBoxes) max_depth=\(maxDepth)")
    for kind in kinds.keys.sorted() {
        boxes.append("  \(kind): \(kinds[kind]!)")
    }
    errors.append("formulas=\(records.count) rendered=\(valid) errors=\(records.count - valid) warnings=\(warningCount) overfull=\(overfullCount)")
    write("rendered.txt", rendered);
    write("boxes.txt", boxes);
    write("trees.txt", trees);
    write("errors.txt", errors)
}
runProgram()
