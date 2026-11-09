import Foundation

func realText(_ value: Double) -> String {
    let text = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" ? "0.0000" : text
}
func rounded(_ value: Double) -> Int { Int((value * 10000).rounded()) }
func proportionText(_ numerator: Int, _ denominator: Int) -> String { "\(numerator)/\(denominator) \(realText(Double(numerator) / Double(denominator)))" }
func fractionText(_ numerator: Int, _ denominator: Int) -> String {
    if denominator == 0 { return "- -" }
    var a = abs(numerator), b = denominator
    while b != 0 { (a, b) = (b, a % b) }
    return proportionText(numerator / a, denominator / a)
}
struct Evaluation {
    let matrix: [[Int]]
    let total: Int
    let correct: Int
    let microF1: Double
    let macroF1: Double
    init(_ classCount: Int, _ truths: [Int], _ predictions: [Int]) {
        var matrix = Array(repeating: Array(repeating: 0, count: classCount), count: classCount)
        for (truth, predicted) in zip(truths, predictions) { matrix[truth][predicted] += 1 }
        let correct = (0..<classCount).reduce(0) { $0 + matrix[$1][$1] }
        var sum = 0.0, scored = 0
        for label in 0..<classCount {
            let support = matrix[label].reduce(0, +), predicted = matrix.reduce(0) { $0 + $1[label] }
            if support + predicted > 0 { sum += Double(2 * matrix[label][label]) / Double(support + predicted); scored += 1 }
        }
        self.matrix = matrix; total = truths.count; self.correct = correct
        microF1 = Double(correct) / Double(truths.count); macroF1 = sum / Double(scored)
    }
    func support(_ label: Int) -> Int { matrix[label].reduce(0, +) }
    func predictedCount(_ label: Int) -> Int { matrix.reduce(0) { $0 + $1[label] } }
    var fields: String { "\(correct),\(realText(microF1)),\(realText(macroF1))" }
    func lines(_ names: [String]) -> [String] {
        var lines = ["true\\predicted " + names.joined(separator: " ")]
        for label in names.indices { lines.append(names[label] + " " + matrix[label].map(String.init).joined(separator: " ")) }
        for label in names.indices {
            let hits = matrix[label][label], predicted = predictedCount(label), support = self.support(label)
            lines.append("class \(names[label]) precision \(fractionText(hits, predicted)) recall \(fractionText(hits, support)) f1 \(fractionText(2 * hits, predicted + support)) support \(support)")
        }
        lines.append("micro_f1 \(realText(microF1)) macro_f1 \(realText(macroF1))")
        return lines
    }
}
