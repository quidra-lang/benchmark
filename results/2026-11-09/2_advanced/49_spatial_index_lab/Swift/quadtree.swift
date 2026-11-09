import Foundation

let quadChildNames = ["NW", "NE", "SW", "SE"]

final class QuadNode {
    let x: Int
    let y: Int
    let size: Int
    var points: [Point] = []
    var children: [QuadNode] = []
    init(_ x: Int, _ y: Int, _ size: Int) { self.x = x; self.y = y; self.size = size }
}

func quadDestination(_ node: QuadNode, _ point: Point) -> Int {
    (point.x >= node.x + node.size / 2 ? 1 : 0) + (point.y >= node.y + node.size / 2 ? 2 : 0)
}

func insertQuad(_ root: QuadNode, _ point: Point, _ capacity: Int) {
    var node = root
    while !node.children.isEmpty { node = node.children[quadDestination(node, point)] }
    node.points.append(point)
    node.points.sort { $0.id < $1.id }
    if node.points.count > capacity {
        let half = node.size / 2
        node.children = [QuadNode(node.x, node.y, half), QuadNode(node.x + half, node.y, half), QuadNode(node.x, node.y + half, half), QuadNode(node.x + half, node.y + half, half)]
        let previous = node.points
        node.points = []
        for point in previous { insertQuad(node, point, capacity) }
    }
}

func deleteQuad(_ root: QuadNode, _ point: Point, _ capacity: Int) {
    var ancestors: [QuadNode] = [], node = root
    while !node.children.isEmpty { ancestors.append(node); node = node.children[quadDestination(node, point)] }
    node.points.removeAll { $0.id == point.id }
    for node in ancestors.reversed() {
        if node.children.contains(where: { !$0.children.isEmpty }) { break }
        let points = node.children.flatMap { $0.points }
        if points.count > capacity { break }
        node.points = points.sorted { $0.id < $1.id }
        node.children = []
    }
}

func buildQuad(_ points: [Point], _ world: Int, _ capacity: Int) -> QuadNode {
    let root = QuadNode(0, 0, world)
    for point in points { insertQuad(root, point, capacity) }
    return root
}
