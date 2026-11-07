struct WeightedEdge {
    let source: Int
    let weight: Int
}

typealias WeightedEdges = [[WeightedEdge]]

struct PageRankResult {
    let values: [Double]
    let changes: [Double]
    let convergedAt: Int?
}

func powerIteration(_ inEdges: WeightedEdges, _ teleport: [Int], _ damping: Double,
    _ iterations: Int, _ tolerance: Double) -> PageRankResult {
    let count = inEdges.count
    var outWeight = Array(repeating: 0, count: count)
    for edges in inEdges { for edge in edges { outWeight[edge.source] += edge.weight } }
    let dangling = (0..<count).filter { outWeight[$0] == 0 }
    var inTeleport = Array(repeating: false, count: count)
    for node in teleport { inTeleport[node] = true }
    let size = Double(teleport.count)
    var values = inTeleport.map { $0 ? 1 / size : 0 }
    var changes: [Double] = []
    var convergedAt: Int? = nil
    for step in 1...iterations {
        var danglingMass = 0.0
        for node in dangling { danglingMass += values[node] }
        let teleportValue = ((1 - damping) + damping * danglingMass) / size
        var updated: [Double] = []
        for node in 0..<count {
            var inflow = 0.0
            for edge in inEdges[node] { inflow += (values[edge.source] * Double(edge.weight)) / Double(outWeight[edge.source]) }
            updated.append(damping * inflow + (inTeleport[node] ? teleportValue : 0))
        }
        var change = 0.0
        for node in 0..<count { change += abs(updated[node] - values[node]) }
        changes.append(change)
        if convergedAt == nil && change < tolerance { convergedAt = step }
        values = updated
    }
    return PageRankResult(values: values, changes: changes, convergedAt: convergedAt)
}
