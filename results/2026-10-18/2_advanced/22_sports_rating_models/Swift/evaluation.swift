import Foundation

func sigma(_ value: Double) -> Double { 1 / (1 + exp(-value)) }
func fitLink(_ features: [Double], _ results: [Double], _ iterations: Int) -> (Double, Double) {
    var alpha = 0.0, beta = 0.0
    for _ in 0..<iterations {
        var g0 = 0.0, g1 = 0.0, h00 = 0.0, h01 = 0.0, h11 = 0.0
        for (z, y) in zip(features, results) {
            let p = sigma(alpha + beta * z), w = p * (1 - p)
            g0 += y - p; g1 += (y - p) * z; h00 += w; h01 += w * z; h11 += w * z * z
        }
        let determinant = h00 * h11 - h01 * h01
        alpha += (h11 * g0 - h01 * g1) / determinant; beta += (h00 * g1 - h01 * g0) / determinant
    }
    return (alpha, beta)
}
func logLoss(_ probability: Double, _ resultTwice: Int) -> Double {
    if resultTwice == 2 { return -log(probability) }
    if resultTwice == 0 { return -log(1 - probability) }
    return -(log(probability) / 2 + log(1 - probability) / 2)
}
func brierScore(_ probability: Double, _ resultTwice: Int) -> Double { let difference = probability - Double(resultTwice) / 2; return difference * difference }
func correctnessTwice(_ probability: Double, _ resultTwice: Int) -> Int {
    if resultTwice == 1 { return 1 }
    return probability > 0.5 && resultTwice == 2 || probability < 0.5 && resultTwice == 0 ? 2 : 0
}
private func doubledAverageRanks(_ values: [Fraction]) -> [Int] {
    values.map { value in 2 * values.filter { $0 > value }.count + values.filter { $0 == value }.count + 1 }
}
func kendallTau(_ first: [Fraction], _ second: [Fraction]) -> Fraction {
    var signed = 0
    for team in first.indices { for other in (team + 1)..<first.count {
        let a = first[team] > first[other] ? 1 : (first[team] < first[other] ? -1 : 0)
        let b = second[team] > second[other] ? 1 : (second[team] < second[other] ? -1 : 0)
        signed += a * b
    } }
    return Fraction(signed, first.count * (first.count - 1) / 2)
}
func spearmanRho(_ first: [Fraction], _ second: [Fraction]) -> Fraction {
    let firstRanks = doubledAverageRanks(first), secondRanks = doubledAverageRanks(second)
    var squares = 0
    for (a, b) in zip(firstRanks, secondRanks) { squares += (a - b) * (a - b) }
    let count = first.count
    return Fraction(1) - Fraction(6 * squares, 4 * count * (count * count - 1))
}
