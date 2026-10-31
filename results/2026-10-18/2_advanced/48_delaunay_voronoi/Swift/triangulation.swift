import Foundation

struct Edge: Hashable, Comparable {
    let first: Int
    let second: Int
    init(_ first: Int, _ second: Int) { self.first = first; self.second = second }
    var reversed: Edge { Edge(second, first) }
    var undirected: Edge { first < second ? self : reversed }
    static func < (a: Edge, b: Edge) -> Bool { a.first == b.first ? a.second < b.second : a.first < b.first }
}

struct Triangle: Hashable, Comparable {
    let a: Int
    let b: Int
    let c: Int
    var sites: [Int] { [a, b, c] }
    var edges: [Edge] { [Edge(a, b), Edge(b, c), Edge(c, a)] }
    init(_ a: Int, _ b: Int, _ c: Int) {
        if a <= b && a <= c { self.a = a; self.b = b; self.c = c }
        else if b <= a && b <= c { self.a = b; self.b = c; self.c = a }
        else { self.a = c; self.b = a; self.c = b }
    }
    static func < (a: Triangle, b: Triangle) -> Bool { a.a != b.a ? a.a < b.a : a.b != b.b ? a.b < b.b : a.c < b.c }
}

struct Insertion {
    let site: Int
    let containing: Triangle?
    let visible: Int
    let flips: Int
    let triangles: Int
    let hull: Int
}

final class Triangulation {
    let points: [Point]
    var directed: [Edge: Int] = [:]
    let initial: Triangle

    init(_ points: [Point]) {
        self.points = points
        initial = orient(points[1], points[2], points[3]) > 0 ? Triangle(1, 2, 3) : Triangle(1, 3, 2)
        add(initial.a, initial.b, initial.c)
    }

    func add(_ a: Int, _ b: Int, _ c: Int) { directed[Edge(a, b)] = c; directed[Edge(b, c)] = a; directed[Edge(c, a)] = b }
    func remove(_ a: Int, _ b: Int, _ c: Int) { directed.removeValue(forKey: Edge(a, b)); directed.removeValue(forKey: Edge(b, c)); directed.removeValue(forKey: Edge(c, a)) }
    func triangles() -> [Triangle] { Set(directed.map { Triangle($0.key.first, $0.key.second, $0.value) }).sorted() }
    func hullEdges() -> [Edge] { directed.keys.filter { directed[$0.reversed] == nil }.sorted() }

    func insert(_ site: Int) -> Insertion {
        let containing = triangles().first { triangle in triangle.edges.allSatisfy { orient(points[$0.first], points[$0.second], points[site]) > 0 } }
        var check = Set<Edge>(), visible = 0
        if let triangle = containing {
            remove(triangle.a, triangle.b, triangle.c)
            check = Set(triangle.edges)
        } else {
            check = Set(hullEdges().filter { orient(points[$0.first], points[$0.second], points[site]) < 0 }.map { $0.reversed })
            visible = check.count
        }
        for edge in check.sorted() { add(edge.first, edge.second, site) }
        var flips = 0
        while let edge = check.min() {
            check.remove(edge)
            let a = edge.first, b = edge.second
            if let q = directed[edge.reversed], incircle(points[a], points[b], points[site], points[q]) > 0 {
                remove(a, b, site)
                remove(b, a, q)
                add(a, q, site)
                add(q, b, site)
                check.insert(Edge(a, q)); check.insert(Edge(q, b))
                flips += 1
            }
        }
        return Insertion(site: site, containing: containing, visible: visible, flips: flips, triangles: directed.count / 3, hull: hullEdges().count)
    }

    func visibilityWalk(_ query: Point, _ triangles: [Triangle], _ edgeTriangles: [Edge: Int]) -> (path: [Int], outside: Edge?) {
        var path = [1]
        while true {
            guard let crossing = triangles[path.last!].edges.first(where: { orient(points[$0.first], points[$0.second], query) < 0 }) else { return (path, nil) }
            guard let following = edgeTriangles[crossing.reversed] else { return (path, crossing.undirected) }
            path.append(following)
        }
    }
}
