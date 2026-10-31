struct Pattern {
    let items: [String]
    let weight: Int
}
final class FPNode {
    let item: String
    let parent: Int
    var count = 0
    var children: [String: Int] = [:]
    init(_ item: String, _ parent: Int) { self.item = item; self.parent = parent }
}
final class FPTree {
    let header: [String]
    var nodes = [FPNode("", -1)]
    var links: [String: [Int]] = [:]
    var nodeCount: Int { nodes.count - 1 }
    init(_ base: [Pattern], _ minimum: Int) {
        var supports: [String: Int] = [:]
        for pattern in base { for item in pattern.items { supports[item, default: 0] += pattern.weight } }
        header = supports.keys.filter { supports[$0]! >= minimum }.sorted { supports[$0]! == supports[$1]! ? $0 < $1 : supports[$0]! > supports[$1]! }
        let order = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        for item in header { links[item] = [] }
        for pattern in base {
            var cursor = 0
            for item in pattern.items.filter({ order[$0] != nil }).sorted(by: { order[$0]! < order[$1]! }) {
                let child: Int
                if let existing = nodes[cursor].children[item] { child = existing }
                else { child = nodes.count; nodes.append(FPNode(item, cursor)); nodes[cursor].children[item] = child; links[item]!.append(child) }
                nodes[child].count += pattern.weight
                cursor = child
            }
        }
    }
    func support(_ item: String) -> Int { links[item]!.reduce(0) { $0 + nodes[$1].count } }
    func conditionalBase(_ item: String) -> [Pattern] {
        links[item]!.map { index in
            var path: [String] = []
            var parent = nodes[index].parent
            while parent > 0 { path.append(nodes[parent].item); parent = nodes[parent].parent }
            return Pattern(items: Array(path.reversed()), weight: nodes[index].count)
        }
    }
}
struct GrowthResult {
    let header: Int
    let nodes: Int
    var conditionalTrees = 0
    var conditionalNodes = 0
    var itemsets: [[String]: Int] = [:]
}
func fpGrowth(_ base: [Pattern], _ minimum: Int, _ maxSize: Int) -> GrowthResult {
    let tree = FPTree(base, minimum)
    var result = GrowthResult(header: tree.header.count, nodes: tree.nodeCount)
    var stack: [(FPTree, [String])] = [(tree, [])]
    while let (current, suffix) = stack.popLast() {
        for item in current.header.reversed() {
            let items = (suffix + [item]).sorted()
            result.itemsets[items] = current.support(item)
            if items.count < maxSize {
                let conditional = FPTree(current.conditionalBase(item), minimum)
                if conditional.nodeCount > 0 { stack.append((conditional, items)); result.conditionalTrees += 1; result.conditionalNodes += conditional.nodeCount }
            }
        }
    }
    return result
}
