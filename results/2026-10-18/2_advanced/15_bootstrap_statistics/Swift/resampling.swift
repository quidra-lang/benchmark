import Foundation

func sequentialSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var total = 0.0
    for value in values { total += value }
    return total
}

func total(_ values: [Int64]) -> Int64 { values.reduce(0, +) }
func mean(_ values: [Int64]) -> Double { Double(total(values)) / Double(100 * values.count) }

func doubledMedian(_ values: [Int64]) -> Int64 {
    let ordered = values.sorted()
    let size = ordered.count
    return ordered[(size + 1) / 2 - 1] + ordered[(size + 2) / 2 - 1]
}

func median(_ values: [Int64]) -> Double { Double(doubledMedian(values)) / 200 }
func trimCount(_ size: Int) -> Int { size / 10 }

func trimmedMean(_ values: [Int64]) -> Double {
    let ordered = values.sorted()
    let size = ordered.count
    let trim = trimCount(size)
    return Double(total(Array(ordered[trim..<(size - trim)]))) / Double(100 * (size - 2 * trim))
}

func sd(_ values: [Int64]) -> Double {
    let center = mean(values)
    let squares = sequentialSum(values.map { value in
        let deviation = Double(value) / 100 - center
        return deviation * deviation
    })
    return sqrt(squares / Double(values.count - 1))
}

func centralMoments(_ values: [Int64]) -> [Double] {
    let center = mean(values)
    var moments = [0.0, 0.0, 0.0]
    for value in values {
        let deviation = Double(value) / 100 - center
        moments[0] += deviation * deviation
        moments[1] += deviation * deviation * deviation
        moments[2] += deviation * deviation * deviation * deviation
    }
    return moments.map { $0 / Double(values.count) }
}

func mad(_ values: [Int64]) -> Double {
    let center = doubledMedian(values)
    return Double(doubledMedian(values.map { abs(2 * $0 - center) })) / 400
}

func quantileNumerator(_ values: [Int64], _ percent: Int) -> Int64 {
    let ordered = values.sorted()
    let position = (values.count - 1) * percent
    let index = position / 100
    let fraction = Int64(position % 100)
    return fraction == 0 ? 100 * ordered[index] : 100 * ordered[index] + fraction * (ordered[index + 1] - ordered[index])
}

func winsorized(_ values: [Int64]) -> [Int64] {
    let ordered = values.sorted()
    let trim = trimCount(values.count)
    return values.map { min(max($0, ordered[trim]), ordered[values.count - trim - 1]) }
}

func meanDifference(_ x: [Int64], _ y: [Int64]) -> Double {
    Double(Int64(y.count) * total(x) - Int64(x.count) * total(y)) / Double(100 * x.count * y.count)
}

func medianRatio(_ x: [Int64], _ y: [Int64]) -> Double { Double(doubledMedian(x)) / Double(doubledMedian(y)) }

func hodgesLehmann(_ x: [Int64], _ y: [Int64]) -> Double {
    Double(doubledMedian(x.flatMap { first in y.map { first - $0 } })) / 200
}

func pooledSD(_ x: [Int64], _ y: [Int64]) -> Double {
    let first = sd(x)
    let second = sd(y)
    let squares = Double(x.count - 1) * first * first + Double(y.count - 1) * second * second
    return sqrt(squares / Double(x.count + y.count - 2))
}

func cohenD(_ x: [Int64], _ y: [Int64]) -> Double { meanDifference(x, y) / pooledSD(x, y) }

func correlation(_ x: [Int64], _ y: [Int64]) -> Double {
    let firstCenter = mean(x)
    let secondCenter = mean(y)
    let first = x.map { Double($0) / 100 - firstCenter }
    let second = y.map { Double($0) / 100 - secondCenter }
    let products = sequentialSum(zip(first, second).map { first, second in first * second })
    let firstSquares = sequentialSum(first.map { $0 * $0 })
    let secondSquares = sequentialSum(second.map { $0 * $0 })
    return products / sqrt(firstSquares * secondSquares)
}

func groupStatistics(_ values: [Int64]) -> [Double] { [mean(values), median(values), trimmedMean(values), sd(values)] }
func pairStatistics(_ x: [Int64], _ y: [Int64]) -> [Double] { [meanDifference(x, y), medianRatio(x, y), hodgesLehmann(x, y), cohenD(x, y)] }

func resampleIndices(_ generator: inout Minstd, _ size: Int) -> [Int] {
    (0..<size).map { _ in generator.drawBelow(size) }
}

func ordinaryIndices(_ generator: inout Minstd, _ size: Int, _ count: Int) -> [[Int]] {
    (0..<count).map { _ in resampleIndices(&generator, size) }
}

func balancedIndices(_ generator: inout Minstd, _ size: Int, _ count: Int) -> [[Int]] {
    var indices = (0..<count).flatMap { _ in Array(0..<size) }
    generator.shuffle(&indices)
    return (0..<count).map { Array(indices[($0 * size)..<(($0 + 1) * size)]) }
}

func without(_ values: [Int64], _ omitted: Int) -> [Int64] {
    values.enumerated().filter { $0.offset != omitted }.map { $0.element }
}

func meanAndSE(_ values: [Double]) -> (average: Double, se: Double) {
    let average = sequentialSum(values) / Double(values.count)
    let squares = sequentialSum(values.map { ($0 - average) * ($0 - average) })
    return (average, sqrt(squares / Double(values.count - 1)))
}

func phi(_ value: Double) -> Double {
    if value < 0 { return 1 - phi(-value) }
    let eta = 1 / (1 + 0.2316419 * value)
    let psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))))
    return 1 - 0.3989422804014327 * exp(-(value * value) / 2) * psi
}

func phiInverse(_ probability: Double) -> Double {
    if probability > 0.5 { return -phiInverse(1 - probability) }
    let eta = sqrt(-2 * log(probability))
    let numerator = 2.515517 + eta * (0.802853 + eta * 0.010328)
    let denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))
    return -(eta - numerator / denominator)
}
