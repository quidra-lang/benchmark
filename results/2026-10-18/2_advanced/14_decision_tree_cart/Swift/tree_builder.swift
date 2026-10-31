func halfText(_ value: Int64) -> String { "\(value / 2).\(5 * (value % 2))" }

struct Split {
    let attribute: Int
    let point: Int64
    func goesLeft(_ value: Int64, _ attributes: [Attribute]) -> Bool {
        attributes[attribute].integer ? 2 * value <= point : value == point
    }
    func condition(_ left: Bool, _ attributes: [Attribute]) -> String {
        let definition = attributes[attribute]
        if definition.integer { return "\(definition.name) \(left ? "<=" : ">") \(halfText(point))" }
        return "\(definition.name) \(left ? "=" : "!=") \(definition.values[Int(point)])"
    }
}

struct Surrogate {
    let split: Split
    let forward: Bool
    let score: Int64
}

struct Candidate {
    let split: Split
    let left: [Int64]
    let right: [Int64]
    var value: Fraction { evaluationValue(left, right) }
    var leftSize: Int64 { left.reduce(0, +) }
    var rightSize: Int64 { right.reduce(0, +) }
}

struct Node {
    let number: Int
    let depth: Int
    let counts: [Int64]
    let size: Int64
    let prediction: Int
    let errors: Int64
    var split: Split? = nil
    var surrogates: [Surrogate] = []
    var defaultLeft = true
    var children: (left: Int, right: Int)? = nil
}

func candidates(_ attribute: Int, _ attributes: [Attribute], _ rows: [Row], _ labels: [Int], _ classes: Int) -> [Candidate] {
    let values = Set(rows.map { $0.values[attribute]! }).sorted()
    guard values.count > 1 else { return [] }
    let points = attributes[attribute].integer ? zip(values, values.dropFirst()).map { first, second in first + second } : values
    return points.map { point in
        let split = Split(attribute: attribute, point: point)
        var left = Array<Int64>(repeating: 0, count: classes)
        var right = Array<Int64>(repeating: 0, count: classes)
        for (row, label) in zip(rows, labels) {
            if split.goesLeft(row.values[attribute]!, attributes) { left[label] += 1 }
            else { right[label] += 1 }
        }
        return Candidate(split: split, left: left, right: right)
    }
}

struct TreeBuilder {
    let attributes: [Attribute]
    let classes: Int
    let settings: Settings

    func bestSplit(_ rows: [Row], _ selectedAttributes: [Int]) -> Candidate? {
        let labels = rows.map(\.label)
        var best: Candidate?
        for attribute in selectedAttributes {
            for candidate in candidates(attribute, attributes, rows, labels, classes) {
                if candidate.leftSize < Int64(settings.minLeaf) || candidate.rightSize < Int64(settings.minLeaf) { continue }
                if best == nil || candidate.value.compare(best!.value) > 0 { best = candidate }
            }
        }
        return best
    }

    func findSurrogates(_ rows: [Row], _ primary: Split) -> [Surrogate] {
        let labels = rows.map { primary.goesLeft($0.values[primary.attribute]!, attributes) ? 0 : 1 }
        let left = Int64(labels.filter { $0 == 0 }.count)
        let size = Int64(rows.count)
        let baseline = max(left, size - left)
        var selected: [Surrogate] = []
        for attribute in attributes.indices where attribute != primary.attribute {
            var best: Surrogate?
            for candidate in candidates(attribute, attributes, rows, labels, 2) {
                let agreement = candidate.left[0] + candidate.right[1]
                let forward = agreement >= size - agreement
                let score = max(agreement, size - agreement)
                if best == nil || score > best!.score { best = Surrogate(split: candidate.split, forward: forward, score: score) }
            }
            if let best, best.score > baseline { selected.append(best) }
        }
        selected.sort { $0.score == $1.score ? $0.split.attribute < $1.split.attribute : $0.score > $1.score }
        return Array(selected.prefix(settings.maxSurrogates))
    }

    func grow(_ rows: [Row]) -> [Node] {
        var nodes: [Node] = []
        growNode(rows, 1, 0, &nodes)
        return nodes
    }

    @discardableResult
    private func growNode(_ rows: [Row], _ number: Int, _ depth: Int, _ nodes: inout [Node]) -> Int {
        let counts = classCounts(rows, classes)
        let predicted = majority(counts)
        let index = nodes.count
        nodes.append(Node(number: number, depth: depth, counts: counts, size: Int64(rows.count),
            prediction: predicted, errors: errorCount(counts)))
        if counts[predicted] == Int64(rows.count) || depth == settings.maxDepth || rows.count < settings.minSplit { return index }
        guard let best = bestSplit(rows, Array(attributes.indices)), improves(best.value, counts) else { return index }
        let split = best.split
        let left = rows.filter { split.goesLeft($0.values[split.attribute]!, attributes) }
        let right = rows.filter { !split.goesLeft($0.values[split.attribute]!, attributes) }
        nodes[index].split = split
        nodes[index].surrogates = findSurrogates(rows, split)
        nodes[index].defaultLeft = left.count >= right.count
        let leftChild = growNode(left, number * 2, depth + 1, &nodes)
        let rightChild = growNode(right, number * 2 + 1, depth + 1, &nodes)
        nodes[index].children = (leftChild, rightChild)
        return index
    }
}
