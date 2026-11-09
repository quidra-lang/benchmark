import Foundation

struct BoostRound {
    let stump: Stump
    var weights: [Double] = []
    var error: Double? = nil
    var alpha: Double? = nil
    var polarity: Int? = nil
    var z: Double? = nil
    var bound: Double? = nil
    var loss: Double? = nil
}

struct Model {
    let rounds: [BoostRound]
    let stop: String
    var cuts: [[Double]]? = nil
}

func trainDiscrete(_ rows: [Row], _ maxRounds: Int, weights initialWeights: [Double]? = nil, shrinkage: Double = 1, space suppliedSpace: SearchSpace? = nil) -> Model {
    let space = suppliedSpace ?? SearchSpace(rows), labels = rows.map { $0.label }
    var weights = initialWeights ?? Array(repeating: 1 / Double(rows.count), count: rows.count)
    var rounds: [BoostRound] = [], bound = 1.0, stop = "completed"
    for _ in 0..<maxRounds {
        let candidate = discreteSearch(space, labels, weights), e = candidate.error
        if e >= 0.5 { stop = "weak"; break }
        let alpha = e <= 1e-10 ? 1 : shrinkage * (0.5 * log((1 - e) / e))
        let stump = Stump(feature: candidate.stump.feature, thresholds: candidate.stump.thresholds, values: [-Double(candidate.polarity) * alpha, Double(candidate.polarity) * alpha])
        let before = weights
        let updated = rows.indices.map { i -> Double in
            if weights[i] == 0 { return 0 }
            let decision = rows[i].values[stump.feature] > stump.thresholds[0] ? candidate.polarity : -candidate.polarity
            return weights[i] * (decision == rows[i].label ? exp(-alpha) : exp(alpha))
        }
        let normalizer = orderedSum(updated)
        weights = updated.map { $0 / normalizer }
        bound = bound * normalizer
        rounds.append(BoostRound(stump: stump, weights: before, error: e, alpha: alpha, polarity: candidate.polarity, z: normalizer, bound: bound))
        if e <= 1e-10 { stop = "perfect"; break }
    }
    return Model(rounds: rounds, stop: stop)
}

func trainSAMME(_ rows: [Row], _ maxRounds: Int, _ classes: Int) -> Model {
    let space = SearchSpace(rows), labels = rows.map { $0.label }
    var weights = Array(repeating: 1 / Double(rows.count), count: rows.count)
    var rounds: [BoostRound] = [], stop = "completed"
    for _ in 0..<maxRounds {
        let candidate = multiclassSearch(space, labels, weights, classes), e = candidate.error
        if e >= Double(classes - 1) / Double(classes) { stop = "weak"; break }
        let alpha = e <= 1e-10 ? 1 : log((1 - e) / e) + log(Double(classes - 1))
        let updated = rows.indices.map { i in Int(candidate.stump.output(rows[i].values)) != rows[i].label ? weights[i] * exp(alpha) : weights[i] }
        let normalizer = orderedSum(updated)
        weights = updated.map { $0 / normalizer }
        rounds.append(BoostRound(stump: candidate.stump, error: e, alpha: alpha))
        if e <= 1e-10 { stop = "perfect"; break }
    }
    return Model(rounds: rounds, stop: stop)
}
