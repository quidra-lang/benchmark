import Foundation

let differenceKinds = ["none", "first", "seasonal", "both"]

func difference(_ values: [Double], _ season: Int, _ kind: Int) -> ([Double], Int) {
    switch kind {
    case 0:
        return (values, 0)
    case 1:
        return ((1..<values.count).map { values[$0] - values[$0 - 1] }, 1)
    case 2:
        return ((season..<values.count).map { values[$0] - values[$0 - season] }, season)
    default:
        return (((season + 1)..<values.count).map {
            (values[$0] - values[$0 - 1]) - (values[$0 - season] - values[$0 - season - 1])
        }, season + 1)
    }
}

func autocorrelation(_ values: [Double], _ maxLag: Int) -> (Double, Double, [Double]) {
    let average = mean(values)
    let centered = values.map { $0 - average }
    let count = values.count
    let variance = total(centered.map { $0 * $0 }) / Double(count)
    var correlations = [1.0]
    if maxLag > 0 {
        for lag in 1...maxLag {
            let numerator = total((0..<(count - lag)).map { centered[$0] * centered[$0 + lag] })
            correlations.append(numerator / Double(count) / variance)
        }
    }
    return (average, variance, correlations)
}

struct DurbinLevinson {
    let coefficients: [[Double]]
    let partial: [Double]
    let variances: [Double]
}

func durbinLevinson(_ correlations: [Double]) -> DurbinLevinson {
    var coefficients: [[Double]] = [[]]
    var partial = [0.0]
    var variances = [1.0]
    for order in 1..<correlations.count {
        let previous = coefficients[order - 1]
        let correction = total((1..<order).map { previous[$0 - 1] * correlations[order - $0] })
        let theta = (correlations[order] - correction) / variances[order - 1]
        var current = (1..<order).map { previous[$0 - 1] - theta * previous[order - $0 - 1] }
        current.append(theta)
        coefficients.append(current)
        partial.append(theta)
        variances.append(variances[order - 1] * (1 - theta * theta))
    }
    return DurbinLevinson(coefficients: coefficients, partial: partial, variances: variances)
}

func arResiduals(_ values: [Double], _ average: Double, _ coefficients: [Double]) -> [Double] {
    let order = coefficients.count
    return (order..<values.count).map { i in
        let correction = total(coefficients.indices.map { j in
            coefficients[j] * (values[i - j - 1] - average)
        })
        return values[i] - average - correction
    }
}

func arForecast(
    _ values: [Double], _ differenced: [Double], _ offset: Int, _ kind: Int, _ average: Double,
    _ coefficients: [Double], _ origin: Int, _ steps: Int, _ season: Int
) -> [Double] {
    var transformed = Array(differenced.prefix(origin - offset))
    var extended = Array(values.prefix(origin))
    var result: [Double] = []
    for _ in 0..<steps {
        var predicted = average + total(coefficients.enumerated().map { pair in
            pair.element * (transformed[transformed.count - pair.offset - 1] - average)
        })
        transformed.append(predicted)
        let n = extended.count
        switch kind {
        case 1:
            predicted += extended[n - 1]
        case 2:
            predicted += extended[n - season]
        case 3:
            predicted = predicted + extended[n - 1] + extended[n - season] - extended[n - season - 1]
        default:
            break
        }
        extended.append(predicted)
        result.append(predicted)
    }
    return result
}

func ljungBox(_ errors: [Double], _ lags: [Int]) -> [(Int, Double, Double)] {
    let count = errors.count
    let (_, _, correlations) = autocorrelation(errors, lags.max()!)
    return lags.map { lag in
        let sum = total((1...lag).map { correlations[$0] * correlations[$0] / Double(count - $0) })
        let q = Double(count) * Double(count + 2) * sum
        let x = q / 2
        var term = 1.0
        var terms = term
        for i in 1..<(lag / 2) {
            term = term * x / Double(i)
            terms += term
        }
        return (lag, q, exp(-x) * terms)
    }
}
