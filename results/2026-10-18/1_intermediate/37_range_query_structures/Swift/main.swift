import Foundation

enum CommandError: Error { case invalid(String) }
enum Kind: String, CaseIterable { case seg = "SEG", lazy = "LAZY", fen = "FEN", rfen = "RFEN", sparse = "SPARSE", sqrt = "SQRT", persist = "PERSIST" }
enum Operation: String {
    case sum = "SUM", min = "MIN", max = "MAX", gcd = "GCD"
    func combine(_ a: Int, _ b: Int) -> Int {
        switch self {
        case .sum: return a + b
        case .min: return Swift.min(a, b)
        case .max: return Swift.max(a, b)
        case .gcd: return greatestCommonDivisor(a, b)
        }
    }
}
struct Span {
    let left: Int, right: Int
    var middle: Int { (left + right) / 2 }
    var leaf: Bool { left == right }
    var length: Int { right - left + 1 }
    var leftChild: Span { Span(left: left, right: middle) }
    var rightChild: Span { Span(left: middle + 1, right: right) }
    func covers(_ other: Span) -> Bool { left <= other.left && other.right <= right }
}
struct Aggregate {
    let sum: Int, minimum: Int, maximum: Int
    var text: String { "sum=\(sum) min=\(minimum) max=\(maximum)" }
    var values: [Int] { [sum, minimum, maximum] }
    func merged(with other: Aggregate) -> Aggregate {
        Aggregate(sum: sum + other.sum, minimum: min(minimum, other.minimum), maximum: max(maximum, other.maximum))
    }
}
struct Answer {
    let value: Int, visited: Int
    var text: String { "sum=\(value) visited=\(visited)" }
    var report: Report { Report(text: text, values: [value]) }
}
struct Counts { var visited = 0, covered = 0, pushes = 0 }
struct Report { let text: String; let values: [Int] }
struct BlockAnswer {
    let sum: Int, whole: Int, cells: Int
    var partition: String { "whole=\(whole) cells=\(cells)" }
}
func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
    var a = abs(a), b = abs(b)
    while b != 0 { (a, b) = (b, a % b) }
    return a
}
func lowbit(_ value: Int) -> Int { value & -value }
func floorLog(_ value: Int) -> Int { Int.bitWidth - 1 - value.leadingZeroBitCount }
func integerSqrt(_ value: Int) -> Int {
    var root = 1
    while (root + 1) * (root + 1) <= value { root += 1 }
    return root
}
func words<S: Sequence>(_ values: S) -> String where S.Element == Int { values.map(String.init).joined(separator: " ") }
func fullSpan(_ count: Int) -> Span { Span(left: 0, right: count - 1) }

final class SegmentTree {
    struct Node { let span: Span; var value: Int }
    let operation: Operation, count: Int
    private(set) var nodes: [Node?]
    private var maxNode = 0
    init(_ values: [Int], operation: Operation) {
        self.operation = operation; count = values.count
        nodes = Array(repeating: nil, count: 4 * count)
        build(values, index: 1, span: fullSpan(count))
    }
    private func build(_ values: [Int], index: Int, span: Span) {
        maxNode = max(maxNode, index)
        let value: Int
        if span.leaf { value = operation == .gcd ? abs(values[span.left]) : values[span.left] }
        else {
            build(values, index: 2 * index, span: span.leftChild)
            build(values, index: 2 * index + 1, span: span.rightChild)
            value = operation.combine(nodes[2 * index]!.value, nodes[2 * index + 1]!.value)
        }
        nodes[index] = Node(span: span, value: value)
    }
    func query(_ range: Span, index: Int = 1) -> Answer {
        let node = nodes[index]!
        if range.covers(node.span) { return Answer(value: node.value, visited: 1) }
        let answer: Answer
        if range.right <= node.span.middle { answer = query(range, index: 2 * index) }
        else if range.left > node.span.middle { answer = query(range, index: 2 * index + 1) }
        else {
            let left = query(range, index: 2 * index), right = query(range, index: 2 * index + 1)
            answer = Answer(value: operation.combine(left.value, right.value), visited: left.visited + right.visited)
        }
        return Answer(value: answer.value, visited: answer.visited + 1)
    }
    func update(_ position: Int, value: Int, index: Int = 1) -> Int {
        let span = nodes[index]!.span
        if span.leaf { nodes[index]!.value = operation == .gcd ? abs(value) : value; return 1 }
        let visited = update(position, value: value, index: position <= span.middle ? 2 * index : 2 * index + 1)
        nodes[index]!.value = operation.combine(nodes[2 * index]!.value, nodes[2 * index + 1]!.value)
        return visited + 1
    }
    var root: Int { nodes[1]!.value }
    var buildLine: String { "SEG BUILD \(operation.rawValue) nodes=\(2 * count - 1) maxnode=\(maxNode) root=\(root)" }
    func dump() -> [String] {
        var rows = ["SEG DUMP \(operation.rawValue) nodes=\(2 * count - 1)"]
        for (index, entry) in nodes.enumerated() {
            if let node = entry { rows.append("NODE \(index) \(node.span.left) \(node.span.right) \(node.value)") }
        }
        return rows
    }
}
final class LazyTree {
    struct Node { let span: Span; var value: Aggregate; var assignment: Int? = nil; var addition = 0 }
    let count: Int
    private var nodes: [Node?]
    init(_ values: [Int]) {
        count = values.count; nodes = Array(repeating: nil, count: 4 * count)
        build(values, index: 1, span: fullSpan(count))
    }
    private func build(_ values: [Int], index: Int, span: Span) {
        let value: Aggregate
        if span.leaf { value = Aggregate(sum: values[span.left], minimum: values[span.left], maximum: values[span.left]) }
        else {
            build(values, index: 2 * index, span: span.leftChild)
            build(values, index: 2 * index + 1, span: span.rightChild)
            value = nodes[2 * index]!.value.merged(with: nodes[2 * index + 1]!.value)
        }
        nodes[index] = Node(span: span, value: value)
    }
    private func pull(_ index: Int) { nodes[index]!.value = nodes[2 * index]!.value.merged(with: nodes[2 * index + 1]!.value) }
    private func apply(_ index: Int, value: Int, assignment: Bool) {
        var node = nodes[index]!
        if assignment { node.value = Aggregate(sum: value * node.span.length, minimum: value, maximum: value) }
        else { node.value = Aggregate(sum: node.value.sum + value * node.span.length, minimum: node.value.minimum + value, maximum: node.value.maximum + value) }
        if !node.span.leaf {
            if assignment { node.assignment = value; node.addition = 0 }
            else { node.addition += value }
        }
        nodes[index] = node
    }
    private func push(_ index: Int) -> Int {
        let node = nodes[index]!
        if node.assignment == nil && node.addition == 0 { return 0 }
        for child in [2 * index, 2 * index + 1] {
            if let value = node.assignment { apply(child, value: value, assignment: true) }
            if node.addition != 0 { apply(child, value: node.addition, assignment: false) }
        }
        nodes[index]!.assignment = nil; nodes[index]!.addition = 0
        return 1
    }
    func update(_ range: Span, value: Int, assignment: Bool) -> Counts {
        var counts = Counts()
        func visit(_ index: Int) {
            counts.visited += 1
            let span = nodes[index]!.span
            if range.covers(span) { counts.covered += 1; apply(index, value: value, assignment: assignment); return }
            counts.pushes += push(index)
            if range.left <= span.middle { visit(2 * index) }
            if range.right > span.middle { visit(2 * index + 1) }
            pull(index)
        }
        visit(1)
        return counts
    }
    func query(_ range: Span) -> Report {
        var counts = Counts()
        func visit(_ index: Int) -> Aggregate {
            counts.visited += 1
            let span = nodes[index]!.span
            if range.covers(span) { return nodes[index]!.value }
            counts.pushes += push(index)
            if range.right <= span.middle { return visit(2 * index) }
            if range.left > span.middle { return visit(2 * index + 1) }
            let left = visit(2 * index), right = visit(2 * index + 1)
            return left.merged(with: right)
        }
        let value = visit(1)
        return Report(text: "\(value.text) visited=\(counts.visited) pushes=\(counts.pushes)", values: value.values)
    }
    var buildLine: String { "LAZY BUILD nodes=\(2 * count - 1) \(nodes[1]!.value.text)" }
    func dump() -> [String] {
        var rows = ["LAZY DUMP nodes=\(2 * count - 1)"]
        for (index, entry) in nodes.enumerated() {
            if let node = entry {
                rows.append("NODE \(index) \(node.span.left) \(node.span.right) \(node.value.text) assign=\(node.assignment.map(String.init) ?? "-") add=\(node.addition)")
            }
        }
        return rows
    }
}

final class Bit {
    private(set) var tree: [Int]
    init(_ values: [Int]) {
        tree = [0] + values
        for position in 1..<tree.count {
            let parent = position + lowbit(position)
            if parent < tree.count { tree[parent] += tree[position] }
        }
    }
    func add(_ position: Int, value: Int) -> Int {
        var position = position, visited = 0
        while position < tree.count { tree[position] += value; visited += 1; position += lowbit(position) }
        return visited
    }
    func prefix(_ position: Int) -> Answer {
        var position = position, sum = 0, visited = 0
        while position > 0 { sum += tree[position]; visited += 1; position -= lowbit(position) }
        return Answer(value: sum, visited: visited)
    }
    func query(_ range: Span) -> Answer {
        let right = prefix(range.right + 1), left = prefix(range.left)
        return Answer(value: right.value - left.value, visited: right.visited + left.visited)
    }
    func lower(_ target: Int) -> Answer {
        let count = tree.count - 1
        var step = 1 << floorLog(count), position = 0, rest = target, visited = 0
        while step > 0 {
            if position + step <= count {
                visited += 1
                if tree[position + step] < rest { rest -= tree[position + step]; position += step }
            }
            step /= 2
        }
        return Answer(value: position < count ? position : -1, visited: visited)
    }
    var text: String { words(tree.dropFirst()) }
}
final class FenwickArray {
    private(set) var values: [Int]
    let bit: Bit
    init(_ values: [Int]) { self.values = values; bit = Bit(values) }
    func add(_ index: Int, value: Int) -> Int { values[index] += value; return bit.add(index + 1, value: value) }
    var buildLine: String { "FEN BUILD n=\(values.count) total=\(values.reduce(0, +))" }
    func dump() -> [String] { ["FEN DUMP n=\(values.count)", "T \(bit.text)"] }
}
final class RangeFenwick {
    let first: Bit, second: Bit
    init(_ values: [Int]) {
        let differences = values.enumerated().map { index, value in value - (index == 0 ? 0 : values[index - 1]) }
        first = Bit(differences)
        second = Bit(differences.enumerated().map { index, value in index * value })
    }
    func add(_ range: Span, value: Int) -> Int {
        var visited = first.add(range.left + 1, value: value)
        visited += first.add(range.right + 2, value: -value)
        visited += second.add(range.left + 1, value: value * range.left)
        visited += second.add(range.right + 2, value: -value * (range.right + 1))
        return visited
    }
    private func prefix(_ position: Int) -> Answer {
        let a = first.prefix(position), b = second.prefix(position)
        return Answer(value: position * a.value - b.value, visited: a.visited + b.visited)
    }
    func query(_ range: Span) -> Answer {
        let a = prefix(range.right + 1), b = prefix(range.left)
        return Answer(value: a.value - b.value, visited: a.visited + b.visited)
    }
    var buildLine: String { "RFEN BUILD n=\(first.tree.count - 1) total=\(prefix(first.tree.count - 1).value)" }
    func dump() -> [String] { ["RFEN DUMP n=\(first.tree.count - 1)", "B1 \(first.text)", "B2 \(second.text)"] }
}
final class SparseTable {
    let values: [Int]
    private var minima: [[Int]], maxima: [[Int]]
    init(_ values: [Int]) {
        self.values = values; minima = [Array(values.indices)]; maxima = [Array(values.indices)]
        var width = 2
        while width <= values.count {
            var lows: [Int] = [], highs: [Int] = []
            for index in 0...(values.count - width) {
                let a = minima.last![index], b = minima.last![index + width / 2]
                let c = maxima.last![index], d = maxima.last![index + width / 2]
                lows.append(values[a] <= values[b] ? a : b)
                highs.append(values[c] >= values[d] ? c : d)
            }
            minima.append(lows); maxima.append(highs); width *= 2
        }
    }
    func query(_ range: Span) -> Report {
        let level = floorLog(range.length), end = range.right - (1 << level) + 1
        let a = minima[level][range.left], b = minima[level][end], c = maxima[level][range.left], d = maxima[level][end]
        let low = values[a] <= values[b] ? a : b, high = values[c] >= values[d] ? c : d
        return Report(text: "min=\(values[low]) minpos=\(low) max=\(values[high]) maxpos=\(high) level=\(level)", values: [values[low], values[high]])
    }
    var buildLine: String { "SPARSE BUILD levels=\(minima.count) entries=\(minima.reduce(0) { $0 + $1.count })" }
    func dump() -> [String] {
        var rows = ["SPARSE DUMP levels=\(minima.count)"]
        for level in minima.indices { rows.append("MIN \(level) \(words(minima[level]))"); rows.append("MAX \(level) \(words(maxima[level]))") }
        return rows
    }
}
final class SquareRoot {
    let block: Int
    private var raw: [Int], tags: [Int], sums: [Int]
    init(_ values: [Int], block: Int) {
        self.block = block; raw = values
        tags = Array(repeating: 0, count: (values.count + block - 1) / block); sums = tags
        for index in values.indices { sums[index / block] += values[index] }
    }
    private func split(_ range: Span) -> (cells: [Int], whole: [Int]) {
        let first = range.left / block, last = range.right / block
        if first == last { return (Array(range.left...range.right), []) }
        return (Array(range.left..<((first + 1) * block)) + Array((last * block)...range.right), Array((first + 1)..<last))
    }
    func add(_ range: Span, value: Int) -> BlockAnswer {
        let parts = split(range)
        for index in parts.cells { raw[index] += value; sums[index / block] += value }
        for index in parts.whole { tags[index] += value; sums[index] += value * block }
        return BlockAnswer(sum: 0, whole: parts.whole.count, cells: parts.cells.count)
    }
    func query(_ range: Span) -> BlockAnswer {
        let parts = split(range)
        let total = parts.cells.reduce(0) { $0 + raw[$1] + tags[$1 / block] } + parts.whole.reduce(0) { $0 + sums[$1] }
        return BlockAnswer(sum: total, whole: parts.whole.count, cells: parts.cells.count)
    }
    var buildLine: String { "SQRT BUILD block=\(block) blocks=\(tags.count)" }
    func dump() -> [String] {
        var rows = ["SQRT DUMP block=\(block) blocks=\(tags.count)"]
        for index in tags.indices {
            let first = index * block, end = min(first + block, raw.count)
            rows.append("BLOCK \(index) \(first) \(end - 1) add=\(tags[index]) sum=\(sums[index]) \(words(raw[first..<end]))")
        }
        return rows
    }
}

final class PersistentNode {
    let sum: Int
    let left: PersistentNode?, right: PersistentNode?
    init(_ sum: Int, left: PersistentNode? = nil, right: PersistentNode? = nil) { self.sum = sum; self.left = left; self.right = right }
}
final class PersistentTree {
    let count: Int
    private(set) var created = 0
    private(set) var roots: [PersistentNode] = []
    init(_ values: [Int]) { count = values.count; roots.append(build(values, span: fullSpan(count))) }
    private func node(_ sum: Int, left: PersistentNode? = nil, right: PersistentNode? = nil) -> PersistentNode {
        created += 1
        return PersistentNode(sum, left: left, right: right)
    }
    private func build(_ values: [Int], span: Span) -> PersistentNode {
        if span.leaf { return node(values[span.left]) }
        let left = build(values, span: span.leftChild), right = build(values, span: span.rightChild)
        return node(left.sum + right.sum, left: left, right: right)
    }
    private func copyPath(_ previous: PersistentNode, span: Span, index: Int, value: Int, addition: Bool) -> PersistentNode {
        if span.leaf { return node(addition ? previous.sum + value : value) }
        var left = previous.left!, right = previous.right!
        if index <= span.middle { left = copyPath(left, span: span.leftChild, index: index, value: value, addition: addition) }
        else { right = copyPath(right, span: span.rightChild, index: index, value: value, addition: addition) }
        return node(left.sum + right.sum, left: left, right: right)
    }
    func fork(_ version: Int, index: Int, value: Int, addition: Bool = false) -> Int {
        let before = created
        let root = copyPath(roots[version], span: fullSpan(count), index: index, value: value, addition: addition)
        roots.append(root)
        return created - before
    }
    func query(_ version: Int, range: Span) -> Answer {
        func visit(_ node: PersistentNode, span: Span) -> Answer {
            if range.covers(span) { return Answer(value: node.sum, visited: 1) }
            let answer: Answer
            if range.right <= span.middle { answer = visit(node.left!, span: span.leftChild) }
            else if range.left > span.middle { answer = visit(node.right!, span: span.rightChild) }
            else {
                let left = visit(node.left!, span: span.leftChild), right = visit(node.right!, span: span.rightChild)
                answer = Answer(value: left.value + right.value, visited: left.visited + right.visited)
            }
            return Answer(value: answer.value, visited: answer.visited + 1)
        }
        return visit(roots[version], span: fullSpan(count))
    }
}
final class Persistence {
    let positions: PersistentTree
    private let prefixes: PersistentTree, domain: [Int]
    init(_ values: [Int]) {
        positions = PersistentTree(values)
        domain = Array(Set(values)).sorted()
        prefixes = PersistentTree(Array(repeating: 0, count: domain.count))
        let ranks = Dictionary(uniqueKeysWithValues: domain.enumerated().map { ($0.element, $0.offset) })
        for (index, value) in values.enumerated() { _ = prefixes.fork(index, index: ranks[value]!, value: 1, addition: true) }
    }
    func kth(_ range: Span, k: Int) -> Answer {
        var upper = prefixes.roots[range.right + 1], lower = prefixes.roots[range.left]
        var left = 0, right = domain.count - 1, k = k, visited = 1
        while left < right {
            let middle = (left + right) / 2, count = upper.left!.sum - lower.left!.sum
            if k <= count { upper = upper.left!; lower = lower.left!; right = middle }
            else { k -= count; upper = upper.right!; lower = lower.right!; left = middle + 1 }
            visited += 1
        }
        return Answer(value: domain[left], visited: visited)
    }
    var buildLine: String { "PERSIST BUILD nodes=\(positions.created) distinct=\(domain.count) valuenodes=\(prefixes.created)" }
    var nodeLine: String { "PERSIST NODES versions=\(positions.roots.count) position=\(positions.created) value=\(prefixes.created)" }
}
final class Grid {
    let height: Int, width: Int
    private var tree: [[Int]]
    init(height: Int, width: Int, values: [Int]) {
        self.height = height; self.width = width
        tree = Array(repeating: Array(repeating: 0, count: width + 1), count: height + 1)
        for (index, value) in values.enumerated() { _ = add(index / width, column: index % width, value: value) }
    }
    func check(_ row: Int, _ column: Int) throws {
        if row < 0 || row >= height || column < 0 || column >= width { throw CommandError.invalid("BAD CELL \(row) \(column)") }
    }
    func add(_ row: Int, column: Int, value: Int) -> Int {
        var y = row + 1, visited = 0
        while y <= height {
            var x = column + 1
            while x <= width { tree[y][x] += value; visited += 1; x += lowbit(x) }
            y += lowbit(y)
        }
        return visited
    }
    private func prefix(_ row: Int, _ column: Int) -> Answer {
        var y = row, sum = 0, visited = 0
        while y > 0 {
            var x = column
            while x > 0 { sum += tree[y][x]; visited += 1; x -= lowbit(x) }
            y -= lowbit(y)
        }
        return Answer(value: sum, visited: visited)
    }
    func query(_ row: Int, _ column: Int, _ bottom: Int, _ right: Int) -> Answer {
        let a = prefix(bottom + 1, right + 1), b = prefix(row, right + 1), c = prefix(bottom + 1, column), d = prefix(row, column)
        return Answer(value: a.value - b.value - c.value + d.value, visited: a.visited + b.visited + c.visited + d.visited)
    }
    func dump() -> [String] {
        ["GRID DUMP rows=\(height) cols=\(width)"] + (1...height).map { "ROW \($0) \(words(tree[$0].dropFirst()))" }
    }
}
func mo(_ values: [Int], ranges: [Span]) -> [String] {
    let block = integerSqrt(values.count)
    let order = ranges.indices.sorted { a, b in
        let first = ranges[a].left / block, second = ranges[b].left / block
        if first != second { return first < second }
        if ranges[a].right != ranges[b].right { return first % 2 == 0 ? ranges[a].right < ranges[b].right : ranges[a].right > ranges[b].right }
        return a < b
    }
    var frequency: [Int: Int] = [:], answers = Array(repeating: 0, count: ranges.count)
    var left = 0, right = -1, moves = 0
    func add(_ index: Int) { frequency[values[index], default: 0] += 1; moves += 1 }
    func remove(_ index: Int) {
        let value = values[index], count = frequency[value]! - 1
        if count == 0 { frequency.removeValue(forKey: value) } else { frequency[value] = count }
        moves += 1
    }
    for index in order {
        let range = ranges[index]
        while left > range.left { left -= 1; add(left) }
        while right < range.right { right += 1; add(right) }
        while left < range.left { remove(left); left += 1 }
        while right > range.right { remove(right); right -= 1 }
        answers[index] = frequency.count
    }
    return ["MO queries=\(ranges.count) block=\(block) moves=\(moves)", "ORDER \(words(order.map { $0 + 1 }))"]
        + ranges.indices.map { "ANSWER \($0 + 1) \(ranges[$0].left) \(ranges[$0].right) distinct=\(answers[$0])" }
}

enum Structure {
    case seg(SegmentTree), lazy(LazyTree), fen(FenwickArray), rfen(RangeFenwick)
    case sparse(SparseTable), sqrt(SquareRoot), persist(Persistence)
    var buildLine: String {
        switch self {
        case .seg(let tree): return tree.buildLine
        case .lazy(let tree): return tree.buildLine
        case .fen(let tree): return tree.buildLine
        case .rfen(let tree): return tree.buildLine
        case .sparse(let tree): return tree.buildLine
        case .sqrt(let tree): return tree.buildLine
        case .persist(let tree): return tree.buildLine
        }
    }
    func query(_ span: Span, version: Int? = nil) -> Report {
        switch self {
        case .seg(let tree):
            let answer = tree.query(span)
            return Report(text: "\(tree.operation.rawValue.lowercased())=\(answer.value) visited=\(answer.visited)", values: [answer.value])
        case .lazy(let tree): return tree.query(span)
        case .fen(let tree): return tree.bit.query(span).report
        case .rfen(let tree): return tree.query(span).report
        case .sparse(let tree): return tree.query(span)
        case .sqrt(let tree):
            let answer = tree.query(span)
            return Report(text: "sum=\(answer.sum) \(answer.partition)", values: [answer.sum])
        case .persist(let tree): return tree.positions.query(version ?? tree.positions.roots.count - 1, range: span).report
        }
    }
    func dump() -> [String] {
        switch self {
        case .seg(let tree): return tree.dump()
        case .lazy(let tree): return tree.dump()
        case .fen(let tree): return tree.dump()
        case .rfen(let tree): return tree.dump()
        case .sparse(let tree): return tree.dump()
        case .sqrt(let tree): return tree.dump()
        case .persist: preconditionFailure("PERSIST has no DUMP command")
        }
    }
}
final class Laboratory {
    private var values: [Int], original: [Int]
    private var structures: [Kind: Structure] = [:]
    private var grid: Grid?
    init(_ values: [Int]) { self.values = values; original = values }
    private func checkIndex(_ index: Int) throws {
        if index < 0 || index >= values.count { throw CommandError.invalid("BAD INDEX \(index)") }
    }
    private func checkedRange(_ left: Int, _ right: Int) throws -> Span {
        try checkIndex(left); try checkIndex(right)
        if left > right { throw CommandError.invalid("BAD RANGE \(left) \(right)") }
        return Span(left: left, right: right)
    }
    private func checkVersion(_ version: Int, tree: Persistence) throws {
        if version < 0 || version >= tree.positions.roots.count { throw CommandError.invalid("BAD VERSION \(version)") }
    }
    private func create(_ kind: Kind, operation: Operation = .sum, block: Int = 1) -> Structure {
        switch kind {
        case .seg: return .seg(SegmentTree(values, operation: operation))
        case .lazy: return .lazy(LazyTree(values))
        case .fen: return .fen(FenwickArray(values))
        case .rfen: return .rfen(RangeFenwick(values))
        case .sparse: return .sparse(SparseTable(values))
        case .sqrt: return .sqrt(SquareRoot(values, block: block))
        case .persist: return .persist(Persistence(values))
        }
    }
    private func change(_ range: Span, value: Int, assignment: Bool = false) {
        for index in range.left...range.right { values[index] = assignment ? value : values[index] + value }
    }
    private func check(_ range: Span) -> [String] {
        let cells = values[range.left...range.right]
        let direct = Aggregate(sum: cells.reduce(0, +), minimum: cells.min()!, maximum: cells.max()!)
        let common = cells.reduce(0, greatestCommonDivisor)
        var rows = ["CHECK \(range.left) \(range.right) \(direct.text) gcd=\(common)"], ok = 0, different = 0
        for kind in Kind.allCases {
            guard let structure = structures[kind] else { continue }
            var expected = [direct.sum], prefix = ""
            switch structure {
            case .seg(let tree):
                switch tree.operation {
                case .sum: expected = [direct.sum]
                case .min: expected = [direct.minimum]
                case .max: expected = [direct.maximum]
                case .gcd: expected = [common]
                }
            case .lazy: expected = direct.values
            case .sparse: expected = [direct.minimum, direct.maximum]
            case .persist(let tree): prefix = "version=\(tree.positions.roots.count - 1) "
            default: break
            }
            let answer = structure.query(range), matches = answer.values == expected
            if matches { ok += 1 } else { different += 1 }
            rows.append("\(kind.rawValue) \(matches ? "OK" : "DIFF") \(prefix)\(answer.text)")
        }
        rows.append("RESULT ok=\(ok) diff=\(different)")
        return rows
    }
    func execute(_ line: String) throws -> [String] {
        let parts = line.split(separator: " ").map(String.init), command = parts[0]
        if command == "LOAD" {
            let removed = structures.count
            values = parts.dropFirst().map { Int($0)! }; original = values
            structures.removeAll()
            return ["LOAD n=\(values.count) removed=\(removed)"]
        }
        if command == "RESET" {
            values = original
            var operation = Operation.sum, block = 1, rebuilt = 0
            if case .seg(let tree)? = structures[.seg] { operation = tree.operation }
            if case .sqrt(let tree)? = structures[.sqrt] { block = tree.block }
            for kind in Kind.allCases where structures[kind] != nil { structures[kind] = create(kind, operation: operation, block: block); rebuilt += 1 }
            return ["RESET rebuilt=\(rebuilt)"]
        }
        if command == "ARRAY" || command == "CHECK" {
            let range = try checkedRange(Int(parts[1])!, Int(parts[2])!)
            return command == "CHECK" ? check(range) : ["\(line) \(words(values[range.left...range.right]))"]
        }
        if command == "MO" {
            var ranges: [Span] = []
            for index in stride(from: 1, to: parts.count, by: 2) { ranges.append(try checkedRange(Int(parts[index])!, Int(parts[index + 1])!)) }
            return mo(values, ranges: ranges)
        }
        let action = parts[1]
        if command == "GRID" {
            let args = parts.dropFirst(2).map { Int($0)! }
            if action == "BUILD" {
                let height = args[0], width = args[1], cells = Array(args.dropFirst(2))
                if cells.count != height * width { throw CommandError.invalid("BAD COUNT \(cells.count) \(height * width)") }
                grid = Grid(height: height, width: width, values: cells)
                return ["GRID BUILD rows=\(height) cols=\(width) total=\(cells.reduce(0, +))"]
            }
            guard let grid else { throw CommandError.invalid("NOT BUILT GRID") }
            if action == "DUMP" { return grid.dump() }
            let row = args[0], column = args[1]
            try grid.check(row, column)
            if action == "ADD" { return ["\(line) visited=\(grid.add(row, column: column, value: args[2]))"] }
            let bottom = args[2], right = args[3]
            try grid.check(bottom, right)
            if row > bottom || column > right { throw CommandError.invalid("BAD RECT \(words(args))") }
            return ["\(line) \(grid.query(row, column, bottom, right).text)"]
        }
        let kind = Kind(rawValue: command)!
        if action == "BUILD" {
            var operation = Operation.sum, block = 1
            if kind == .seg {
                guard let selected = Operation(rawValue: parts[2]) else { throw CommandError.invalid("BAD OP \(parts[2])") }
                operation = selected
            } else if kind == .sqrt {
                block = parts.count == 3 ? Int(parts[2])! : integerSqrt(values.count)
                if block > values.count { throw CommandError.invalid("BAD BLOCK \(block)") }
            }
            let state = create(kind, operation: operation, block: block)
            structures[kind] = state
            return [state.buildLine]
        }
        guard let state = structures[kind] else { throw CommandError.invalid("NOT BUILT \(command)") }
        if action == "DUMP" { return state.dump() }
        let args = parts.dropFirst(2).map { Int($0)! }
        switch state {
        case .seg(let tree) where action == "UPDATE":
            let index = args[0], value = args[1]
            try checkIndex(index)
            let visited = tree.update(index, value: value)
            values[index] = value
            return ["\(line) root=\(tree.root) visited=\(visited)"]
        case .fen(let tree) where action == "LOWER":
            if let index = tree.values.firstIndex(where: { $0 < 0 }) { throw CommandError.invalid("NEGATIVE \(index)") }
            let answer = tree.bit.lower(args[0])
            return ["\(line) index=\(answer.value < 0 ? "none" : String(answer.value)) visited=\(answer.visited)"]
        case .fen(let tree) where action == "ADD" || action == "PREFIX":
            let index = args[0]
            try checkIndex(index)
            if action == "PREFIX" { return ["\(line) \(tree.bit.prefix(index + 1).text)"] }
            let visited = tree.add(index, value: args[1])
            values[index] += args[1]
            return ["\(line) visited=\(visited)"]
        case .persist(let tree):
            if action == "NODES" { return [tree.nodeLine] }
            if action == "KTH" {
                let range = try checkedRange(args[0], args[1]), k = args[2]
                if k < 1 || k > range.length { throw CommandError.invalid("BAD K \(k)") }
                let answer = tree.kth(range, k: k)
                return ["\(line) value=\(answer.value) visited=\(answer.visited)"]
            }
            let version = args[0]
            try checkVersion(version, tree: tree)
            if action == "SET" {
                let index = args[1]
                try checkIndex(index)
                let next = tree.positions.roots.count, created = tree.positions.fork(version, index: index, value: args[2])
                return ["\(line) version=\(next) created=\(created)"]
            }
            let range = try checkedRange(args[1], args[2])
            return ["\(line) \(state.query(range, version: version).text)"]
        default: break
        }
        let range = try checkedRange(args[0], args[1])
        if action == "ADD" || action == "ASSIGN" {
            let value = args[2], assignment = action == "ASSIGN", detail: String
            switch state {
            case .lazy(let tree):
                let counts = tree.update(range, value: value, assignment: assignment)
                detail = "visited=\(counts.visited) covered=\(counts.covered) pushes=\(counts.pushes)"
            case .rfen(let tree): detail = "visited=\(tree.add(range, value: value))"
            case .sqrt(let tree): detail = tree.add(range, value: value).partition
            default: preconditionFailure("Invalid range update")
            }
            change(range, value: value, assignment: assignment)
            return ["\(line) \(detail)"]
        }
        return ["\(line) \(state.query(range).text)"]
    }
}

let initialSize = Int(readLine()!)!
let laboratory = Laboratory(readLine()!.split(separator: " ").map { Int($0)! })
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    let line = readLine()!
    do { for row in try laboratory.execute(line) { print(row) } }
    catch CommandError.invalid(let message) { print("ERROR \(message)") }
    catch { preconditionFailure("Unexpected error: \(error)") }
}
