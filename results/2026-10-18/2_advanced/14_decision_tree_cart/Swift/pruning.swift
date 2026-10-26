struct Decision {
    let node: Int
    let rows: Int
    let leafError: Int64
    let subtreeError: Int64
    let pruned: Bool
}

struct SequenceTree {
    let alpha: Fraction
    let tree: PrunedTree
}

private func decide(_ index: Int, _ nodes: [Node], _ reached: [[Int]], _ rows: [Row], _ decisions: inout [Decision], _ cut: inout Set<Int>) -> Int64 {
    let node = nodes[index]
    let leafError = Int64(reached[index].filter { rows[$0].label != node.prediction }.count)
    guard let children = node.children else { return leafError }
    let leftError = decide(children.left, nodes, reached, rows, &decisions, &cut)
    let rightError = decide(children.right, nodes, reached, rows, &decisions, &cut)
    let subtreeError = leftError + rightError
    let pruned = leafError <= subtreeError
    decisions.append(Decision(node: index, rows: reached[index].count, leafError: leafError, subtreeError: subtreeError, pruned: pruned))
    if pruned { cut.insert(index) }
    return pruned ? leafError : subtreeError
}

func reducedErrorPruning(_ nodes: [Node], _ rows: [Row], _ attributes: [Attribute]) -> (tree: PrunedTree, decisions: [Decision]) {
    let grown = PrunedTree(nodes: nodes)
    var reached = Array(repeating: [Int](), count: nodes.count)
    for (index, row) in rows.enumerated() { for node in grown.route(row, attributes).path { reached[node].append(index) } }
    var decisions: [Decision] = []
    var cut: Set<Int> = []
    _ = decide(0, nodes, reached, rows, &decisions, &cut)
    return (PrunedTree(nodes: nodes, cut: cut), decisions)
}

func costComplexitySequence(_ nodes: [Node]) -> [SequenceTree] {
    var tree = PrunedTree(nodes: nodes)
    var sequence = [SequenceTree(alpha: Fraction(numerator: 0, denominator: 1), tree: tree)]
    while !tree.isLeaf(0) {
        var alpha: Fraction?
        var weakest: Set<Int> = []
        for index in tree.internalNodes() {
            let leaves = tree.leaves(index)
            let errors = leaves.reduce(Int64(0)) { $0 + nodes[$1].errors }
            let strength = Fraction(numerator: nodes[index].errors - errors, denominator: Int64(leaves.count - 1))
            if alpha == nil || strength.compare(alpha!) < 0 {
                alpha = strength
                weakest = [index]
            } else if strength.compare(alpha!) == 0 { weakest.insert(index) }
        }
        tree.cut.formUnion(weakest)
        sequence.append(SequenceTree(alpha: alpha!, tree: tree))
    }
    return sequence
}
