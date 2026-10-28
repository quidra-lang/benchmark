struct Fraction {
    let numerator: Int
    let denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
        var a = abs(numerator)
        var b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        self.numerator = numerator / a
        self.denominator = denominator / a
    }

    func adding(_ other: Fraction) -> Fraction {
        Fraction(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator)
    }

    func divided(by value: Int) -> Fraction { Fraction(numerator, denominator * value) }
}

func reducedFraction(_ numerator: Int, _ denominator: Int) -> Fraction? {
    denominator == 0 ? nil : Fraction(numerator, denominator)
}

func sumFractions(_ values: [Fraction]) -> Fraction { values.reduce(Fraction(0, 1)) { $0.adding($1) } }

struct Measures {
    let matrix: [[Int]]
    let support: [Int]
    let correct: Int
    let accuracy: Fraction?
    let balancedAccuracy: Fraction
    let kappa: Fraction?
    let recall: [Fraction]
    let precision: [Fraction?]
    let f1: [Fraction]
    let macroF1: Double
}

func confusionMatrix(_ actual: [Int], _ predicted: [Int], _ classes: Int) -> [[Int]] {
    var matrix = Array(repeating: Array(repeating: 0, count: classes), count: classes)
    for (expected, prediction) in zip(actual, predicted) { matrix[expected][prediction] += 1 }
    return matrix
}

func measures(_ actual: [Int], _ predicted: [Int], _ classes: Int) -> Measures {
    let matrix = confusionMatrix(actual, predicted, classes)
    let support = matrix.map { $0.reduce(0, +) }
    let predictedCounts = (0..<classes).map { column in matrix.reduce(0) { $0 + $1[column] } }
    let correct = (0..<classes).reduce(0) { $0 + matrix[$1][$1] }
    let count = actual.count
    let recall = (0..<classes).map { Fraction(matrix[$0][$0], support[$0]) }
    let precision = (0..<classes).map { reducedFraction(matrix[$0][$0], predictedCounts[$0]) }
    let f1 = (0..<classes).map { Fraction(2 * matrix[$0][$0], support[$0] + predictedCounts[$0]) }
    let expected = (0..<classes).reduce(0) { $0 + support[$1] * predictedCounts[$1] }
    let macro = orderedSum((0..<classes).map { Double(2 * matrix[$0][$0]) / Double(support[$0] + predictedCounts[$0]) }) / Double(classes)
    return Measures(matrix: matrix, support: support, correct: correct, accuracy: reducedFraction(correct, count),
                     balancedAccuracy: sumFractions(recall).divided(by: classes), kappa: reducedFraction(count * correct - expected, count * count - expected),
                     recall: recall, precision: precision, f1: f1, macroF1: macro)
}

struct McNemar {
    let b01: Int
    let b10: Int
    let chiSquared: Double
    var significant: Bool { chiSquared > 3.841 }
}

func mcnemar(_ actual: [Int], _ first: [Int], _ second: [Int]) -> McNemar {
    var b01 = 0
    var b10 = 0
    for index in actual.indices {
        let a = first[index] == actual[index]
        let b = second[index] == actual[index]
        if a && !b { b01 += 1 }
        else if !a && b { b10 += 1 }
    }
    let difference = abs(b01 - b10) - 1
    let chiSquared = b01 == b10 ? 0 : Double(difference * difference) / Double(b01 + b10)
    return McNemar(b01: b01, b10: b10, chiSquared: chiSquared)
}

struct RandomGenerator {
    var state: Int
    mutating func draw() -> Int {
        state = 48271 * state % 2147483647
        return state
    }
}
