func total<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var result = 0.0
    for value in values {
        result += value
    }
    return result
}

func mean(_ values: [Double]) -> Double {
    total(values) / Double(values.count)
}

func sampleVariance(_ values: [Double]) -> Double {
    let average = mean(values)
    return total(values.map { ($0 - average) * ($0 - average) }) / Double(values.count - 1)
}

struct Decomposition {
    let trend: [Double?]
    let additive: [Double]
    let multiplicative: [Double]
    let residualAdd: [Double?]
    let residualMult: [Double?]
    let defined: [Int]
}

func decompose(_ values: [Double], _ season: Int) -> Decomposition {
    let count = values.count
    let half = season / 2
    let defined = Array(half..<(count - half))
    var trend = [Double?](repeating: nil, count: count)
    for t in defined {
        var value = 0.5 * values[t - half]
        for i in (t - half + 1)..<(t + half) {
            value += values[i]
        }
        value += 0.5 * values[t + half]
        trend[t] = value / Double(season)
    }
    var additive: [Double] = []
    var multiplicative: [Double] = []
    for position in 0..<season {
        let times = defined.filter { $0 % season == position }
        additive.append(total(times.map { values[$0] - trend[$0]! }) / Double(times.count))
        multiplicative.append(total(times.map { values[$0] / trend[$0]! }) / Double(times.count))
    }
    let averageAdd = mean(additive)
    let averageMult = mean(multiplicative)
    for j in 0..<season {
        additive[j] -= averageAdd
        multiplicative[j] /= averageMult
    }
    var residualAdd = [Double?](repeating: nil, count: count)
    var residualMult = [Double?](repeating: nil, count: count)
    for t in defined {
        residualAdd[t] = values[t] - trend[t]! - additive[t % season]
        residualMult[t] = values[t] / (trend[t]! * multiplicative[t % season])
    }
    return Decomposition(
        trend: trend, additive: additive, multiplicative: multiplicative,
        residualAdd: residualAdd, residualMult: residualMult, defined: defined
    )
}

func leastSquaresLine(_ values: [Double]) -> (Double, Double) {
    let center = Double(values.count + 1) / 2
    let average = mean(values)
    let numerator = total(values.enumerated().map { (Double($0.offset + 1) - center) * ($0.element - average) })
    let denominator = total(values.indices.map { (Double($0 + 1) - center) * (Double($0 + 1) - center) })
    let slope = numerator / denominator
    return (average - slope * center, slope)
}
