import Foundation

func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var result = 0.0
    for value in values { result = result + value }
    return result
}

struct Stump {
    let feature: Int
    let thresholds: [Double]
    let values: [Double]
    func output(_ row: [Double]) -> Double { values[thresholds.filter { row[feature] > $0 }.count] }
}

struct SearchSpace {
    let rows: [Row]
    let orders: [[Int]]
    let groups: [[[Int]]]
    let thresholds: [[Double]]

    init(_ rows: [Row]) {
        var orders: [[Int]] = [], groups: [[[Int]]] = [], thresholds: [[Double]] = []
        for feature in rows[0].values.indices {
            let order = rows.indices.sorted { rows[$0].values[feature] == rows[$1].values[feature] ? $0 < $1 : rows[$0].values[feature] < rows[$1].values[feature] }
            var featureGroups: [[Int]] = [], distinct: [Double] = []
            for index in order {
                let value = rows[index].values[feature]
                if distinct.last != value { distinct.append(value); featureGroups.append([]) }
                featureGroups[featureGroups.count - 1].append(index)
            }
            let cuts = [distinct[0] - 1] + (1..<distinct.count).map { (distinct[$0 - 1] + distinct[$0]) / 2 }
            orders.append(order)
            groups.append(featureGroups)
            thresholds.append(cuts)
        }
        self.rows = rows
        self.orders = orders
        self.groups = groups
        self.thresholds = thresholds
    }
}

func leftCumulative(_ groups: [[Int]], _ values: [Double]) -> [Double] {
    var total = 0.0, result = [0.0]
    for group in groups.dropLast() {
        for index in group { total = total + values[index] }
        result.append(total)
    }
    return result
}

func choose<T>(_ candidates: [T], value: (T) -> Double) -> T {
    let minimum = candidates.map(value).min()!
    return candidates.first { value($0) <= minimum + 1e-9 }!
}

struct StumpCandidate {
    let stump: Stump
    let error: Double
    var polarity = 0
}

func discreteSearch(_ space: SearchSpace, _ labels: [Int], _ weights: [Double]) -> StumpCandidate {
    let positives = labels.indices.map { labels[$0] == 1 ? weights[$0] : 0 }, negatives = labels.indices.map { labels[$0] == -1 ? weights[$0] : 0 }
    let positiveTotal = orderedSum(positives), negativeTotal = orderedSum(negatives)
    var candidates: [StumpCandidate] = []
    for feature in space.thresholds.indices {
        let leftPositive = leftCumulative(space.groups[feature], positives), leftNegative = leftCumulative(space.groups[feature], negatives)
        for (index, threshold) in space.thresholds[feature].enumerated() {
            candidates.append(StumpCandidate(stump: Stump(feature: feature, thresholds: [threshold], values: [-1, 1]), error: leftPositive[index] + (negativeTotal - leftNegative[index]), polarity: 1))
            candidates.append(StumpCandidate(stump: Stump(feature: feature, thresholds: [threshold], values: [1, -1]), error: leftNegative[index] + (positiveTotal - leftPositive[index]), polarity: -1))
        }
    }
    return choose(candidates) { $0.error }
}

func regressionSearch(_ space: SearchSpace, _ targets: [Double], _ weights: [Double]) -> StumpCandidate {
    let totalWeight = orderedSum(weights), products = weights.indices.map { weights[$0] * targets[$0] }
    let totalTarget = orderedSum(products), totalSquare = orderedSum(weights.indices.map { weights[$0] * targets[$0] * targets[$0] })
    var candidates: [StumpCandidate] = []
    for feature in space.thresholds.indices {
        let leftWeights = leftCumulative(space.groups[feature], weights), leftTargets = leftCumulative(space.groups[feature], products)
        for (position, threshold) in space.thresholds[feature].enumerated() {
            let leftWeight = leftWeights[position], leftTarget = leftTargets[position]
            let rightWeight = totalWeight - leftWeight, rightTarget = totalTarget - leftTarget
            let left = position == 0 ? 0 : leftTarget / leftWeight, right = rightTarget / rightWeight
            let gain = position == 0 ? rightTarget * rightTarget / rightWeight : leftTarget * leftTarget / leftWeight + rightTarget * rightTarget / rightWeight
            candidates.append(StumpCandidate(stump: Stump(feature: feature, thresholds: [threshold], values: [left, right]), error: totalSquare - gain))
        }
    }
    return choose(candidates) { $0.error }
}

func firstMaximum(_ values: [Double]) -> Int {
    var best = 0
    for index in values.indices.dropFirst() where values[index] > values[best] { best = index }
    return best
}

func multiclassSearch(_ space: SearchSpace, _ labels: [Int], _ weights: [Double], _ classes: Int) -> StumpCandidate {
    let totalWeight = orderedSum(weights)
    let totals = (1...classes).map { c in orderedSum(labels.indices.filter { labels[$0] == c }.map { weights[$0] }) }
    var candidates: [StumpCandidate] = []
    for feature in space.thresholds.indices {
        var left = Array(repeating: 0.0, count: classes)
        for (position, threshold) in space.thresholds[feature].enumerated() {
            if position > 0 { for index in space.groups[feature][position - 1] { left[labels[index] - 1] = left[labels[index] - 1] + weights[index] } }
            let right = (0..<classes).map { totals[$0] - left[$0] }
            let a = firstMaximum(left), b = firstMaximum(right)
            let stump = Stump(feature: feature, thresholds: [threshold], values: [Double(a + 1), Double(b + 1)])
            candidates.append(StumpCandidate(stump: stump, error: totalWeight - (left[a] + right[b])))
        }
    }
    return choose(candidates) { $0.error }
}

struct RealGeometry {
    let cuts: [[Double]]
    let assignments: [[Int]]

    init(_ space: SearchSpace, _ bins: Int) {
        var cuts: [[Double]] = [], assignments: [[Int]] = []
        for feature in space.orders.indices {
            let sorted = space.orders[feature].map { space.rows[$0].values[feature] }
            let featureCuts = (1..<bins).map { b -> Double in let rank = b * sorted.count / bins; return (sorted[rank - 1] + sorted[rank]) / 2 }
            cuts.append(featureCuts)
            assignments.append(space.rows.map { row in featureCuts.filter { row.values[feature] > $0 }.count })
        }
        self.cuts = cuts
        self.assignments = assignments
    }
}

struct RealCandidate {
    let feature: Int
    let positive: [Double]
    let negative: [Double]
    let normalizer: Double
}

func realSearch(_ geometry: RealGeometry, _ labels: [Int], _ weights: [Double], _ bins: Int) -> RealCandidate {
    let candidates = geometry.assignments.enumerated().map { feature, memberships -> RealCandidate in
        var positive = Array(repeating: 0.0, count: bins), negative = positive
        for index in labels.indices {
            let bin = memberships[index]
            if labels[index] == 1 { positive[bin] = positive[bin] + weights[index] } else { negative[bin] = negative[bin] + weights[index] }
        }
        let normalizer = 2 * orderedSum((0..<bins).map { sqrt(positive[$0] * negative[$0]) })
        return RealCandidate(feature: feature, positive: positive, negative: negative, normalizer: normalizer)
    }
    return choose(candidates) { $0.normalizer }
}
