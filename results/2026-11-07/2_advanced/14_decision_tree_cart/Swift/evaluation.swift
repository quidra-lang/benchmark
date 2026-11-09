import Foundation

func realText(_ value: Double, _ places: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
}

func ratioText(_ numerator: Int64, _ denominator: Int64) -> String {
    denominator == 0 ? "0/0 -" : "\(numerator)/\(denominator) \(realText(Double(numerator) / Double(denominator)))"
}

func fractionText(_ numerator: Int64, _ denominator: Int64, _ places: Int = 4) -> String {
    guard denominator > 0 else { return "- -" }
    var first = abs(numerator)
    var second = denominator
    while second != 0 { (first, second) = (second, first % second) }
    let reducedNumerator = numerator / first
    let reducedDenominator = denominator / first
    return "\(reducedNumerator)/\(reducedDenominator) \(realText(Double(reducedNumerator) / Double(reducedDenominator), places))"
}

enum Method: Int {
    case primary, surrogate, `default`
    var mark: String {
        switch self {
        case .primary: return ""
        case .surrogate: return " [surrogate]"
        case .default: return " [default]"
        }
    }
}

struct Route {
    let path: [Int]
    let methods: [Method]
}

struct PrunedTree {
    let nodes: [Node]
    var cut: Set<Int> = []

    func isLeaf(_ index: Int) -> Bool { nodes[index].split == nil || cut.contains(index) }
    func preorder(_ start: Int = 0) -> [Int] {
        var result: [Int] = []
        var pending = [start]
        while let index = pending.popLast() {
            result.append(index)
            if !isLeaf(index) {
                let children = nodes[index].children!
                pending.append(children.right)
                pending.append(children.left)
            }
        }
        return result
    }
    func leaves(_ start: Int = 0) -> [Int] { preorder(start).filter { isLeaf($0) } }
    func internalNodes() -> [Int] { preorder().filter { !isLeaf($0) } }
    var depth: Int { leaves().map { nodes[$0].depth }.max()! }
    var trainingErrors: Int64 { leaves().reduce(0) { $0 + nodes[$1].errors } }

    func route(_ row: Row, _ attributes: [Attribute]) -> Route {
        var index = 0
        var path = [index]
        var methods: [Method] = []
        while !isLeaf(index) {
            let node = nodes[index]
            let split = node.split!
            var left = node.defaultLeft
            var method = Method.default
            if let value = row.values[split.attribute] {
                left = split.goesLeft(value, attributes)
                method = .primary
            } else {
                for surrogate in node.surrogates {
                    if let value = row.values[surrogate.split.attribute] {
                        left = surrogate.split.goesLeft(value, attributes) == surrogate.forward
                        method = .surrogate
                        break
                    }
                }
            }
            index = left ? node.children!.left : node.children!.right
            path.append(index)
            methods.append(method)
        }
        return Route(path: path, methods: methods)
    }
    func leafOf(_ row: Row, _ attributes: [Attribute]) -> Int { route(row, attributes).path.last! }
    func predict(_ row: Row, _ attributes: [Attribute]) -> Int { nodes[leafOf(row, attributes)].prediction }
    func correctCount(_ rows: [Row], _ attributes: [Attribute]) -> Int64 {
        Int64(rows.filter { predict($0, attributes) == $0.label }.count)
    }
    func limited(_ depth: Int) -> PrunedTree {
        PrunedTree(nodes: nodes, cut: Set(internalNodes().filter { nodes[$0].depth == depth }))
    }
}

func classificationLines(_ title: String, _ classes: [String], _ rows: [Row], _ predictions: [Int]) -> [String] {
    var matrix = Array(repeating: Array<Int64>(repeating: 0, count: classes.count), count: classes.count)
    for (row, predicted) in zip(rows, predictions) { matrix[row.label][predicted] += 1 }
    let correct = classes.indices.reduce(Int64(0)) { $0 + matrix[$1][$1] }
    let total = Int64(rows.count)
    var lines = ["confusion \(title) correct \(correct)/\(total) accuracy \(fractionText(correct, total))",
        "actual\\predicted " + classes.joined(separator: " ")]
    for (name, counts) in zip(classes, matrix) { lines.append(name + " " + counts.map(String.init).joined(separator: " ")) }
    var f1Sum = 0.0
    var f1Count = 0
    for (index, name) in classes.enumerated() {
        let hits = matrix[index][index]
        let predicted = matrix.reduce(Int64(0)) { $0 + $1[index] }
        let support = matrix[index].reduce(0, +)
        if predicted + support > 0 {
            f1Sum += Double(2 * hits) / Double(predicted + support)
            f1Count += 1
        }
        lines.append("class \(name) precision \(fractionText(hits, predicted)) recall \(fractionText(hits, support)) f1 \(fractionText(2 * hits, predicted + support)) support \(support)")
    }
    lines.append("macro_f1 \(realText(f1Sum / Double(f1Count)))")
    return lines
}
