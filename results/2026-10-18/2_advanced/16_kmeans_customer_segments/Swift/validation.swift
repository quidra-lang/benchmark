import Foundation

func distanceTable(_ points: [Point]) -> [[Double]] {
    var table = Array(repeating: Array(repeating: 0.0, count: points.count), count: points.count)
    for first in points.indices {
        for second in (first + 1)..<points.count {
            let distance = sqrt(squaredDistance(points[first], points[second]))
            table[first][second] = distance
            table[second][first] = distance
        }
    }
    return table
}

func silhouettes(_ table: [[Double]], _ labels: [Int], _ sizes: [Int]) -> [Double] {
    table.enumerated().map { index, row in
        let own = labels[index]
        if sizes[own] == 1 { return 0 }
        var totals = Array(repeating: 0.0, count: sizes.count)
        for (other, distance) in row.enumerated() where other != index { totals[labels[other]] += distance }
        let inner = totals[own] / Double(sizes[own] - 1)
        var outer = Double.infinity
        for segment in sizes.indices where segment != own { outer = min(outer, totals[segment] / Double(sizes[segment])) }
        let largest = max(inner, outer)
        return largest == 0 ? 0 : (outer - inner) / largest
    }
}

func calinskiHarabasz(_ points: [Point], _ centers: [Point], _ sizes: [Int], _ within: Double) -> Double {
    let overall = meanPoint(points)
    var between = 0.0
    for (center, size) in zip(centers, sizes) { between += Double(size) * squaredDistance(center, overall) }
    return (between / Double(centers.count - 1)) / (within / Double(points.count - centers.count))
}

func daviesBouldin(_ points: [Point], _ labels: [Int], _ centers: [Point], _ sizes: [Int]) -> Double {
    let k = centers.count
    var spreads = Array(repeating: 0.0, count: k)
    for (point, label) in zip(points, labels) { spreads[label] += sqrt(squaredDistance(point, centers[label])) }
    for index in spreads.indices { spreads[index] /= Double(sizes[index]) }
    var total = 0.0
    for first in 0..<k {
        var worst = -Double.infinity
        for second in 0..<k where first != second {
            let value = (spreads[first] + spreads[second]) / sqrt(squaredDistance(centers[first], centers[second]))
            worst = max(worst, value)
        }
        total += worst
    }
    return total / Double(k)
}

func elbow(_ k: Int, _ minimum: Int, _ maximum: Int, _ within: Double, _ first: Double, _ last: Double) -> Double {
    let x = Double(k - minimum) / Double(maximum - minimum)
    let y = (within - last) / (first - last)
    return ((1 - x) - y) / sqrt(2)
}

func hartigan(_ within: Double, _ next: Double, _ count: Int, _ k: Int) -> Double {
    (within / next - 1) * Double(count - k - 1)
}

private struct Joint<A: Hashable, B: Hashable>: Hashable {
    let first: A
    let second: B
}

private func pairCount(_ size: Int64) -> Int64 { size * (size - 1) / 2 }

func adjustedRandIndex<A: Hashable, B: Hashable>(_ first: [A], _ second: [B]) -> Double {
    var joint: [Joint<A, B>: Int64] = [:]
    var firstSizes: [A: Int64] = [:]
    var secondSizes: [B: Int64] = [:]
    for (a, b) in zip(first, second) {
        joint[Joint(first: a, second: b), default: 0] += 1
        firstSizes[a, default: 0] += 1
        secondSizes[b, default: 0] += 1
    }
    let total = pairCount(Int64(first.count))
    let shared = joint.values.reduce(Int64(0)) { $0 + pairCount($1) }
    let firstPairs = firstSizes.values.reduce(Int64(0)) { $0 + pairCount($1) }
    let secondPairs = secondSizes.values.reduce(Int64(0)) { $0 + pairCount($1) }
    let numerator = 2 * (total * shared - firstPairs * secondPairs)
    let denominator = total * (firstPairs + secondPairs) - 2 * firstPairs * secondPairs
    return denominator == 0 ? 1 : Double(numerator) / Double(denominator)
}
