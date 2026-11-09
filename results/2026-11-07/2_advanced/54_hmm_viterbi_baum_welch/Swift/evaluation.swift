import Foundation

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    if denominator == 0 { return "-" }
    var x = abs(numerator), y = abs(denominator)
    while y != 0 { let next = x % y; x = y; y = next }
    return "\(denominator < 0 ? -numerator / x : numerator / x)/\(abs(denominator) / x)"
}
func confusionMatrix(_ count: Int) -> [[Int]] { Array(repeating: Array(repeating: 0, count: count), count: count) }
func accumulateConfusion(_ matrix: inout [[Int]], _ truth: [Int], _ prediction: [Int]) { for i in truth.indices { matrix[truth[i]][prediction[i]] += 1 } }
func correctCount(_ truth: [Int], _ prediction: [Int]) -> Int { truth.indices.filter { truth[$0] == prediction[$0] }.count }
func matrixLines(_ states: [String], _ matrix: [[Int]]) -> [String] {
    let width = matrix.flatMap { $0 }.map { String($0).count }.max()!
    func pad(_ text: String) -> String { String(repeating: " ", count: width - text.count) + text }
    return [" " + states.map { " " + pad($0) }.joined()] + states.enumerated().map { i, state in state + matrix[i].map { " " + pad(String($0)) }.joined() }
}
func metricLines(_ states: [String], _ matrix: [[Int]]) -> [String] {
    let rows = matrix.map { $0.reduce(0, +) }, columns = states.indices.map { col in matrix.reduce(0) { $0 + $1[col] } }, total = rows.reduce(0, +), correct = states.indices.reduce(0) { $0 + matrix[$1][$1] }, expected = states.indices.reduce(0) { $0 + rows[$1] * columns[$1] }
    return ["ACCURACY \(fraction(correct, total))", "KAPPA \(fraction(total * correct - expected, total * total - expected))"] + states.indices.map { i in "STATE \(states[i]) precision \(fraction(matrix[i][i], columns[i])) recall \(fraction(matrix[i][i], rows[i])) f1 \(fraction(2 * matrix[i][i], columns[i] + rows[i]))" }
}
struct Segment { let start: Int; let end: Int; var length: Int { end - start + 1 } }
struct PathRun { let state: Int; let segment: Segment }
func runs(_ path: [Int]) -> [PathRun] {
    if path.isEmpty { return [] }
    var result: [PathRun] = [], start = 1, state = path[0]
    for i in path.indices.dropFirst() { if path[i] != state { result.append(PathRun(state: state, segment: Segment(start: start, end: i))); state = path[i]; start = i + 1 } }
    result.append(PathRun(state: state, segment: Segment(start: start, end: path.count)))
    return result
}
struct MatchCounts {
    var predicted = 0
    var truth = 0
    var matchedPredicted = 0
    var matchedTruth = 0
    mutating func add(_ other: MatchCounts) { predicted += other.predicted; truth += other.truth; matchedPredicted += other.matchedPredicted; matchedTruth += other.matchedTruth }
    var text: String { "predicted \(predicted) true \(truth) precision \(fraction(matchedPredicted, predicted)) recall \(fraction(matchedTruth, truth))" }
}
func regionCounts(_ predicted: [Segment], _ truth: [Segment]) -> MatchCounts {
    func overlap(_ a: Segment, _ b: Segment) -> Bool { a.start <= b.end && b.start <= a.end }
    return MatchCounts(predicted: predicted.count, truth: truth.count, matchedPredicted: predicted.filter { a in truth.contains { overlap(a, $0) } }.count, matchedTruth: truth.filter { a in predicted.contains { overlap(a, $0) } }.count)
}
func boundaries(_ path: [Int]) -> [Int] { path.indices.dropFirst().filter { path[$0 - 1] != path[$0] }.map { $0 + 1 } }
func boundaryCounts(_ predictedPath: [Int], _ truePath: [Int], _ tolerance: Int) -> MatchCounts {
    let predicted = boundaries(predictedPath), truth = boundaries(truePath)
    return MatchCounts(predicted: predicted.count, truth: truth.count, matchedPredicted: predicted.filter { a in truth.contains { abs(a - $0) <= tolerance } }.count, matchedTruth: truth.filter { a in predicted.contains { abs(a - $0) <= tolerance } }.count)
}
