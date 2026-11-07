import Foundation

func real(_ value: Double, _ places: Int) -> String { let text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value); return text.first == "-" && Double(text) == 0 ? String(text.dropFirst()) : text }
func ratio(_ numerator: Int, _ denominator: Int) -> String { if denominator == 0 { return "-" }; let rounded = (20000 * numerator + denominator) / (2 * denominator), remainder = String(rounded % 10000); return "\(rounded / 10000)." + String(repeating: "0", count: 4 - remainder.count) + remainder }
func bestTwo(_ scores: [Double]) -> [Int] { Array(scores.indices.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1] }.prefix(2)) }
func confusion(_ outcomes: [Outcome], _ classes: Int) -> [[Int]] { var matrix = Array(repeating: Array(repeating: 0, count: classes), count: classes); for outcome in outcomes { matrix[outcome.label][outcome.predicted] += 1 }; return matrix }
struct ClassMeasures { let support: Int; let predicted: Int; let precision: String; let recall: String; let f1: String }
func classMeasures(_ table: [[Int]], _ number: Int) -> ClassMeasures { let support = table[number].reduce(0, +), predicted = table.reduce(0) { $0 + $1[number] }, correct = table[number][number]; return ClassMeasures(support: support, predicted: predicted, precision: ratio(correct, predicted), recall: ratio(correct, support), f1: ratio(2 * correct, support + predicted)) }
func levelMaps(_ levels: [[Int]], _ width: Int, _ height: Int) -> [String] { (0..<height).map { row in levels.map { level in (0..<width).map { String(level[row * width + $0]) }.joined() }.joined(separator: " ") } }
func asciiImage(_ image: Image, _ width: Int, _ height: Int) -> [String] { (0..<height).map { row in (0..<width).map { image.pixels[row * width + $0] == 49 ? "#" : "." }.joined() } }
func binaryFrequency(_ images: [Image], _ label: Int, _ pixels: Int) -> [Int] { let chosen = images.filter { $0.label == label }; if chosen.isEmpty { return Array(repeating: 0, count: pixels) }; return (0..<pixels).map { i in min(9, 10 * chosen.filter { $0.pixels[i] == 49 }.count / chosen.count) } }
