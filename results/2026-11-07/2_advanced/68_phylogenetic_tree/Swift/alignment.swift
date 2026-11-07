import Foundation

let baseSymbols: [UInt8] = [65, 67, 71, 84]
let ambiguitySymbols: Set<UInt8> = Set("RYSWKMBDHV".utf8)
let baseSets: [UInt8: Int] = [65: 1, 67: 2, 71: 4, 84: 8, 82: 5, 89: 10, 83: 6, 87: 9, 75: 12, 77: 3, 66: 14, 68: 13, 72: 11, 86: 7, 78: 15, 45: 15]
struct FastaRecord { let headerLine: Int; let name: String; let sequence: [UInt8] }
func readFASTA() throws -> [FastaRecord] {
    let lines = try String(contentsOfFile: "input/alignment.fasta", encoding: .ascii).split(separator: "\n").map(String.init)
    var records: [FastaRecord] = [], name: String?, headerLine = 0, pieces: [UInt8] = []
    for (index, line) in lines.enumerated() { if line.first == ">" { if let name { records.append(FastaRecord(headerLine: headerLine, name: name, sequence: pieces)) }; name = String(line.dropFirst().split(separator: " ", maxSplits: 1)[0]); headerLine = index + 1; pieces = [] } else { pieces += line.utf8.map { (97...122).contains($0) ? $0 - 32 : $0 } } }
    records.append(FastaRecord(headerLine: headerLine, name: name!, sequence: pieces))
    return records
}
struct Patterns {
    let patterns: [String]
    let columns: [Int]
    let weights: [Int]
    let encoded: [[Int]]
    init(_ sequences: [[UInt8]]) { var patterns: [String] = [], columns: [Int] = [], weights: [Int] = [], numbers: [String: Int] = [:], encoded: [[Int]] = []; for column in sequences[0].indices { let characters = sequences.map { $0[column] }, pattern = String(decoding: characters, as: UTF8.self), number: Int; if let previous = numbers[pattern] { number = previous } else { number = patterns.count; numbers[pattern] = number; patterns.append(pattern); weights.append(0); encoded.append(characters.map { baseSets[$0]! }) }; columns.append(number); weights[number] += 1 }; self.patterns = patterns; self.columns = columns; self.weights = weights; self.encoded = encoded }
}
struct ColumnClasses { var constant = 0; var variable = 0; var informative = 0; var gapped = 0; var empty = 0 }
func classifyColumns(_ sequences: [[UInt8]]) -> ColumnClasses { var result = ColumnClasses(); for column in sequences[0].indices { var counts: [UInt8: Int] = [:], gap = false; for sequence in sequences { let character = sequence[column]; if baseSymbols.contains(character) { counts[character, default: 0] += 1 }; if character == 45 { gap = true } }; if counts.isEmpty { result.empty += 1 } else if counts.count == 1 { result.constant += 1 } else { result.variable += 1 }; if counts.values.filter({ $0 >= 2 }).count >= 2 { result.informative += 1 }; if gap { result.gapped += 1 } }; return result }
