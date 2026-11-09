import Foundation

enum ModelKind: String, CaseIterable {
    case nb = "NB", lda = "LDA", qda = "QDA"
}

func argmax(_ values: [Double]) -> Int {
    var best = 0
    for index in values.indices.dropFirst() where values[index] > values[best] { best = index }
    return best
}

func argmin(_ values: [Double]) -> Int {
    var best = 0
    for index in values.indices.dropFirst() where values[index] < values[best] { best = index }
    return best
}

struct Statistics {
    let rowCount: Int
    let featureCount: Int
    let counts: [Int]
    let means: [[Double]]
    let scatter: [Matrix]
    let center: [Double]
    let variances: [Double]

    init(_ rows: [Row], _ features: [Int], _ classes: Int) {
        let vectors = rows.map { row in features.map { row.values[$0] } }
        var groups = Array(repeating: [[Double]](), count: classes)
        for (row, vector) in zip(rows, vectors) { groups[row.classIndex].append(vector) }
        let means = groups.map { group in features.indices.map { index in orderedSum(group.map { $0[index] }) / Double(group.count) } }
        let scatter = groups.indices.map { group -> Matrix in
            features.indices.map { a in features.indices.map { b in
                orderedSum(groups[group].map { ($0[a] - means[group][a]) * ($0[b] - means[group][b]) })
            } }
        }
        let center = features.indices.map { index in orderedSum(vectors.map { $0[index] }) / Double(rows.count) }
        let variances = features.indices.map { index in
            orderedSum(vectors.map { ($0[index] - center[index]) * ($0[index] - center[index]) }) / Double(rows.count)
        }
        rowCount = rows.count
        featureCount = features.count
        counts = groups.map { $0.count }
        self.means = means
        self.scatter = scatter
        self.center = center
        self.variances = variances
    }

    func pooledCovariance() -> Matrix {
        (0..<featureCount).map { a in (0..<featureCount).map { b in
            orderedSum(scatter.map { $0[a][b] }) / Double(rowCount - counts.count)
        } }
    }
}

struct Prediction {
    let predicted: Int
    let posterior: [Double]
    let logPosterior: [Double]
    let confidence: Double
    let decision: Int
}

struct GaussianModel {
    let kind: ModelKind
    let features: [Int]
    let statistics: Statistics
    let epsilon: Double
    let gamma: Double
    let priors: [Double]
    let maximumVariance: Double
    let addedVariance: Double
    let covariances: [Matrix]
    let factors: [Matrix]
    let logDeterminants: [Double]
    let logPriors: [Double]
    let normalizer: Double
    var means: [[Double]] { statistics.means }

    init(_ rows: [Row], features: [Int], classes: Int, kind: ModelKind, prior: String, epsilon: Double, gamma: Double) {
        let statistics = Statistics(rows, features, classes)
        let priors = prior == "empirical" ? statistics.counts.map { Double($0) / Double(rows.count) }
            : Array(repeating: 1 / Double(classes), count: classes)
        let maximumVariance = statistics.variances.max()!
        let addedVariance = epsilon * maximumVariance
        let covariances: [Matrix]
        if kind == .lda { covariances = Array(repeating: statistics.pooledCovariance(), count: classes) }
        else {
            covariances = (0..<classes).map { group in
                features.indices.map { a in features.indices.map { b in
                    if kind == .nb { return a == b ? statistics.scatter[group][a][b] / Double(statistics.counts[group]) + addedVariance : 0 }
                    let value = statistics.scatter[group][a][b] / Double(statistics.counts[group] - 1)
                    return a == b ? value : value * (1 - gamma)
                } }
            }
        }
        let factors: [Matrix]
        if kind == .lda { factors = Array(repeating: cholesky(covariances[0]), count: classes) }
        else { factors = covariances.map(cholesky) }
        self.kind = kind
        self.features = features
        self.statistics = statistics
        self.epsilon = epsilon
        self.gamma = gamma
        self.priors = priors
        self.maximumVariance = maximumVariance
        self.addedVariance = addedVariance
        self.covariances = covariances
        self.factors = factors
        logDeterminants = factors.map(logDeterminant)
        logPriors = priors.map(log)
        normalizer = Double(features.count) * log(2 * Double.pi) / 2
    }

    func vector(_ values: [Double]) -> [Double] { features.map { values[$0] } }

    func squaredDistances(_ vector: [Double]) -> [Double] {
        means.indices.map { group in quadraticForm(factors[group], vector.indices.map { vector[$0] - means[group][$0] }) }
    }

    func distances(_ values: [Double]) -> [Double] { squaredDistances(vector(values)) }

    func scores(_ vector: [Double]) -> [Double] {
        let distances = squaredDistances(vector)
        return means.indices.map { logPriors[$0] - normalizer - logDeterminants[$0] / 2 - distances[$0] / 2 }
    }

    func predictVector(_ vector: [Double]) -> Int { argmax(scores(vector)) }
    func predict(_ values: [Double]) -> Int { predictVector(vector(values)) }

    func inferVector(_ vector: [Double], costs: Matrix? = nil) -> Prediction {
        let scores = self.scores(vector)
        let predicted = argmax(scores)
        let maximum = scores[predicted]
        let exponentials = scores.map { exp($0 - maximum) }
        let total = orderedSum(exponentials)
        let probabilities = exponentials.map { $0 / total }
        let logTotal = log(total)
        let logProbabilities = scores.map { ($0 - maximum) - logTotal }
        let decision: Int
        if let costs {
            let risks = means.indices.map { target in orderedSum(means.indices.map { probabilities[$0] * costs[$0][target] }) }
            decision = argmin(risks)
        } else { decision = predicted }
        return Prediction(predicted: predicted, posterior: probabilities, logPosterior: logProbabilities,
                           confidence: probabilities.max()!, decision: decision)
    }

    func infer(_ values: [Double], costs: Matrix? = nil) -> Prediction { inferVector(vector(values), costs: costs) }
}
