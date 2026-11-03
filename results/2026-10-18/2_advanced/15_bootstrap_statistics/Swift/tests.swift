func positionChoices(_ total: Int, _ size: Int) -> [[Int]] {
    var choice = Array(0..<size)
    var result: [[Int]] = []
    while true {
        result.append(choice)
        guard let index = choice.indices.reversed().first(where: { choice[$0] < total - size + $0 }) else { break }
        choice[index] += 1
        if index + 1 < size {
            for next in (index + 1)..<size { choice[next] = choice[next - 1] + 1 }
        }
    }
    return result
}

func reducedFraction(_ numerator: Int64, _ denominator: Int64) -> (Int64, Int64) {
    var first = abs(numerator)
    var second = denominator
    while second != 0 { (first, second) = (second, first % second) }
    return (numerator / first, denominator / first)
}

func contrast(_ firstTotal: Int64, _ firstSize: Int, _ secondTotal: Int64, _ secondSize: Int) -> Int64 {
    Int64(secondSize) * firstTotal - Int64(firstSize) * secondTotal
}

func valueCounts(_ values: [Int64]) -> [Int64: Int] {
    var counts: [Int64: Int] = [:]
    for value in values { counts[value, default: 0] += 1 }
    return counts
}

func doubledRanks(_ values: [Int64]) -> [Int64] {
    let counts = valueCounts(values)
    var ranks: [Int64: Int64] = [:]
    var smaller = 0
    for value in counts.keys.sorted() {
        let count = counts[value]!
        ranks[value] = Int64(2 * smaller + count + 1)
        smaller += count
    }
    return values.map { ranks[$0]! }
}

func splitList<T>(_ items: [T], _ sizes: [Int]) -> [[T]] {
    var start = 0
    return sizes.map { size in
        let part = Array(items[start..<(start + size)])
        start += size
        return part
    }
}

func sumsOfSquares(_ samples: [[Int64]]) -> (between: Double, within: Double) {
    let count = samples.reduce(0) { $0 + $1.count }
    let grandMean = Double(samples.reduce(Int64(0)) { $0 + total($1) }) / Double(100 * count)
    var between = 0.0
    var within = 0.0
    for sample in samples {
        let center = mean(sample)
        let deviation = center - grandMean
        between += Double(sample.count) * (deviation * deviation)
        var squares = 0.0
        for value in sample {
            let delta = Double(value) / 100 - center
            squares += delta * delta
        }
        within += squares
    }
    return (between, within)
}

func fStatistic(_ between: Double, _ within: Double, _ groups: Int, _ count: Int) -> Double {
    between / Double(groups - 1) / (within / Double(count - groups))
}

func hStatistic(_ rankSums: [Int64], _ sizes: [Int], _ correction: Double) -> Double {
    let count = sizes.reduce(0, +)
    let sum = sequentialSum(zip(rankSums, sizes).map { rank, size in Double(rank * rank) / Double(4 * size) })
    return (12 * sum / Double(count * (count + 1)) - 3 * Double(count + 1)) / correction
}
