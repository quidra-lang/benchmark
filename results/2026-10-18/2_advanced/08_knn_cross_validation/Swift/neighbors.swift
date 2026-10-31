import Foundation

struct Neighbor {
    let distance: Double
    let row: Row
}
struct Vote {
    let label: String
    let share: Double
    let runner: String?
    let runnerShare: Double
}
struct VoteTally {
    let label: String
    var count = 0
    var distances = 0.0
    var weights = 0.0
}
func distance(_ first: [Double], _ second: [Double], _ metric: String) -> Double {
    var total = 0.0
    var dot = 0.0
    var firstSquares = 0.0
    var secondSquares = 0.0
    for index in first.indices {
        let a = first[index], b = second[index]
        let difference = a - b
        switch metric {
        case "squared_euclidean": total += difference * difference
        case "manhattan": total += abs(difference)
        case "chebyshev": total = max(total, abs(difference))
        default: dot += a * b; firstSquares += a * a; secondSquares += b * b
        }
    }
    if metric != "cosine" { return total }
    let a = sqrt(firstSquares), b = sqrt(secondSquares)
    return a == 0 || b == 0 ? 1 : 1 - dot / (a * b)
}
func sortNeighbors(_ neighbors: [Neighbor]) -> [Neighbor] { neighbors.sorted { $0.distance == $1.distance ? $0.row.id < $1.row.id : $0.distance < $1.distance } }
func neighborOrder(_ query: [Double], _ references: [([Double], Row)], _ metric: String) -> [Neighbor] { sortNeighbors(references.map { Neighbor(distance: distance(query, $0.0, metric), row: $0.1) }) }
func vote(_ nearest: [Neighbor], _ weighting: String) -> Vote {
    var tallies: [String: VoteTally] = [:]
    var totalWeight = 0.0
    for neighbor in nearest {
        let weight = 1 / (neighbor.distance + 0.000000001)
        let label = neighbor.row.label!
        var tally = tallies[label] ?? VoteTally(label: label)
        tally.count += 1
        tally.distances += neighbor.distance
        tally.weights += weight
        tallies[label] = tally
        totalWeight += weight
    }
    let ranked = tallies.values.sorted { first, second in
        if weighting == "uniform" && first.count != second.count { return first.count > second.count }
        if weighting == "distance" && first.weights != second.weights { return first.weights > second.weights }
        return first.distances == second.distances ? first.label < second.label : first.distances < second.distances
    }
    func share(_ tally: VoteTally) -> Double { weighting == "uniform" ? Double(tally.count) / Double(nearest.count) : tally.weights / totalWeight }
    return Vote(label: ranked[0].label, share: share(ranked[0]), runner: ranked.count > 1 ? ranked[1].label : nil, runnerShare: ranked.count > 1 ? share(ranked[1]) : 0)
}
func estimate(_ nearest: [Neighbor], _ weighting: String) -> Double {
    var total = 0.0
    var weights = 0.0
    for neighbor in nearest {
        if weighting == "uniform" { total += neighbor.row.target! }
        else { let weight = 1 / (neighbor.distance + 0.000000001); total += weight * neighbor.row.target!; weights += weight }
    }
    return total / (weighting == "uniform" ? Double(nearest.count) : weights)
}
