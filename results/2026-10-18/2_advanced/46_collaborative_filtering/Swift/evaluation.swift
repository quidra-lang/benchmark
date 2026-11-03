import Foundation

func sequentialSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var total = 0.0
    for value in values { total = total + value }
    return total
}

func clip(_ value: Double) -> Double { value < 1 ? 1 : value > 5 ? 5 : value }
func rmse(_ errors: [Double]) -> Double? { errors.isEmpty ? nil : sqrt(sequentialSum(errors.map { $0 * $0 }) / Double(errors.count)) }
func mae(_ errors: [Double]) -> Double? { errors.isEmpty ? nil : sequentialSum(errors.map { abs($0) }) / Double(errors.count) }

func trainingRMSE(_ training: [Rating], _ predict: (Int, Int) -> Double) -> Double {
    let squared = training.map { row -> Double in let error = Double(row.rating) - predict(row.user, row.item); return error * error }
    return sqrt(sequentialSum(squared) / Double(training.count))
}

func rankWeight(_ rank: Int) -> Double { 1 / log2(Double(rank + 1)) }

struct RankingMetrics {
    let hits: Int
    let recall: Double
    let ndcg: Double
    let averagePrecision: Double
    let reciprocalRank: Double
}

func rankingMetrics(_ ranked: [Int], _ relevant: Set<Int>, _ cutoff: Int) -> RankingMetrics {
    var hits = 0
    var dcg = 0.0, averagePrecision = 0.0, reciprocalRank = 0.0
    for (index, item) in ranked.prefix(cutoff).enumerated() where relevant.contains(item) {
        let rank = index + 1
        hits += 1
        dcg = dcg + rankWeight(rank)
        averagePrecision = averagePrecision + Double(hits) / Double(rank)
        if reciprocalRank == 0 { reciprocalRank = 1 / Double(rank) }
    }
    let idealHits = min(cutoff, relevant.count)
    let idealDCG = sequentialSum((1...idealHits).map(rankWeight))
    return RankingMetrics(hits: hits, recall: Double(hits) / Double(relevant.count), ndcg: dcg / idealDCG,
                          averagePrecision: averagePrecision / Double(idealHits), reciprocalRank: reciprocalRank)
}
