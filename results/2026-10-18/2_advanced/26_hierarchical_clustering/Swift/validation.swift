import Foundation

struct Fraction {
    let numerator: Int
    let denominator: Int
    var value: Double { Double(numerator) / Double(denominator) }
    func greater(_ other: Fraction) -> Bool { numerator * other.denominator > other.numerator * denominator }
}

func correlation(_ first: [Double], _ second: [Double]) -> Double {
    let meanA = sequentialSum(first) / Double(first.count), meanB = sequentialSum(second) / Double(second.count)
    let cross = sequentialSum(zip(first, second).map { a, b in (a - meanA) * (b - meanB) })
    let spreadA = sequentialSum(first.map { ($0 - meanA) * ($0 - meanA) })
    let spreadB = sequentialSum(second.map { ($0 - meanB) * ($0 - meanB) })
    return cross / sqrt(spreadA * spreadB)
}

func contingencyTable(_ first: [Int], _ second: [Int], _ rows: Int, _ columns: Int) -> [[Int]] {
    var table = Array(repeating: Array(repeating: 0, count: columns), count: rows)
    for (a, b) in zip(first, second) { table[a][b] += 1 }
    return table
}

func pairCount(_ count: Int) -> Int { count * (count - 1) / 2 }

func adjustedRandIndex(_ table: [[Int]]) -> Fraction {
    let count = table.reduce(0) { $0 + $1.reduce(0, +) }
    let same = table.reduce(0) { $0 + $1.reduce(0) { $0 + pairCount($1) } }
    let rowPairs = table.reduce(0) { $0 + pairCount($1.reduce(0, +)) }
    let columnPairs = table[0].indices.reduce(0) { total, column in total + pairCount(table.reduce(0) { $0 + $1[column] }) }
    let total = pairCount(count)
    var numerator = 2 * (total * same - rowPairs * columnPairs)
    var denominator = total * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs
    if denominator == 0 { return Fraction(numerator: 1, denominator: 1) }
    if denominator < 0 { numerator = -numerator; denominator = -denominator }
    var a = abs(numerator), b = denominator
    while b != 0 { let remainder = a % b; a = b; b = remainder }
    return Fraction(numerator: numerator / a, denominator: denominator / a)
}

func silhouetteValues(_ partition: [Int], _ groups: Int, _ delta: [[Double]]) -> [Double] {
    var sizes = Array(repeating: 0, count: groups + 1)
    for number in partition { sizes[number] += 1 }
    var values: [Double] = []
    for (i, own) in partition.enumerated() {
        if sizes[own] == 1 { values.append(0.0); continue }
        var sums = Array(repeating: 0.0, count: groups + 1)
        for (j, other) in partition.enumerated() where j != i { sums[other] += delta[i][j] }
        let inner = sums[own] / Double(sizes[own] - 1)
        var outer = Double.infinity
        for g in 1...groups where g != own { outer = min(outer, sums[g] / Double(sizes[g])) }
        values.append((outer - inner) / max(inner, outer))
    }
    return values
}
