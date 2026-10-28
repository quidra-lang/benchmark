import Foundation

struct NodePair: Hashable { let first: Int; let second: Int; init(_ first: Int, _ second: Int) { self.first = min(first, second); self.second = max(first, second) } }
struct Edge { let first: Int; let second: Int; let length: Double }
struct Tree {
    let size: Int
    var adjacent: [Int: [Int: Double]]
    var nextNode: Int
    var negative = 0
    init(_ size: Int, _ taxa: [Int]) { self.size = size; adjacent = Dictionary(uniqueKeysWithValues: taxa.map { ($0, [:]) }); nextNode = size }
    mutating func internalNode() -> Int { let node = nextNode; nextNode += 1; adjacent[node] = [:]; return node }
    mutating func connect(_ first: Int, _ second: Int, _ length: Double = 0) { adjacent[first, default: [:]][second] = length; adjacent[second, default: [:]][first] = length }
    @discardableResult mutating func disconnect(_ first: Int, _ second: Int) -> Double { let length = adjacent[first]!.removeValue(forKey: second)!; adjacent[second]!.removeValue(forKey: first); return length }
    var taxa: [Int] { adjacent.keys.filter { $0 < size }.sorted() }
    var internalNodes: [Int] { adjacent.keys.filter { $0 >= size }.sorted() }
    var edges: [Edge] { adjacent.keys.sorted().flatMap { first in adjacent[first]!.keys.sorted().filter { first < $0 }.map { Edge(first: first, second: $0, length: adjacent[first]![$0]!) } } }
    func rooted(_ outgroup: Int) -> Rooted { Rooted(self, outgroup) }
}
struct Rooted {
    let tree: Tree
    let outgroup: Int
    let root: Int
    let parents: [Int: Int]
    let children: [Int: [Int]]
    let masks: [Int: Int]
    let order: [Int]
    let ingroup: Int
    init(_ tree: Tree, _ outgroup: Int) {
        let root = tree.adjacent[outgroup]!.keys.first!
        var parents: [Int: Int] = [:], children: [Int: [Int]] = [:], masks: [Int: Int] = [:], order: [Int] = []
        func visit(_ node: Int, _ parent: Int?) { if let parent { parents[node] = parent }; order.append(node); let descendants = tree.adjacent[node]!.keys.filter { $0 != parent }.sorted(); children[node] = descendants; var mask = node < tree.size ? 1 << node : 0; for child in descendants { visit(child, node); mask |= masks[child]! }; masks[node] = mask }
        visit(root, nil)
        self.tree = tree; self.outgroup = outgroup; self.root = root; self.parents = parents; self.children = children; self.masks = masks; self.order = order; ingroup = masks[root]! ^ (1 << outgroup)
    }
    func splits() -> Set<Int> { Set(tree.internalNodes.filter { $0 != root }.map { masks[$0]! }) }
    func branchLengths() -> [Int: Double] { Dictionary(uniqueKeysWithValues: order.dropFirst().map { node in (node == outgroup ? ingroup : masks[node]!, tree.adjacent[node]![parents[node]!]!) }) }
}
func star(_ size: Int, _ taxa: [Int]) -> Tree { var tree = Tree(size, taxa); let root = tree.internalNode(); for taxon in taxa { tree.connect(root, taxon) }; return tree }
func neighborJoining(_ matrix: [[Double]], _ taxa: [Int]) -> Tree {
    var active = taxa, tree = Tree(matrix.count, taxa), distances = Dictionary(uniqueKeysWithValues: taxa.map { first in (first, Dictionary(uniqueKeysWithValues: taxa.map { ($0, matrix[first][$0]) })) })
    while active.count >= 4 {
        let count = active.count
        var totals: [Int: Double] = [:], minimum = Double.infinity, chosen = (active[0], active[1])
        for first in active { var total = 0.0; for second in active where first != second { total += distances[first]![second]! }; totals[first] = total }
        for index in active.indices { let first = active[index]; for second in active.dropFirst(index + 1) { let value = Double(count - 2) * distances[first]![second]! - totals[first]! - totals[second]!; if value < minimum { minimum = value; chosen = (first, second) } } }
        let first = chosen.0, second = chosen.1, node = tree.internalNode(), distance = distances[first]![second]!, length = distance / 2 + (totals[first]! - totals[second]!) / Double(2 * (count - 2)), remaining = active.filter { $0 != first && $0 != second }
        tree.connect(first, node, length); tree.connect(second, node, distance - length); distances[node] = [:]
        for other in remaining { let value = (distances[first]![other]! + distances[second]![other]! - distance) / 2; distances[node]![other] = value; distances[other]![node] = value }
        active = remaining + [node]
    }
    let first = active[0], second = active[1], third = active[2], node = tree.internalNode(), a = distances[first]![second]!, b = distances[first]![third]!, c = distances[second]![third]!
    tree.connect(first, node, (a + b - c) / 2); tree.connect(second, node, (a + c - b) / 2); tree.connect(third, node, (b + c - a) / 2)
    for edge in tree.edges where edge.length < 0 { tree.connect(edge.first, edge.second, 0); tree.negative += 1 }
    return tree
}
func pathDistances(_ tree: Tree, _ start: Int) -> [Int: Double] { var distances = [start: 0.0], stack = [(start, -1)]; while let (node, parent) = stack.popLast() { for neighbor in tree.adjacent[node]!.keys.sorted() where neighbor != parent { distances[neighbor] = distances[node]! + tree.adjacent[node]![neighbor]!; stack.append((neighbor, node)) } }; return distances }
func pathSteps(_ tree: Tree, _ start: Int) -> [Int: Int] { var distances = [start: 0], stack = [(start, -1)]; while let (node, parent) = stack.popLast() { for neighbor in tree.adjacent[node]!.keys.sorted() where neighbor != parent { distances[neighbor] = distances[node]! + 1; stack.append((neighbor, node)) } }; return distances }
func patristicMatrix(_ tree: Tree) -> [[Double]] { var matrix = Array(repeating: Array(repeating: 0.0, count: tree.size), count: tree.size); let taxa = tree.taxa; for (index, first) in taxa.enumerated() { let distances = pathDistances(tree, first); for second in taxa.dropFirst(index + 1) { matrix[first][second] = distances[second]!; matrix[second][first] = distances[second]! } }; return matrix }
