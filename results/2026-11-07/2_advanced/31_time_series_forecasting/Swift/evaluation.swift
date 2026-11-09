import Foundation

struct Accuracy {
    let me: Double
    let mae: Double
    let rmse: Double
    let mape: Double
    let smape: Double
    let mase: Double
}

func seasonalScale(_ values: [Double], _ season: Int) -> Double {
    total((season..<values.count).map { abs(values[$0] - values[$0 - season]) }) / Double(values.count - season)
}

func accuracy(_ actual: [Double], _ predicted: [Double], _ scale: Double) -> Accuracy {
    let count = Double(actual.count)
    let errors = actual.indices.map { actual[$0] - predicted[$0] }
    let mae = total(errors.map { abs($0) }) / count
    let mape = 100 * total(errors.indices.map { abs(errors[$0]) / actual[$0] }) / count
    let smape = 100 * total(errors.indices.map {
        2 * abs(errors[$0]) / (abs(actual[$0]) + abs(predicted[$0]))
    }) / count
    return Accuracy(
        me: total(errors) / count, mae: mae, rmse: sqrt(total(errors.map { $0 * $0 }) / count),
        mape: mape, smape: smape, mase: mae / scale
    )
}

func winkler(_ actual: Double, _ low: Double, _ high: Double, _ multiplier: Double) -> Double {
    if actual < low {
        return high - low + multiplier * (low - actual)
    }
    if actual > high {
        return high - low + multiplier * (actual - high)
    }
    return high - low
}

func rankModels(_ scores: [Double]) -> [Int] {
    scores.indices.sorted { a, b in scores[a] == scores[b] ? a < b : scores[a] < scores[b] }
}
