import Foundation

enum DistanceModel: String { case p = "P", jc = "JC", k2p = "K2P" }
let distanceModels = [DistanceModel.p, .jc, .k2p]
struct PairCounts { let first: Int; let second: Int; let sites: Int; let transitions: Int; let transversions: Int }
struct MatrixResult { let matrix: [[Double]]; let saturated: [PairCounts] }
func pairCounts(_ first: [UInt8], _ second: [UInt8], _ weights: [Int]) -> (sites: Int, transitions: Int, transversions: Int) { var sites = 0, transitions = 0, transversions = 0; for column in first.indices { let a = first[column], b = second[column]; if !baseSymbols.contains(a) || !baseSymbols.contains(b) { continue }; sites += weights[column]; if a != b { if (a == 65 && b == 71) || (a == 71 && b == 65) || (a == 67 && b == 84) || (a == 84 && b == 67) { transitions += weights[column] } else { transversions += weights[column] } } }; return (sites, transitions, transversions) }
func allPairs(_ sequences: [[UInt8]], _ weights: [Int]) -> [PairCounts] { var pairs: [PairCounts] = []; for first in sequences.indices { for second in (first + 1)..<sequences.count { let counts = pairCounts(sequences[first], sequences[second], weights); pairs.append(PairCounts(first: first, second: second, sites: counts.sites, transitions: counts.transitions, transversions: counts.transversions)) } }; return pairs }
func corrected(_ model: DistanceModel, _ counts: PairCounts, _ replacement: Double) -> (value: Double, saturated: Bool) {
    let n = counts.sites, s = counts.transitions, v = counts.transversions
    if n == 0 || (model == .jc && 4 * (s + v) >= 3 * n) || (model == .k2p && (2 * s + v >= n || 2 * v >= n)) { return (replacement, true) }
    let value: Double
    switch model { case .p: value = Double(s + v) / Double(n); case .jc: value = -(3.0 / 4) * log(1 - Double(4 * (s + v)) / Double(3 * n)); case .k2p: value = -(1.0 / 2) * log(1 - Double(2 * s) / Double(n) - Double(v) / Double(n)) - (1.0 / 4) * log(1 - Double(2 * v) / Double(n)) }
    return (value, false)
}
func buildMatrix(_ pairs: [PairCounts], _ count: Int, _ model: DistanceModel, _ replacement: Double) -> MatrixResult { var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count), saturated: [PairCounts] = []; for pair in pairs { let result = corrected(model, pair, replacement); matrix[pair.first][pair.second] = result.value; matrix[pair.second][pair.first] = result.value; if result.saturated { saturated.append(pair) } }; return MatrixResult(matrix: matrix, saturated: saturated) }
