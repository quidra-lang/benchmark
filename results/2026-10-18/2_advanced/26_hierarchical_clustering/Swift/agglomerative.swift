import Foundation

enum Linkage: String {
    case single, complete, average, weighted, centroid, median, ward
    var squared: Bool { self == .centroid || self == .median || self == .ward }
}

struct Merge {
    let a: Int
    let b: Int
    let height: Double
    let size: Int
}
struct Edge {
    let parent: Int
    let child: Int
    let weight: Double
}

func lanceWilliams(_ method: Linkage, _ sizeA: Int, _ sizeB: Int, _ sizeK: Int) -> (Double, Double, Double, Double) {
    let a = Double(sizeA), b = Double(sizeB), k = Double(sizeK)
    switch method {
    case .single: return (0.5, 0.5, 0.0, -0.5)
    case .complete: return (0.5, 0.5, 0.0, 0.5)
    case .average: return (a / (a + b), b / (a + b), 0.0, 0.0)
    case .weighted: return (0.5, 0.5, 0.0, 0.0)
    case .centroid: return (a / (a + b), b / (a + b), -(a * b) / ((a + b) * (a + b)), 0.0)
    case .median: return (0.5, 0.5, -0.25, 0.0)
    case .ward:
        let total = a + b + k
        return ((a + k) / total, (b + k) / total, -k / total, 0.0)
    }
}

func agglomerate(_ delta: [[Double]], _ method: Linkage) -> [Merge] {
    let n = delta.count, capacity = 2 * delta.count - 1
    var values = Array(repeating: Array(repeating: 0.0, count: capacity), count: capacity)
    for u in 0..<n {
        for w in 0..<n { values[u][w] = method.squared ? delta[u][w] * delta[u][w] : delta[u][w] }
    }
    var sizes = Array(repeating: 1, count: capacity)
    var active = Array(0..<n)
    var merges: [Merge] = []
    for step in 0..<(n - 1) {
        var a = active[0], b = active[1]
        for position in active.indices {
            for w in active.dropFirst(position + 1) {
                let u = active[position]
                if values[u][w] < values[a][b] { a = u; b = w }
            }
        }
        let node = n + step
        sizes[node] = sizes[a] + sizes[b]
        let height = method.squared ? sqrt(values[a][b]) : values[a][b]
        merges.append(Merge(a: a, b: b, height: height, size: sizes[node]))
        for k in active where k != a && k != b {
            let (alphaA, alphaB, beta, gamma) = lanceWilliams(method, sizes[a], sizes[b], sizes[k])
            let value = alphaA * values[a][k] + alphaB * values[b][k] + beta * values[a][b] + gamma * abs(values[a][k] - values[b][k])
            values[node][k] = value
            values[k][node] = value
        }
        active.removeAll { $0 == a || $0 == b }
        active.append(node)
    }
    return merges
}

func minimumSpanningTree(_ delta: [[Double]]) -> [Edge] {
    let n = delta.count
    var inTree = Array(repeating: false, count: n)
    inTree[0] = true
    var keys = delta[0], parents = Array(repeating: 0, count: n)
    var edges: [Edge] = []
    for _ in 0..<(n - 1) {
        var chosen: Int? = nil
        for u in 0..<n where !inTree[u] {
            if chosen == nil || keys[u] < keys[chosen!] { chosen = u }
        }
        let v = chosen!
        inTree[v] = true
        edges.append(Edge(parent: parents[v], child: v, weight: keys[v]))
        for u in 0..<n where !inTree[u] && delta[v][u] < keys[u] {
            keys[u] = delta[v][u]
            parents[u] = v
        }
    }
    return edges
}
