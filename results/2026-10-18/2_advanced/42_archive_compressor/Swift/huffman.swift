private final class HuffmanNode {
    let weight: Int
    let minimum: Int
    let symbol: Int?
    let children: [HuffmanNode]

    init(weight: Int, minimum: Int, symbol: Int?, children: [HuffmanNode] = []) {
        self.weight = weight
        self.minimum = minimum
        self.symbol = symbol
        self.children = children
    }
}

func treeLengths(_ frequencies: [Int]) -> [Int] {
    var lengths = Array(repeating: 0, count: frequencies.count)
    var nodes = frequencies.indices.filter { frequencies[$0] > 0 }.map {
        HuffmanNode(weight: frequencies[$0], minimum: $0, symbol: $0)
    }
    if nodes.isEmpty { return lengths }
    if nodes.count == 1 { lengths[nodes[0].minimum] = 1; return lengths }
    while nodes.count > 1 {
        nodes.sort { $0.weight == $1.weight ? $0.minimum < $1.minimum : $0.weight < $1.weight }
        let first = nodes.removeFirst()
        let second = nodes.removeFirst()
        nodes.append(HuffmanNode(weight: first.weight + second.weight, minimum: min(first.minimum, second.minimum),
                                  symbol: nil, children: [first, second]))
    }
    var pending = [(nodes[0], 0)]
    while let (node, depth) = pending.popLast() {
        if let symbol = node.symbol { lengths[symbol] = depth }
        else { pending += node.children.map { ($0, depth + 1) } }
    }
    return lengths
}

func limitedLengths(_ frequencies: [Int], _ maximum: Int) -> (lengths: [Int], halvings: Int) {
    var weights = frequencies
    var halvings = 0
    while true {
        let lengths = treeLengths(weights)
        if (lengths.max() ?? 0) <= maximum { return (lengths, halvings) }
        weights = weights.map { ($0 + 1) / 2 }
        halvings += 1
    }
}

func canonicalCodes(_ lengths: [Int]) -> [Int] {
    let ordered = lengths.indices.filter { lengths[$0] > 0 }.sorted {
        lengths[$0] == lengths[$1] ? $0 < $1 : lengths[$0] < lengths[$1]
    }
    var codes = Array(repeating: 0, count: lengths.count)
    var code = 0
    var previousLength = 0
    for (index, symbol) in ordered.enumerated() {
        if index > 0 { code = (code + 1) << (lengths[symbol] - previousLength) }
        codes[symbol] = code
        previousLength = lengths[symbol]
    }
    return codes
}
