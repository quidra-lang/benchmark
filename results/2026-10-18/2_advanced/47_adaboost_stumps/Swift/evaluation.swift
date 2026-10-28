import Foundation

func number(_ value: Double, decimals: Int = 4) -> String {
    let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), decimals, value)
    return text.hasPrefix("-") && Double(text) == 0 ? String(text.dropFirst()) : text
}

func ratio(_ numerator: Int, _ denominator: Int) -> String { denominator > 0 ? number(Double(numerator) / Double(denominator)) : "-" }
func ratio(_ numerator: Double, _ denominator: Int) -> String { denominator > 0 ? number(numerator / Double(denominator)) : "-" }
func ratio(_ numerator: Double, _ denominator: Double) -> String { denominator > 0 ? number(numerator / denominator) : "-" }
func prediction(_ score: Double) -> Int { score > 0 ? 1 : -1 }

func auc(_ rows: [Row], _ scores: [Double]) -> (numerator: Int, denominator: Int) {
    let positives = rows.indices.filter { rows[$0].label == 1 }.map { scores[$0] }, negatives = rows.indices.filter { rows[$0].label == -1 }.map { scores[$0] }
    var wins = 0, ties = 0
    for positive in positives {
        for negative in negatives { if positive > negative { wins += 1 } else if positive == negative { ties += 1 } }
    }
    return (2 * wins + ties, 2 * positives.count * negatives.count)
}

func confusion(_ rows: [Row], _ predictions: [Int], _ classes: Int) -> [[Int]] {
    var matrix = Array(repeating: Array(repeating: 0, count: classes), count: classes)
    for i in rows.indices { matrix[rows[i].label - 1][predictions[i] - 1] += 1 }
    return matrix
}

func countAtMost(_ margins: [Double], _ threshold: Double) -> Int { margins.filter { $0 <= threshold }.count }
func writeLines(_ filename: String, _ lines: [String]) throws { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + filename, atomically: false, encoding: .ascii) }
