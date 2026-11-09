import Foundation

enum DistanceKind: String, CaseIterable {
    case euclidean, manhattan, correlation
}

func sequentialSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var total = 0.0
    for value in values { total += value }
    return total
}

func squaredDistance(_ first: [Double], _ second: [Double]) -> Double {
    sequentialSum(zip(first, second).map { a, b in (a - b) * (a - b) })
}

func featureStatistics(_ rows: [[Double]]) -> ([Double], [Double]) {
    var means: [Double] = []
    var deviations: [Double] = []
    for f in rows[0].indices {
        let mean = sequentialSum(rows.map { $0[f] }) / Double(rows.count)
        let variance = sequentialSum(rows.map { ($0[f] - mean) * ($0[f] - mean) }) / Double(rows.count - 1)
        means.append(mean)
        deviations.append(sqrt(variance))
    }
    return (means, deviations)
}

func standardize(_ rows: [[Double]], _ means: [Double], _ deviations: [Double]) -> [[Double]] {
    rows.map { row in row.indices.map { (row[$0] - means[$0]) / deviations[$0] } }
}

func distance(_ first: [Double], _ second: [Double], _ kind: DistanceKind) -> Double {
    switch kind {
    case .euclidean:
        return sqrt(squaredDistance(first, second))
    case .manhattan:
        return sequentialSum(zip(first, second).map { a, b in abs(a - b) })
    case .correlation:
        let meanA = sequentialSum(first) / Double(first.count)
        let meanB = sequentialSum(second) / Double(second.count)
        let cross = sequentialSum(zip(first, second).map { a, b in (a - meanA) * (b - meanB) })
        let spreadA = sequentialSum(first.map { ($0 - meanA) * ($0 - meanA) })
        let spreadB = sequentialSum(second.map { ($0 - meanB) * ($0 - meanB) })
        return 1.0 - cross / sqrt(spreadA * spreadB)
    }
}

func distanceMatrix(_ vectors: [[Double]], _ kind: DistanceKind) -> [[Double]] {
    let n = vectors.count
    var matrix = Array(repeating: Array(repeating: 0.0, count: n), count: n)
    for i in 0..<n {
        for j in (i + 1)..<n {
            let value = distance(vectors[i], vectors[j], kind)
            matrix[i][j] = value
            matrix[j][i] = value
        }
    }
    return matrix
}
