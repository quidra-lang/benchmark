import Foundation

final class DisjointSets {
    var parent: [Int]
    var size: [Int]
    var count: Int
    init(_ size: Int) { parent = Array(0...size); self.size = Array(repeating: 1, count: size + 1); count = size }
    func find(_ site: Int) -> Int {
        var site = site
        while parent[site] != site { parent[site] = parent[parent[site]]; site = parent[site] }
        return site
    }
    @discardableResult func union(_ first: Int, _ second: Int) -> Bool {
        var a = find(first), b = find(second)
        if a == b { return false }
        if size[a] < size[b] { swap(&a, &b) }
        parent[b] = a; size[a] += size[b]; count -= 1
        return true
    }
}

func nearestNeighbors(_ points: [Point], _ neighbors: [[Int]]) -> [Int] {
    [0] + (1..<points.count).map { site in neighbors[site].min { d2(points[site], points[$0]) == d2(points[site], points[$1]) ? $0 < $1 : d2(points[site], points[$0]) < d2(points[site], points[$1]) }! }
}

func nearestComponents(_ nearest: [Int]) -> [[Int]] {
    let sets = DisjointSets(nearest.count - 1)
    for site in 1..<nearest.count { sets.union(site, nearest[site]) }
    var groups: [Int: [Int]] = [:]
    for site in 1..<nearest.count { groups[sets.find(site), default: []].append(site) }
    return groups.values.sorted { $0[0] < $1[0] }
}

func kruskal(_ points: [Point], _ edges: [Edge]) -> [Edge] {
    let sets = DisjointSets(points.count - 1)
    let ordered = edges.sorted { let a = d2(points[$0.first], points[$0.second]), b = d2(points[$1.first], points[$1.second]); return a == b ? $0 < $1 : a < b }
    var adopted: [Edge] = []
    for edge in ordered where sets.union(edge.first, edge.second) { adopted.append(edge); if sets.count == 1 { break } }
    return adopted
}

func isGabriel(_ points: [Point], _ edge: Edge, _ directed: [Edge: Int]) -> Bool {
    for direction in [edge, edge.reversed] {
        if let opposite = directed[direction], dot(points[opposite], points[edge.first], points[edge.second]) <= 0 { return false }
    }
    return true
}

func isRelativeNeighbor(_ points: [Point], _ edge: Edge) -> Bool {
    let length = d2(points[edge.first], points[edge.second])
    return !points.dropFirst().contains { d2(points[edge.first], $0) < length && d2(points[edge.second], $0) < length }
}

func greedyRoute(_ points: [Point], _ neighbors: [[Int]], _ start: Int, _ target: Int) -> (path: [Int], length: Double) {
    var path = [start], length = 0.0, current = start
    while current != target {
        let following = neighbors[current].min { d2(points[$0], points[target]) == d2(points[$1], points[target]) ? $0 < $1 : d2(points[$0], points[target]) < d2(points[$1], points[target]) }!
        length = length + sqrt(Double(d2(points[current], points[following])))
        path.append(following)
        current = following
    }
    return (path, length)
}

struct ShortestPaths {
    let distances: [Double]
    let previous: [Int]
}

func dijkstra(_ points: [Point], _ neighbors: [[Int]], _ start: Int) -> ShortestPaths {
    var distances = Array(repeating: Double.infinity, count: points.count), previous = Array(repeating: 0, count: points.count)
    var visited = Array(repeating: false, count: points.count)
    distances[start] = 0
    for _ in 1..<points.count {
        var site = 0
        for candidate in 1..<points.count where !visited[candidate] {
            if site == 0 || distances[candidate] < distances[site] { site = candidate }
        }
        visited[site] = true
        for other in neighbors[site] {
            let candidate = distances[site] + sqrt(Double(d2(points[site], points[other])))
            if candidate < distances[other] { distances[other] = candidate; previous[other] = site }
        }
    }
    return ShortestPaths(distances: distances, previous: previous)
}
