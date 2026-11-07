import Foundation

let pointStructures = ["kdtree", "quadtree", "rtree", "str", "grid"]
let rectangleStructures = ["rtree_rect", "str_rect"]
let rtreeStructures = ["rtree", "str", "rtree_rect", "str_rect"]
let searchCommands = ["RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"]

enum NodeSource {
    case kd(KDNode), quad(QuadNode), rtree(RNode), cell(GridCell), grid(Grid)
}

final class NodeView {
    let region: Box
    let held: [SpatialObject]
    let children: [NodeView]
    let source: NodeSource
    let mark: String
    let depth: Int
    let count: Int

    init(_ region: Box, _ held: [SpatialObject], _ children: [NodeView], _ source: NodeSource, mark: String = "root", depth: Int = 0) {
        self.region = region; self.held = held; self.children = children; self.source = source; self.mark = mark; self.depth = depth
        count = held.count + children.reduce(0) { $0 + $1.count }
    }
}

func kdChildRegions(_ node: KDNode, _ region: Box) -> (Box, Box) {
    if node.axis == 0 {
        return (Box(x1: region.x1, y1: region.y1, x2: node.point.x, y2: region.y2), Box(x1: node.point.x, y1: region.y1, x2: region.x2, y2: region.y2))
    }
    return (Box(x1: region.x1, y1: region.y1, x2: region.x2, y2: node.point.y), Box(x1: region.x1, y1: node.point.y, x2: region.x2, y2: region.y2))
}

func kdView(_ root: KDNode, _ world: Int) -> NodeView {
    var views: [ObjectIdentifier: NodeView] = [:]
    var pending = [(node: root, region: Box(x1: 0, y1: 0, x2: world - 1, y2: world - 1), mark: "root", depth: 0, ready: false)]
    while let item = pending.popLast() {
        if item.ready {
            let children = [item.node.left, item.node.right].compactMap { $0 }.map { views[ObjectIdentifier($0)]! }
            views[ObjectIdentifier(item.node)] = NodeView(item.region, [SpatialObject(item.node.point)], children, .kd(item.node), mark: item.mark, depth: item.depth)
        } else {
            pending.append((item.node, item.region, item.mark, item.depth, true))
            let regions = kdChildRegions(item.node, item.region)
            if let right = item.node.right { pending.append((right, regions.1, "R", item.depth + 1, false)) }
            if let left = item.node.left { pending.append((left, regions.0, "L", item.depth + 1, false)) }
        }
    }
    return views[ObjectIdentifier(root)]!
}

func quadView(_ node: QuadNode, mark: String = "root", depth: Int = 0) -> NodeView {
    let region = Box(x1: node.x, y1: node.y, x2: node.x + node.size - 1, y2: node.y + node.size - 1)
    let children = node.children.enumerated().map { quadView($0.element, mark: quadChildNames[$0.offset], depth: depth + 1) }
    return NodeView(region, node.points.map(SpatialObject.init), children, .quad(node), mark: mark, depth: depth)
}

func rtreeView(_ node: RNode, _ objects: [Int: SpatialObject], depth: Int = 0) -> NodeView {
    let held = node.level == 0 ? node.entries.map { objects[$0.objectID!]! } : []
    let children = node.level > 0 ? node.entries.map { rtreeView($0.child!, objects, depth: depth + 1) } : []
    return NodeView(node.box, held, children, .rtree(node), depth: depth)
}

func gridView(_ grid: Grid) -> NodeView {
    let children = grid.cells.map { NodeView($0.box, $0.points.map(SpatialObject.init), [], .cell($0), depth: 1) }
    return NodeView(Box(x1: 0, y1: 0, x2: grid.world - 1, y2: grid.world - 1), [], children, .grid(grid))
}

func preorder(_ root: NodeView) -> [NodeView] {
    var pending = [root], result: [NodeView] = []
    while let node = pending.popLast() { result.append(node); pending.append(contentsOf: node.children.reversed()) }
    return result
}

typealias QueryPoint = (x: Int, y: Int)
func pointDistance(_ query: QueryPoint, _ point: Point) -> Int { let dx = point.x - query.x, dy = point.y - query.y; return dx * dx + dy * dy }
func minimumDistance(_ query: QueryPoint, _ box: Box) -> Int {
    let dx = query.x < box.x1 ? box.x1 - query.x : query.x > box.x2 ? query.x - box.x2 : 0
    let dy = query.y < box.y1 ? box.y1 - query.y : query.y > box.y2 ? query.y - box.y2 : 0
    return dx * dx + dy * dy
}
func objectDistance(_ query: QueryPoint, _ object: SpatialObject) -> Int { object.point.map { pointDistance(query, $0) } ?? minimumDistance(query, object.box) }
func boxValues(_ values: [Int]) -> Box { Box(x1: values[0], y1: values[1], x2: values[2], y2: values[3]) }

func searchConditions(_ command: String, _ values: [Int]) -> (region: (Box) -> Bool, object: (SpatialObject) -> Bool) {
    if command == "RANGE" { let box = boxValues(values); return ({ $0.intersects(box) }, { box.contains($0.box) }) }
    if command == "RADIUS" {
        let query: QueryPoint = (values[0], values[1]), limit = values[2] * values[2]
        return ({ minimumDistance(query, $0) <= limit }, { pointDistance(query, $0.point!) <= limit })
    }
    let query = Box(x1: values[0], y1: values[1], x2: values[0], y2: values[1])
    return ({ $0.contains(query) }, { $0.box.contains(query) })
}

struct JoinPair: Equatable, Comparable {
    let rectangle: Int
    let point: Int
    static func < (a: JoinPair, b: JoinPair) -> Bool { a.rectangle == b.rectangle ? a.point < b.point : a.rectangle < b.rectangle }
}

enum Answer: Equatable {
    case identifiers([Int]), count(Int), nearest([ObjectDistance]), pairs([JoinPair])
}

struct SearchResult {
    let answer: Answer
    let nodes: Int
    let tests: Int
}

func conditionSearch(_ root: NodeView, _ regionCondition: (Box) -> Bool, _ objectCondition: (SpatialObject) -> Bool) -> SearchResult {
    var answer: [Int] = [], nodes = 0, tests = 0, pending = [root]
    while let node = pending.popLast() {
        nodes += 1; tests += node.held.count
        answer += node.held.filter(objectCondition).map { $0.id }
        pending.append(contentsOf: node.children.filter { regionCondition($0.region) }.reversed())
    }
    return SearchResult(answer: .identifiers(answer.sorted()), nodes: nodes, tests: tests)
}

func windowCount(_ root: NodeView, _ window: Box) -> SearchResult {
    var answer = 0, nodes = 0, tests = 0, pending = [root]
    while let node = pending.popLast() {
        nodes += 1
        if window.contains(node.region) { answer += node.count; continue }
        tests += node.held.count
        answer += node.held.filter { window.contains($0.box) }.count
        pending.append(contentsOf: node.children.filter { $0.region.intersects(window) }.reversed())
    }
    return SearchResult(answer: .count(answer), nodes: nodes, tests: tests)
}

enum QueueElement { case node(NodeView), object(SpatialObject) }
struct QueueEntry {
    let distance: Int
    let kind: Int
    let tie: Int
    let element: QueueElement
    func precedes(_ other: QueueEntry) -> Bool { [distance, kind, tie].lexicographicallyPrecedes([other.distance, other.kind, other.tie]) }
}

struct PriorityQueue {
    var entries: [QueueEntry] = []
    mutating func push(_ entry: QueueEntry) {
        entries.append(entry)
        var index = entries.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            if !entries[index].precedes(entries[parent]) { break }
            entries.swapAt(index, parent); index = parent
        }
    }
    mutating func pop() -> QueueEntry? {
        if entries.isEmpty { return nil }
        if entries.count == 1 { return entries.removeLast() }
        let result = entries[0]
        let last = entries.removeLast()
        entries[0] = last
        var index = 0
        while 2 * index + 1 < entries.count {
            var child = 2 * index + 1
            if child + 1 < entries.count && entries[child + 1].precedes(entries[child]) { child += 1 }
            if !entries[child].precedes(entries[index]) { break }
            entries.swapAt(index, child); index = child
        }
        return result
    }
}

func bestFirst(_ root: NodeView, _ query: QueryPoint, _ count: Int) -> SearchResult {
    var pending = PriorityQueue(), serial = 1, nodes = 0, tests = 0, answer: [ObjectDistance] = []
    pending.push(QueueEntry(distance: minimumDistance(query, root.region), kind: 0, tie: 0, element: .node(root)))
    while let entry = pending.pop() {
        switch entry.element {
        case .object(let object):
            answer.append(ObjectDistance(id: object.id, distance: entry.distance))
            if answer.count == count { return SearchResult(answer: .nearest(answer), nodes: nodes, tests: tests) }
        case .node(let node):
            nodes += 1; tests += node.held.count
            for object in node.held { pending.push(QueueEntry(distance: objectDistance(query, object), kind: 1, tie: object.id, element: .object(object))) }
            for child in node.children { pending.push(QueueEntry(distance: minimumDistance(query, child.region), kind: 0, tie: serial, element: .node(child))); serial += 1 }
        }
    }
    return SearchResult(answer: .nearest(answer), nodes: nodes, tests: tests)
}

func spatialJoin(_ pointRoot: NodeView, _ rectangleRoot: NodeView) -> SearchResult {
    var answer: [JoinPair] = [], nodes = 0, tests = 0, pending = [(pointRoot, rectangleRoot)]
    while let (points, rectangles) = pending.popLast() {
        nodes += 1
        if points.children.isEmpty && rectangles.children.isEmpty {
            tests += points.held.count * rectangles.held.count
            for point in points.held { for rectangle in rectangles.held where rectangle.box.contains(point.box) { answer.append(JoinPair(rectangle: rectangle.id, point: point.id)) } }
        } else {
            let children: [(NodeView, NodeView)]
            if points.children.isEmpty { children = rectangles.children.filter { points.region.intersects($0.region) }.map { (points, $0) } }
            else if rectangles.children.isEmpty { children = points.children.filter { $0.region.intersects(rectangles.region) }.map { ($0, rectangles) } }
            else { children = points.children.flatMap { p in rectangles.children.filter { p.region.intersects($0.region) }.map { (p, $0) } } }
            pending.append(contentsOf: children.reversed())
        }
    }
    return SearchResult(answer: .pairs(answer.sorted()), nodes: nodes, tests: tests)
}

func bruteForce(_ command: String, _ values: [Int], _ points: [SpatialObject], _ rectangles: [SpatialObject]) -> Answer {
    if ["RANGE", "RADIUS", "CONTAINS"].contains(command) {
        let condition = searchConditions(command, values).object
        return .identifiers((command == "CONTAINS" ? rectangles : points).filter(condition).map { $0.id }.sorted())
    }
    if command == "WINDOWCOUNT" { let window = boxValues(values); return .count(points.filter { window.contains($0.box) }.count) }
    if command == "KNN" || command == "NEAREST" {
        let query: QueryPoint = (values[0], values[1]), objects = command == "NEAREST" ? rectangles : points
        let ordered = objects.map { ObjectDistance(id: $0.id, distance: objectDistance(query, $0)) }.sorted { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }
        return .nearest(Array(ordered.prefix(values[2])))
    }
    let pairs = rectangles.flatMap { rectangle in points.filter { rectangle.box.contains($0.box) }.map { JoinPair(rectangle: rectangle.id, point: $0.id) } }
    return .pairs(pairs.sorted())
}

func structuresFor(_ command: String) -> [String] { command == "JOIN" ? ["rtree", "str"] : ["CONTAINS", "NEAREST"].contains(command) ? rectangleStructures : pointStructures }

func locateKD(_ root: KDNode, _ point: Point) -> String {
    var path = "", node = root
    while node.point.id != point.id {
        if kdLess(point, node.point, node.axis) { path += "L"; node = node.left! } else { path += "R"; node = node.right! }
    }
    return path.isEmpty ? "-" : path
}

func locateQuad(_ root: QuadNode, _ point: Point) -> String {
    var path: [String] = [], node = root
    while !node.children.isEmpty { let destination = quadDestination(node, point); path.append(quadChildNames[destination]); node = node.children[destination] }
    return path.isEmpty ? "-" : path.joined(separator: "/")
}

func locateRTree(_ root: RNode, _ point: Point) -> String {
    var pending = [(root, [Int]())]
    while let (node, path) = pending.popLast() {
        if node.level == 0 {
            if let index = node.entries.firstIndex(where: { $0.objectID == point.id }) { return (path + [index + 1]).map(String.init).joined(separator: "/") }
        } else {
            let children = node.entries.enumerated().filter { $0.element.box.contains(point.box) }.map { ($0.element.child!, path + [$0.offset + 1]) }
            pending.append(contentsOf: children.reversed())
        }
    }
    preconditionFailure("Point is absent from its R-tree")
}

func dumpTree(_ root: NodeView) -> [String] {
    preorder(root).compactMap { view -> String? in
        let prefix = String(repeating: " ", count: 2 * (view.depth + 1))
        switch view.source {
        case .kd(let node): return "\(prefix)\(view.mark) \(node.axis == 0 ? "x" : "y") \(node.point.id) \(node.point.x) \(node.point.y) box \(view.region.words)"
        case .quad(let node):
            let content = view.children.isEmpty ? "leaf " + ids(view.held.map { $0.id }) : "node count \(view.count)"
            return "\(prefix)\(view.mark) \(node.x) \(node.y) \(node.size) \(content)"
        case .rtree(let node):
            return node.level == 0 ? "\(prefix)leaf \(view.region.words) ids \(ids(view.held.map { $0.id }))" : "\(prefix)node \(node.level) \(view.region.words) entries \(node.entries.count)"
        default: return nil
        }
    }
}

func kdStatistics(_ root: NodeView) -> [String] {
    let views = preorder(root), height = views.map { $0.depth }.max()! + 1
    var depths = Array(repeating: [0, 0, 0], count: height), depthSum = 0
    for view in views {
        depths[view.depth][0] += 1
        if view.children.isEmpty { depths[view.depth][1] += 1 } else if view.children.count == 1 { depths[view.depth][2] += 1 }
        depthSum += view.depth
    }
    let nodes = views.count, leaves = depths.reduce(0) { $0 + $1[1] }, oneChild = depths.reduce(0) { $0 + $1[2] }
    var ideal = 0
    while (1 << ideal) - 1 < nodes { ideal += 1 }
    return ["kdtree height \(height) ideal \(ideal) nodes \(nodes) leaves \(leaves) one_child \(oneChild) depth_sum \(depthSum) avg_depth \(fraction(depthSum, nodes))"] + depths.enumerated().map {
        "  depth \($0.offset) nodes \($0.element[0]) leaves \($0.element[1]) one_child \($0.element[2])"
    }
}

func quadStatistics(_ root: NodeView, _ capacity: Int) -> [String] {
    let views = preorder(root), height = views.map { $0.depth }.max()! + 1
    var depths = Array(repeating: [0, 0, 0], count: height), empty = 0, maximum = 0
    for view in views {
        if view.children.isEmpty {
            depths[view.depth][1] += 1; depths[view.depth][2] += view.held.count
            if view.held.isEmpty { empty += 1 }
            maximum = max(maximum, view.held.count)
        } else { depths[view.depth][0] += 1 }
    }
    let internalCount = depths.reduce(0) { $0 + $1[0] }, leaves = depths.reduce(0) { $0 + $1[1] }
    return ["quadtree height \(height) internal \(internalCount) leaves \(leaves) empty \(empty) max_leaf \(maximum) fill \(fraction(root.count, leaves * capacity))"] + depths.enumerated().map {
        "  depth \($0.offset) internal \($0.element[0]) leaves \($0.element[1]) points \($0.element[2])"
    }
}

func rtreeStatistics(_ name: String, _ root: NodeView, _ maximum: Int, _ minimum: Int) -> [String] {
    var levels: [Int: [NodeView]] = [:], entries = 0
    for view in preorder(root) {
        if case .rtree(let node) = view.source { levels[node.level, default: []].append(view); entries += node.entries.count }
    }
    let height = levels.keys.max()! + 1, nodes = levels.values.reduce(0) { $0 + $1.count }, leaves = levels[0]!.count
    var lines = ["\(name) height \(height) nodes \(nodes) leaves \(leaves) entries \(entries) fill \(fraction(entries, nodes * maximum))"]
    for level in (0..<height).reversed() {
        let group = levels[level]!
        let sizes = group.map { view -> Int in if case .rtree(let node) = view.source { return node.entries.count }; preconditionFailure() }
        let area = group.reduce(0) { $0 + $1.region.area }
        var overlap = 0
        if group.count >= 2 { for first in 0..<(group.count - 1) { for second in (first + 1)..<group.count { overlap += group[first].region.overlap(group[second].region) } } }
        lines.append("  level \(level) nodes \(group.count) entries \(sizes.reduce(0, +)) min \(sizes.min()!) max \(sizes.max()!) under \(sizes.filter { $0 < minimum }.count) area \(area) overlap \(overlap)")
    }
    return lines
}

func gridStatistics(_ root: NodeView) -> [String] {
    let occupancy = Dictionary(grouping: root.children.map { $0.held.count }, by: { $0 }).mapValues { $0.count }
    let cells = root.children.count, used = cells - (occupancy[0] ?? 0)
    let sequence = occupancy.keys.sorted().map { "\($0):\(occupancy[$0]!)" }.joined(separator: " ")
    return ["grid cells \(cells) used \(used) max \(occupancy.keys.max()!)", "  occupancy \(sequence)"]
}

struct VisitTotal {
    var queries = 0
    var nodes = 0
    var tests = 0
    var maximum = 0
}

func visitsSummary(_ totals: [String: [String: VisitTotal]]) -> [String] {
    var lines = ["visits"]
    for command in searchCommands {
        guard let commandTotals = totals[command] else { continue }
        let structures = structuresFor(command)
        for name in structures {
            let total = commandTotals[name]!
            lines.append("\(command) \(name) queries \(total.queries) nodes \(total.nodes) tests \(total.tests) max_nodes \(total.maximum) mean_nodes \(fraction(total.nodes, total.queries))")
        }
        let ranking = structures.enumerated().sorted {
            let a = commandTotals[$0.element]!, b = commandTotals[$1.element]!
            return [a.nodes, a.tests, $0.offset].lexicographicallyPrecedes([b.nodes, b.tests, $1.offset])
        }.map { $0.element }
        lines.append("rank \(command) " + ranking.joined(separator: " "))
    }
    return lines
}

final class Laboratory {
    var points: [Int: Point]
    let rectangles: [Int: SpatialObject]
    let params: Parameters
    var kdRoot: KDNode?
    let quadRoot: QuadNode
    let grid: Grid
    var rtrees: [String: RTree] = [:]
    var views: [String: NodeView] = [:]
    var answers: [String] = []
    var visits = ["query,command,structure,nodes,tests"]
    var joinRows = ["query,rect,point"]
    var structures: [String] = []
    var statistics: [String] = []
    var visitTotals: [String: [String: VisitTotal]] = [:]
    var snapshotNumber = 0

    init(_ dataset: Dataset) {
        let params = dataset.params
        points = Dictionary(uniqueKeysWithValues: dataset.points.map { ($0.id, $0) })
        rectangles = Dictionary(uniqueKeysWithValues: dataset.rectangles.map { ($0.id, $0) })
        self.params = params
        kdRoot = buildKD(dataset.points)
        quadRoot = buildQuad(dataset.points, params.world, params.bucket)
        grid = Grid(params.world, params.cellSize, dataset.points)
        for name in rtreeStructures {
            let objects = rectangleStructures.contains(name) ? dataset.rectangles : dataset.points.map(SpatialObject.init)
            let entries = objects.map { REntry($0.box, id: $0.id) }
            rtrees[name] = RTree(entries, params.maximum, params.minimum, bulk: name == "str" || name == "str_rect")
        }
        refreshPointViews()
        for name in rectangleStructures { views[name] = rtreeView(rtrees[name]!.root, rectangles) }
        recordSnapshot(0)
    }

    func refreshPointViews() {
        views["kdtree"] = kdView(kdRoot!, params.world)
        views["quadtree"] = quadView(quadRoot)
        let objects = points.mapValues(SpatialObject.init)
        for name in ["rtree", "str"] { views[name] = rtreeView(rtrees[name]!.root, objects) }
        views["grid"] = gridView(grid)
    }

    func recordSnapshot(_ query: Int) {
        let header = "snapshot \(snapshotNumber) query \(query) points \(points.count) rects \(rectangles.count)"
        if !structures.isEmpty { structures.append(""); statistics.append("") }
        structures += [header, "kdtree"] + dumpTree(views["kdtree"]!) + ["quadtree"] + dumpTree(views["quadtree"]!)
        statistics += [header] + kdStatistics(views["kdtree"]!) + quadStatistics(views["quadtree"]!, params.bucket)
        for name in rtreeStructures {
            structures += [name] + dumpTree(views[name]!)
            statistics += rtreeStatistics(name, views[name]!, params.maximum, params.minimum)
        }
        statistics += gridStatistics(views["grid"]!)
    }

    func searchStructure(_ name: String, _ command: Command) -> SearchResult {
        let root = views[name]!
        if ["RANGE", "RADIUS", "CONTAINS"].contains(command.name) { let conditions = searchConditions(command.name, command.values); return conditionSearch(root, conditions.region, conditions.object) }
        if command.name == "WINDOWCOUNT" { return windowCount(root, boxValues(command.values)) }
        if command.name == "JOIN" { return spatialJoin(root, views[name + "_rect"]!) }
        return bestFirst(root, (command.values[0], command.values[1]), command.values[2])
    }

    func recordVisit(_ query: Int, _ command: String, _ name: String, _ result: SearchResult) {
        visits.append("\(query),\(command),\(name),\(result.nodes),\(result.tests)")
        var total = visitTotals[command]?[name] ?? VisitTotal()
        total.queries += 1; total.nodes += result.nodes; total.tests += result.tests; total.maximum = max(total.maximum, result.nodes)
        visitTotals[command, default: [:]][name] = total
    }

    func processSearch(_ query: Int, _ command: Command) {
        let expected = bruteForce(command.name, command.values, points.values.map(SpatialObject.init), Array(rectangles.values))
        var mismatches: [String] = []
        for name in structuresFor(command.name) {
            let actual = searchStructure(name, command)
            recordVisit(query, command.name, name, actual)
            if actual.answer != expected { mismatches.append(name) }
        }
        let check = mismatches.isEmpty ? "ok" : "mismatch " + mismatches.joined(separator: " ")
        let prefix = "\(query) \(command.name) count"
        switch expected {
        case .count(let count): answers.append("\(prefix) \(count) check \(check)")
        case .pairs(let pairs):
            answers.append("\(prefix) \(pairs.count) check \(check)")
            joinRows += pairs.map { "\(query),\($0.rectangle),\($0.point)" }
        case .identifiers(let values): answers.append("\(prefix) \(values.count) ids \(ids(values)) check \(check)")
        case .nearest(let values): answers.append("\(prefix) \(values.count) ids \(distances(values)) check \(check)")
        }
    }

    func processLocate(_ query: Int, _ identifier: Int) {
        guard let point = points[identifier] else { answers.append("\(query) LOCATE \(identifier) missing"); return }
        let kd = locateKD(kdRoot!, point), quad = locateQuad(quadRoot, point), rtree = locateRTree(rtrees["rtree"]!.root, point), str = locateRTree(rtrees["str"]!.root, point)
        let cell = grid.position(point)
        answers.append("\(query) LOCATE \(identifier) kdtree \(kd) quadtree \(quad) rtree \(rtree) str \(str) grid \(cell.column) \(cell.row)")
    }

    func processInsert(_ query: Int, _ point: Point) {
        points[point.id] = point
        kdRoot = insertKD(kdRoot, point)
        insertQuad(quadRoot, point, params.bucket)
        for name in ["rtree", "str"] { rtrees[name]!.insert(REntry(point.box, id: point.id)) }
        grid.insert(point)
        refreshPointViews()
        answers.append("\(query) INSERT \(point.id) inserted points \(points.count)")
    }

    func processDelete(_ query: Int, _ identifier: Int) {
        var status = "missing"
        if let point = points[identifier] {
            kdRoot = deleteKD(kdRoot, point)
            deleteQuad(quadRoot, point, params.bucket)
            for name in ["rtree", "str"] { rtrees[name]!.delete(point) }
            grid.delete(point)
            points.removeValue(forKey: identifier)
            refreshPointViews()
            status = "deleted"
        }
        answers.append("\(query) DELETE \(identifier) \(status) points \(points.count)")
    }

    func process(_ commands: [Command]) {
        for (index, command) in commands.enumerated() {
            let query = index + 1
            if searchCommands.contains(command.name) { processSearch(query, command) }
            else if command.name == "LOCATE" { processLocate(query, command.values[0]) }
            else if command.name == "INSERT" { processInsert(query, Point(id: command.values[0], x: command.values[1], y: command.values[2])) }
            else if command.name == "DELETE" { processDelete(query, command.values[0]) }
            else { snapshotNumber += 1; recordSnapshot(query); answers.append("\(query) DUMP snapshot \(snapshotNumber)") }
        }
    }

    func writeOutputs() throws {
        try writeLines("answers.txt", answers)
        try writeLines("visits.csv", visits)
        try writeLines("join.csv", joinRows)
        try writeLines("structures.txt", structures)
        try writeLines("stats.txt", statistics + [""] + visitsSummary(visitTotals))
    }
}

let dataset = try readDataset()
let laboratory = Laboratory(dataset)
laboratory.process(dataset.commands)
try laboratory.writeOutputs()
