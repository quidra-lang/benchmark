import Foundation

struct TrainingCounts {
    let classCount: Int
    let vocabularySize: Int
    let documentTotal: Int
    let documents: [Int]
    let occurrences: [[Int]]
    let containing: [[Int]]
    let totals: [Int]
    let total: Int
    let termTotals: [Int]
    init(_ sequences: [[Int]], _ labels: [Int], _ classCount: Int, _ vocabularySize: Int) {
        var documents = Array(repeating: 0, count: classCount)
        var occurrences = Array(repeating: Array(repeating: 0, count: vocabularySize), count: classCount)
        var containing = occurrences
        for (sequence, label) in zip(sequences, labels) {
            documents[label] += 1
            for term in sequence { occurrences[label][term] += 1 }
            for term in firstOccurrences(sequence) { containing[label][term] += 1 }
        }
        let totals = occurrences.map { $0.reduce(0, +) }
        let termTotals = (0..<vocabularySize).map { term in occurrences.reduce(0) { $0 + $1[term] } }
        self.classCount = classCount; self.vocabularySize = vocabularySize; documentTotal = sequences.count
        self.documents = documents; self.occurrences = occurrences; self.containing = containing
        self.totals = totals; total = totals.reduce(0, +); self.termTotals = termTotals
    }
}
struct Prediction {
    let label: Int
    let score: Double
    let ranking: [Int]
    let scores: [Double]
    let probabilities: [Double]
    let normalizer: Double
    let margin: Double
    static func posterior(_ scores: [Double]) -> Prediction {
        let ranking = scores.indices.sorted { scores[$0] == scores[$1] ? $0 < $1 : scores[$0] > scores[$1] }
        let label = ranking[0], best = scores[label]
        let exponentials = scores.map { exp($0 - best) }
        var normalizer = 0.0
        for value in exponentials { normalizer += value }
        let probabilities = exponentials.map { $0 / normalizer }
        return Prediction(label: label, score: probabilities[label], ranking: ranking, scores: scores, probabilities: probabilities, normalizer: normalizer, margin: best - scores[ranking[1]])
    }
}
func smoothedLog(_ count: Int, _ total: Int, _ alpha: Int, _ outcomes: Int) -> Double { log(Double(100 * count + alpha) / Double(100 * total + alpha * outcomes)) }
struct NaiveBayes {
    let kind: Int
    let priors: [Double]
    let base: [Double]
    let weights: [[Double]]
    static func train(_ kind: Int, _ counts: TrainingCounts, _ alpha: Int) -> NaiveBayes {
        let priors = counts.documents.map { log(Double($0) / Double(counts.documentTotal)) }
        var base = Array(repeating: 0.0, count: counts.classCount)
        var weights = Array(repeating: Array(repeating: 0.0, count: counts.vocabularySize), count: counts.classCount)
        for label in 0..<counts.classCount {
            for term in 0..<counts.vocabularySize {
                if kind == 0 { weights[label][term] = smoothedLog(counts.occurrences[label][term], counts.totals[label], alpha, counts.vocabularySize) }
                else if kind == 1 {
                    let present = smoothedLog(counts.containing[label][term], counts.documents[label], alpha, 2)
                    let absent = smoothedLog(counts.documents[label] - counts.containing[label][term], counts.documents[label], alpha, 2)
                    base[label] += absent; weights[label][term] = present - absent
                } else { weights[label][term] = -smoothedLog(counts.termTotals[term] - counts.occurrences[label][term], counts.total - counts.totals[label], alpha, counts.vocabularySize) }
            }
        }
        return NaiveBayes(kind: kind, priors: priors, base: base, weights: weights)
    }
    func predict(_ sequence: [Int]) -> Prediction {
        let terms = kind == 1 ? firstOccurrences(sequence) : sequence
        var scores: [Double] = []
        for label in priors.indices {
            var score = base[label]
            for term in terms { score += weights[label][term] }
            scores.append(score + priors[label])
        }
        return .posterior(scores)
    }
}
