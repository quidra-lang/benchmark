import Foundation

final class KDNode {
    var point: Point
    let axis: Int
    var left: KDNode?
    var right: KDNode?
    init(_ point: Point, _ axis: Int, _ left: KDNode? = nil, _ right: KDNode? = nil) { self.point = point; self.axis = axis; self.left = left; self.right = right }
}

func kdKey(_ point: Point, _ axis: Int) -> [Int] { axis == 0 ? [point.x, point.y, point.id] : [point.y, point.x, point.id] }
func kdLess(_ first: Point, _ second: Point, _ axis: Int) -> Bool { kdKey(first, axis).lexicographicallyPrecedes(kdKey(second, axis)) }

func buildKD(_ points: [Point], depth: Int = 0) -> KDNode? {
    if points.isEmpty { return nil }
    let axis = depth % 2, ordered = points.sorted { kdLess($0, $1, depth % 2) }, middle = points.count / 2
    return KDNode(ordered[middle], axis, buildKD(Array(ordered[..<middle]), depth: depth + 1), buildKD(Array(ordered[(middle + 1)...]), depth: depth + 1))
}

func insertKD(_ root: KDNode?, _ point: Point) -> KDNode {
    guard let root else { return KDNode(point, 0) }
    var node = root
    while true {
        if kdLess(point, node.point, node.axis) {
            if let child = node.left { node = child } else { node.left = KDNode(point, 1 - node.axis); break }
        } else {
            if let child = node.right { node = child } else { node.right = KDNode(point, 1 - node.axis); break }
        }
    }
    return root
}

func minimumKD(_ root: KDNode, _ axis: Int) -> Point {
    var best: Point?, pending = [root]
    while let node = pending.popLast() {
        if node.axis == axis, let left = node.left { pending.append(left); continue }
        if best == nil || kdLess(node.point, best!, axis) { best = node.point }
        if node.axis != axis { if let right = node.right { pending.append(right) }; if let left = node.left { pending.append(left) } }
    }
    return best!
}

func deleteKD(_ root: KDNode?, _ point: Point) -> KDNode? {
    var parent: KDNode?, node = root, point = point, leftSide = false
    while let current = node {
        if current.point.id != point.id {
            parent = current
            leftSide = kdLess(point, current.point, current.axis)
            node = leftSide ? current.left : current.right
        } else if let right = current.right {
            point = minimumKD(right, current.axis)
            current.point = point
            parent = current; leftSide = false; node = right
        } else if let left = current.left {
            point = minimumKD(left, current.axis)
            current.point = point
            current.right = left; current.left = nil
            parent = current; leftSide = false; node = left
        } else {
            guard let parent else { return nil }
            if leftSide { parent.left = nil } else { parent.right = nil }
            return root
        }
    }
    return root
}
