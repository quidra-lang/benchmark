import Foundation

func sign(_ value: Double) -> Int { value > 0 ? 1 : -1 }
func folds(_ size: Int, _ count: Int) -> [(training: [Int], testing: [Int])] { (0..<count).map { fold in ((0..<size).filter { $0 % count != fold }, (0..<size).filter { $0 % count == fold }) } }
func correctCount(_ labels: [Int], _ values: [Double]) -> Int { labels.indices.filter { labels[$0] == sign(values[$0]) }.count }
struct BinaryCounts { var tp = 0; var fp = 0; var tn = 0; var fn = 0; var correct: Int { tp + tn } }
func binaryCounts(_ labels: [Int], _ values: [Double]) -> BinaryCounts {
    var counts = BinaryCounts()
    for i in labels.indices { if labels[i] == 1 { if sign(values[i]) == 1 { counts.tp += 1 } else { counts.fn += 1 } } else { if sign(values[i]) == 1 { counts.fp += 1 } else { counts.tn += 1 } } }
    return counts
}
func auc(_ labels: [Int], _ values: [Double]) -> Double {
    let positives = labels.indices.filter { labels[$0] == 1 }, negatives = labels.indices.filter { labels[$0] == -1 }
    var total = 0.0
    for p in positives { for n in negatives { if values[p] > values[n] { total += 1 } else if values[p] == values[n] { total += 0.5 } } }
    return total / Double(positives.count * negatives.count)
}
func confusionMatrix(_ classes: [Int], _ predictions: [Int]) -> [[Int]] { var matrix = Array(repeating: Array(repeating: 0, count: 3), count: 3); for i in classes.indices { matrix[classes[i] - 1][predictions[i] - 1] += 1 }; return matrix }
func confusionLines(_ matrix: [[Int]]) -> [String] { matrix.map { $0.map(String.init).joined(separator: " ") } + (0..<3).map { i in "class \(i + 1) precision \(ratio(matrix[i][i], matrix.reduce(0) { $0 + $1[i] })) recall \(ratio(matrix[i][i], matrix[i].reduce(0, +)))" } }
func fixed(_ value: Double, _ places: Int = 4) -> String { let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
func ratio(_ numerator: Int, _ denominator: Int) -> String { denominator > 0 ? fixed(Double(numerator) / Double(denominator)) : "-" }
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
