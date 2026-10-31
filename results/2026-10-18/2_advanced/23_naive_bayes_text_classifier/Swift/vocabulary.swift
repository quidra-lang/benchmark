import Foundation

func firstOccurrences(_ sequence: [Int]) -> [Int] {
    var seen = Set<Int>()
    return sequence.filter { seen.insert($0).inserted }
}
struct RankedTerm { let term: String; let frequency: Int; let score: Double; let bestClass: Int }
struct Vocabulary {
    let termCount: Int
    let candidateCount: Int
    let ranking: [RankedTerm]
    let terms: [String]
    let index: [String: Int]
    let frequencies: [Int]
    var size: Int { terms.count }
    init(_ sequences: [[String]], _ labels: [Int], _ classCount: Int, _ minDF: Int, _ size: Int) {
        var counts: [String: [Int]] = [:]
        var classSizes = Array(repeating: 0, count: classCount)
        for (sequence, label) in zip(sequences, labels) {
            classSizes[label] += 1
            for term in Set(sequence) { counts[term, default: Array(repeating: 0, count: classCount)][label] += 1 }
        }
        var ranking: [RankedTerm] = []
        let total = sequences.count
        for term in counts.keys.sorted() {
            let row = counts[term]!, frequency = row.reduce(0, +)
            if frequency < minDF { continue }
            var bestClass = 0, bestScore = -1.0
            for label in 0..<classCount {
                let a = row[label], b = frequency - a, c = classSizes[label] - a
                let e = total - classSizes[label] - b
                let difference = a * e - b * c
                let numerator = total * difference * difference
                let denominator = frequency * (total - frequency) * classSizes[label] * (total - classSizes[label])
                let score = denominator == 0 ? 0.0 : Double(numerator) / Double(denominator)
                if score > bestScore { bestScore = score; bestClass = label }
            }
            ranking.append(RankedTerm(term: term, frequency: frequency, score: bestScore, bestClass: bestClass))
        }
        let candidateCount = ranking.count
        ranking.sort { $0.score == $1.score ? $0.term < $1.term : $0.score > $1.score }
        if size > 0 && ranking.count > size { ranking = Array(ranking.prefix(size)) }
        let terms = ranking.map(\.term).sorted()
        let index = Dictionary(uniqueKeysWithValues: terms.enumerated().map { ($0.element, $0.offset) })
        var frequencies = Array(repeating: 0, count: terms.count)
        for entry in ranking { frequencies[index[entry.term]!] = entry.frequency }
        termCount = counts.count; self.candidateCount = candidateCount; self.ranking = ranking
        self.terms = terms; self.index = index; self.frequencies = frequencies
    }
    func encode(_ sequence: [String]) -> [Int] { sequence.compactMap { index[$0] } }
}
