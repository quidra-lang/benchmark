import Foundation

func squaredDistance(_ a: Vector2, _ b: Vector2) -> Double { let dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy }
func distance(_ a: Vector2, _ b: Vector2) -> Double { sqrt(squaredDistance(a, b)) }
struct KMeansResult { let centers: [Vector2]; let assignment: [Int]; let iterations: Int; let inertia: Double; let sizes: [Int] }
func assignNearest(_ points: [Observation], _ centers: [Vector2]) -> [Int] {
    points.map { point in
        var best = 0
        for k in centers.indices.dropFirst() { if squaredDistance(point.position, centers[k]) < squaredDistance(point.position, centers[best]) { best = k } }
        return best
    }
}
func runKMeans(_ points: [Observation], _ initial: [Vector2], _ limit: Int) -> KMeansResult {
    var centers = initial, assigned = assignNearest(points, initial), iterations = 0
    for t in 1...limit {
        var updated: [Vector2] = []
        for k in centers.indices {
            var x = 0.0, y = 0.0, size = 0
            for (i, point) in points.enumerated() where assigned[i] == k { x += point.position.x; y += point.position.y; size += 1 }
            updated.append(size > 0 ? Vector2(x: x / Double(size), y: y / Double(size)) : centers[k])
        }
        centers = updated
        let next = assignNearest(points, centers)
        iterations = t
        if next == assigned { assigned = next; break }
        assigned = next
    }
    var inertia = 0.0
    for (i, point) in points.enumerated() { inertia += squaredDistance(point.position, centers[assigned[i]]) }
    return KMeansResult(centers: centers, assignment: assigned, iterations: iterations, inertia: inertia, sizes: centers.indices.map { k in assigned.filter { $0 == k }.count })
}
