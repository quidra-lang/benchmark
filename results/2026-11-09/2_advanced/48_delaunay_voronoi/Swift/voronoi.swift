import Foundation

func squaredRadius(_ a: Point, _ b: Point, _ c: Point) -> Double {
    let first = Double(d2(a, b)), second = Double(d2(b, c)), third = Double(d2(c, a)), area = Double(orient(a, b, c))
    return ((first * second) * third) / ((4 * area) * area)
}

func position(_ center: Center, _ points: [Point], _ hull: [Int]) -> String {
    var on = false
    for (index, u) in hull.enumerated() {
        let v = hull[(index + 1) % hull.count]
        let sigma = (points[v].x - points[u].x) * (center.y - points[u].y * center.denominator) - (points[v].y - points[u].y) * (center.x - points[u].x * center.denominator)
        if sigma < 0 { return "outside" }
        if sigma == 0 { on = true }
    }
    return on ? "on" : "inside"
}

func neighborOrder(_ site: Int, _ neighbors: Set<Int>, _ directed: [Edge: Int], _ hullNext: [Int: Int]) -> [Int] {
    let first = hullNext[site] ?? neighbors.min()!
    var order = [first]
    while order.count < neighbors.count { order.append(directed[Edge(site, order.last!)]!) }
    return order
}

func outward(_ points: [Point], _ u: Int, _ v: Int) -> Point { reduceDirection(points[v].y - points[u].y, -(points[v].x - points[u].x)) }

func boundedArea(_ site: Point, _ centers: [Center]) -> Double {
    let relative = centers.map { (Double($0.x) / Double($0.denominator) - Double(site.x), Double($0.y) / Double($0.denominator) - Double(site.y)) }
    var total = 0.0
    for index in relative.indices {
        let next = (index + 1) % relative.count
        total = total + (relative[index].0 * relative[next].1 - relative[next].0 * relative[index].1)
    }
    return total / 2
}

func clippedArea(_ points: [Point], _ site: Int, _ order: [Int]) -> Double {
    var polygon = [(0.0, 0.0), (1000.0, 0.0), (1000.0, 1000.0), (0.0, 1000.0)]
    let source = points[site]
    for neighbor in order {
        let target = points[neighbor]
        let c1 = Double(2 * (target.x - source.x)), c2 = Double(2 * (target.y - source.y))
        let c3 = Double(target.x * target.x + target.y * target.y - source.x * source.x - source.y * source.y)
        var clipped: [(Double, Double)] = []
        for (index, p) in polygon.enumerated() {
            let q = polygon[(index + 1) % polygon.count]
            let fp = c1 * p.0 + c2 * p.1 - c3, fq = c1 * q.0 + c2 * q.1 - c3
            if fp <= 0 { clipped.append(p) }
            if (fp < 0 && fq > 0) || (fq < 0 && fp > 0) {
                let fraction = fp / (fp - fq)
                clipped.append((p.0 + (q.0 - p.0) * fraction, p.1 + (q.1 - p.1) * fraction))
            }
        }
        polygon = clipped
    }
    var total = 0.0
    for (index, p) in polygon.enumerated() {
        let q = polygon[(index + 1) % polygon.count]
        total = total + (p.0 * q.1 - q.0 * p.1)
    }
    return total / 2
}
