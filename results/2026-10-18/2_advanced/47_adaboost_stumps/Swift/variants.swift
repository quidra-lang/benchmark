import Foundation

func updateWeights(_ rows: [Row], _ weights: [Double], _ stump: Stump) -> [Double] {
    let updated = rows.indices.map { weights[$0] * exp(-Double(rows[$0].label) * stump.output(rows[$0].values)) }
    let normalizer = orderedSum(updated)
    return updated.map { $0 / normalizer }
}

func trainReal(_ rows: [Row], _ maxRounds: Int, _ bins: Int, _ smoothing: Double, _ convergence: Double) -> Model {
    let geometry = RealGeometry(SearchSpace(rows), bins), labels = rows.map { $0.label }
    var weights = Array(repeating: 1 / Double(rows.count), count: rows.count)
    var rounds: [BoostRound] = [], bound = 1.0, stop = "completed"
    for _ in 0..<maxRounds {
        let candidate = realSearch(geometry, labels, weights, bins), z = candidate.normalizer
        if z >= 1 - convergence { stop = "converged"; break }
        let values = (0..<bins).map { 0.5 * log((candidate.positive[$0] + smoothing) / (candidate.negative[$0] + smoothing)) }
        let stump = Stump(feature: candidate.feature, thresholds: geometry.cuts[candidate.feature], values: values)
        bound = bound * z
        rounds.append(BoostRound(stump: stump, weights: weights, z: z, bound: bound))
        weights = updateWeights(rows, weights, stump)
    }
    return Model(rounds: rounds, stop: stop, cuts: geometry.cuts)
}

func trainGentle(_ rows: [Row], _ maxRounds: Int) -> Model {
    let space = SearchSpace(rows), targets = rows.map { Double($0.label) }
    var weights = Array(repeating: 1 / Double(rows.count), count: rows.count), rounds: [BoostRound] = []
    for _ in 0..<maxRounds {
        let candidate = regressionSearch(space, targets, weights)
        rounds.append(BoostRound(stump: candidate.stump, weights: weights, error: candidate.error))
        weights = updateWeights(rows, weights, candidate.stump)
    }
    return Model(rounds: rounds, stop: "completed")
}

func trainLogit(_ rows: [Row], _ maxRounds: Int, _ clip: Double) -> Model {
    let space = SearchSpace(rows), targets = rows.map { $0.label == 1 ? 1.0 : 0.0 }
    var scores = Array(repeating: 0.0, count: rows.count), probabilities = Array(repeating: 0.5, count: rows.count)
    var rounds: [BoostRound] = []
    for _ in 0..<maxRounds {
        let workingWeights = probabilities.map { $0 * (1 - $0) }
        let responses = rows.indices.map { i -> Double in
            let response = (targets[i] - probabilities[i]) / workingWeights[i]
            return response > clip ? clip : response < -clip ? -clip : response
        }
        let normalizer = orderedSum(workingWeights), weights = workingWeights.map { $0 / normalizer }
        let candidate = regressionSearch(space, responses, weights)
        let stump = Stump(feature: candidate.stump.feature, thresholds: candidate.stump.thresholds, values: candidate.stump.values.map { $0 / 2 })
        for i in rows.indices { scores[i] = scores[i] + stump.output(rows[i].values); probabilities[i] = 1 / (1 + exp(-2 * scores[i])) }
        let loss = orderedSum(rows.indices.map { log(1 + exp(-2 * Double(rows[$0].label) * scores[$0])) }) / Double(rows.count)
        rounds.append(BoostRound(stump: stump, weights: weights, error: candidate.error, loss: loss))
    }
    return Model(rounds: rounds, stop: "completed")
}
