import Foundation

struct Box: Equatable {
    let x1: Int
    let y1: Int
    let x2: Int
    let y2: Int
    var area: Int { (x2 - x1) * (y2 - y1) }
    var words: String { "\(x1) \(y1) \(x2) \(y2)" }
    func union(_ other: Box) -> Box { Box(x1: min(x1, other.x1), y1: min(y1, other.y1), x2: max(x2, other.x2), y2: max(y2, other.y2)) }
    func enlargement(_ other: Box) -> Int { union(other).area - area }
    func contains(_ other: Box) -> Bool { x1 <= other.x1 && other.x2 <= x2 && y1 <= other.y1 && other.y2 <= y2 }
    func intersects(_ other: Box) -> Bool { x1 <= other.x2 && other.x1 <= x2 && y1 <= other.y2 && other.y1 <= y2 }
    func overlap(_ other: Box) -> Int {
        let width = min(x2, other.x2) - max(x1, other.x1), height = min(y2, other.y2) - max(y1, other.y1)
        return width > 0 && height > 0 ? width * height : 0
    }
}

final class REntry {
    var box: Box
    let objectID: Int?
    let child: RNode?
    init(_ box: Box, id: Int? = nil, child: RNode? = nil) { self.box = box; objectID = id; self.child = child }
}

final class RNode {
    let level: Int
    var entries: [REntry]
    weak var parent: RNode?
    var box: Box { entries.dropFirst().reduce(entries[0].box) { $0.union($1.box) } }
    init(_ level: Int, _ entries: [REntry] = [], parent: RNode? = nil) { self.level = level; self.entries = entries; self.parent = parent; adoptChildren() }
    func adoptChildren() { if level > 0 { for entry in entries { entry.child!.parent = self } } }
}

final class RTree {
    let maximum: Int
    let minimum: Int
    var root: RNode

    init(_ entries: [REntry], _ maximum: Int, _ minimum: Int, bulk: Bool = false) {
        self.maximum = maximum; self.minimum = minimum; root = RNode(0)
        if bulk { root = strRoot(entries, maximum) } else { for entry in entries { insert(entry) } }
    }

    func chooseSubtree(_ box: Box, _ level: Int) -> RNode {
        var node = root
        while node.level > level {
            var best = 0
            for index in node.entries.indices.dropFirst() {
                let candidate = node.entries[index].box, previous = node.entries[best].box
                if [candidate.enlargement(box), candidate.area].lexicographicallyPrecedes([previous.enlargement(box), previous.area]) { best = index }
            }
            node = node.entries[best].child!
        }
        return node
    }

    func split(_ node: RNode) -> RNode {
        let entries = node.entries
        var seeds = (0, 1), bestWaste = Int.min
        for first in 0..<(entries.count - 1) {
            for second in (first + 1)..<entries.count {
                let a = entries[first].box, b = entries[second].box, waste = a.union(b).area - a.area - b.area
                if waste > bestWaste { bestWaste = waste; seeds = (first, second) }
            }
        }
        var group1 = [entries[seeds.0]], group2 = [entries[seeds.1]]
        var box1 = entries[seeds.0].box, box2 = entries[seeds.1].box
        var rest = entries.indices.filter { $0 != seeds.0 && $0 != seeds.1 }.map { entries[$0] }
        while !rest.isEmpty {
            if group1.count + rest.count == minimum { group1 += rest; break }
            if group2.count + rest.count == minimum { group2 += rest; break }
            var selected = 0, greatestDifference = -1, selectedD1 = 0, selectedD2 = 0
            for (index, entry) in rest.enumerated() {
                let d1 = box1.enlargement(entry.box), d2 = box2.enlargement(entry.box), difference = abs(d1 - d2)
                if difference > greatestDifference { selected = index; greatestDifference = difference; selectedD1 = d1; selectedD2 = d2 }
            }
            let entry = rest.remove(at: selected)
            if [selectedD1, box1.area, group1.count, 0].lexicographicallyPrecedes([selectedD2, box2.area, group2.count, 1]) {
                group1.append(entry); box1 = box1.union(entry.box)
            } else { group2.append(entry); box2 = box2.union(entry.box) }
        }
        node.entries = group1
        node.adoptChildren()
        return RNode(node.level, group2, parent: node.parent)
    }

    func insert(_ entry: REntry, level: Int = 0) {
        var node = chooseSubtree(entry.box, level)
        node.entries.append(entry)
        if level > 0 { entry.child!.parent = node }
        while true {
            let sibling = node.entries.count > maximum ? split(node) : nil
            guard let parent = node.parent else {
                if let sibling { root = RNode(node.level + 1, [REntry(node.box, child: node), REntry(sibling.box, child: sibling)]) }
                return
            }
            parent.entries.first { $0.child === node }!.box = node.box
            if let sibling { parent.entries.append(REntry(sibling.box, child: sibling)); sibling.parent = parent }
            node = parent
        }
    }

    func findLeaf(_ identifier: Int, _ box: Box) -> (node: RNode, index: Int)? {
        var pending = [root]
        while let node = pending.popLast() {
            if node.level == 0 {
                if let index = node.entries.firstIndex(where: { $0.objectID == identifier }) { return (node, index) }
            } else { for entry in node.entries.reversed() where entry.box.contains(box) { pending.append(entry.child!) } }
        }
        return nil
    }

    func delete(_ point: Point) {
        let found = findLeaf(point.id, point.box)!
        var node = found.node
        node.entries.remove(at: found.index)
        var removed: [RNode] = []
        while node !== root {
            let parent = node.parent!, index = node.parent!.entries.firstIndex { $0.child === node }!
            if node.entries.count < minimum {
                parent.entries.remove(at: index); removed.append(node); node.parent = nil
            } else { parent.entries[index].box = node.box }
            node = parent
        }
        for node in removed { for entry in node.entries { insert(entry, level: node.level) } }
        while root.level > 0 && root.entries.count == 1 { root = root.entries[0].child!; root.parent = nil }
    }
}

func strRoot(_ entries: [REntry], _ maximum: Int) -> RNode {
    var numbered = entries.map { (number: $0.objectID!, entry: $0) }, level = 0
    while true {
        let pages = (numbered.count + maximum - 1) / maximum
        var slabs = 1
        while slabs * slabs < pages { slabs += 1 }
        numbered.sort {
            [$0.entry.box.x1 + $0.entry.box.x2, $0.entry.box.y1 + $0.entry.box.y2, $0.number].lexicographicallyPrecedes([$1.entry.box.x1 + $1.entry.box.x2, $1.entry.box.y1 + $1.entry.box.y2, $1.number])
        }
        var nodes: [RNode] = []
        let slabSize = slabs * maximum
        for start in stride(from: 0, to: numbered.count, by: slabSize) {
            var slab = Array(numbered[start..<min(start + slabSize, numbered.count)])
            slab.sort {
                [$0.entry.box.y1 + $0.entry.box.y2, $0.entry.box.x1 + $0.entry.box.x2, $0.number].lexicographicallyPrecedes([$1.entry.box.y1 + $1.entry.box.y2, $1.entry.box.x1 + $1.entry.box.x2, $1.number])
            }
            for offset in stride(from: 0, to: slab.count, by: maximum) { nodes.append(RNode(level, slab[offset..<min(offset + maximum, slab.count)].map { $0.entry })) }
        }
        if nodes.count == 1 { return nodes[0] }
        numbered = nodes.enumerated().map { (number: $0.offset, entry: REntry($0.element.box, child: $0.element)) }
        level += 1
    }
}
