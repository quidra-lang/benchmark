struct RRStatistics {
    let count: Int
    let meanRR: Int?
    let meanHR: Int?
    let shortest: (beat: Int, value: Int)?
    let longest: (beat: Int, value: Int)?
}

struct NNStatistics {
    let count: Int
    let pairs: Int
    let mean: Int?
    let sdnn: Int?
    let rmssd: Int?
    let sdsd: Int?
    let nn50: Int
    let pnn50: Int?
    let sd1: Int?
    let sd2: Int?
    let histogram: [Int: Int]
    let histogramMaximum: Int
    let triangularIndex: Int?
}

func integerSquareRoot(_ value: Int) -> Int {
    if value < 2 { return value }
    var current = value
    var next = (current + value / current) / 2
    while next < current {
        current = next
        next = (current + value / current) / 2
    }
    return current
}

func root(_ numerator: Int, _ denominator: Int) -> Int { (integerSquareRoot(40000 * numerator / denominator) + 1) / 2 }

func mean(_ values: [Int]) -> Int? { values.isEmpty ? nil : rdiv(100 * values.reduce(0, +), values.count) }

func meanHeartRate(_ values: [Int]) -> Int? { values.isEmpty ? nil : rdiv(6000000 * values.count, values.reduce(0, +)) }

func rrStatistics(_ intervals: [(beat: Int, value: Int)]) -> RRStatistics {
    let values = intervals.map { $0.value }
    let shortest = intervals.min { $0.value == $1.value ? $0.beat < $1.beat : $0.value < $1.value }
    let longest = intervals.min { $0.value == $1.value ? $0.beat < $1.beat : $0.value > $1.value }
    return RRStatistics(count: intervals.count, meanRR: mean(values), meanHR: meanHeartRate(values), shortest: shortest, longest: longest)
}

func nnStatistics(_ values: [Int], _ pairs: [(Int, Int)]) -> NNStatistics {
    let differences = pairs.map { $0.1 - $0.0 }
    let sums = pairs.map { $0.0 + $0.1 }
    let e = values.count
    let k = pairs.count
    let total = values.reduce(0, +)
    let squares = values.reduce(0) { $0 + $1 * $1 }
    let differenceTotal = differences.reduce(0, +)
    let differenceSquares = differences.reduce(0) { $0 + $1 * $1 }
    let sumTotal = sums.reduce(0, +)
    let sumSquares = sums.reduce(0) { $0 + $1 * $1 }
    let differenceVariance = k * differenceSquares - differenceTotal * differenceTotal
    let sumVariance = k * sumSquares - sumTotal * sumTotal
    let nn50 = differences.filter { abs($0) > 50 }.count
    var histogram: [Int: Int] = [:]
    for value in values { histogram[16 * value / 125, default: 0] += 1 }
    let maximum = histogram.values.max() ?? 0
    return NNStatistics(count: e, pairs: k, mean: mean(values),
                         sdnn: e >= 2 ? root(e * squares - total * total, e * (e - 1)) : nil,
                         rmssd: k > 0 ? root(differenceSquares, k) : nil,
                         sdsd: k >= 2 ? root(differenceVariance, k * (k - 1)) : nil,
                         nn50: nn50, pnn50: k > 0 ? rdiv(10000 * nn50, k) : nil,
                         sd1: k >= 2 ? root(differenceVariance, 2 * k * (k - 1)) : nil,
                         sd2: k >= 2 ? root(sumVariance, 2 * k * (k - 1)) : nil,
                         histogram: histogram, histogramMaximum: maximum,
                         triangularIndex: maximum > 0 ? rdiv(100 * e, maximum) : nil)
}

func consecutiveRanges(_ indices: [Int]) -> [(first: Int, last: Int)] {
    guard let first = indices.first else { return [] }
    var start = first
    var end = first
    var ranges: [(Int, Int)] = []
    for current in indices.dropFirst() {
        if current == end + 1 { end = current }
        else {
            ranges.append((start, end))
            start = current
            end = current
        }
    }
    ranges.append((start, end))
    return ranges
}
