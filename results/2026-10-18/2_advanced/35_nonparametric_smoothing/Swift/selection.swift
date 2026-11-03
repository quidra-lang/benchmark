func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var result = 0.0
    for value in values { result += value }
    return result
}

func crossValidationScore(_ observed: [Double], _ predicted: [Double?]) -> Double? {
    var total = 0.0
    for i in observed.indices {
        guard let estimate = predicted[i] else { return nil }
        let error = observed[i] - estimate
        total += error * error
    }
    return total / Double(observed.count)
}

func generalizedScore(_ observed: [Double], _ fitted: [Double], _ edf: Double) -> Double {
    let rss = orderedSum(observed.indices.map { (observed[$0] - fitted[$0]) * (observed[$0] - fitted[$0]) })
    let factor = 1 - edf / Double(observed.count)
    return rss / Double(observed.count) / (factor * factor)
}

func chooseCandidate(_ scores: [Double?]) -> Int {
    var best: Int?
    for i in scores.indices {
        if let score = scores[i], best == nil || score < scores[best!]! { best = i }
    }
    return best!
}
