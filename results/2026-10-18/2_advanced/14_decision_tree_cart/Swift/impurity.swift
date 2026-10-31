struct Fraction {
    let numerator: Int64
    let denominator: Int64
    func compare(_ other: Fraction) -> Int {
        let first = numerator * other.denominator
        let second = other.numerator * denominator
        return first == second ? 0 : first < second ? -1 : 1
    }
    var real: Double { Double(numerator) / Double(denominator) }
}

func classCounts(_ rows: [Row], _ classCount: Int) -> [Int64] {
    var counts = Array<Int64>(repeating: 0, count: classCount)
    for row in rows { counts[row.label] += 1 }
    return counts
}

func squareSum(_ counts: [Int64]) -> Int64 { counts.reduce(0) { $0 + $1 * $1 } }

func majority(_ counts: [Int64]) -> Int {
    var best = 0
    for index in counts.indices.dropFirst() where counts[index] > counts[best] { best = index }
    return best
}

func errorCount(_ counts: [Int64]) -> Int64 { counts.reduce(0, +) - counts[majority(counts)] }

func evaluationValue(_ left: [Int64], _ right: [Int64]) -> Fraction {
    let leftSize = left.reduce(0, +)
    let rightSize = right.reduce(0, +)
    return Fraction(numerator: squareSum(left) * rightSize + squareSum(right) * leftSize,
        denominator: leftSize * rightSize)
}

func improves(_ value: Fraction, _ counts: [Int64]) -> Bool {
    value.numerator * counts.reduce(0, +) > squareSum(counts) * value.denominator
}

func impurityDecrease(_ counts: [Int64], _ left: [Int64], _ right: [Int64]) -> Double {
    Double(squareSum(left)) / Double(left.reduce(0, +))
        + Double(squareSum(right)) / Double(right.reduce(0, +))
        - Double(squareSum(counts)) / Double(counts.reduce(0, +))
}
