import Foundation

struct Mixture {
    let weights: [Double]
    let means: [Vector2]
    let covariances: [Covariance]
    let type: CovarianceKind
    var count: Int { weights.count }
}
struct Posterior { let probabilities: [Double]; let logDensity: Double; let scores: [Double] }
struct Expectation { let records: [Posterior]; let logLikelihood: Double }
struct EMFit {
    let model: Mixture
    let records: [Posterior]
    let trace: [Double]
    let settledAt: Int
    let largestIteration: Int
    let largestIncrease: Double
    let violations: [Int]
    var logLikelihood: Double { trace.last! }
}
func adjustInitial(_ initial: InitialValues, _ type: CovarianceKind) -> Mixture {
    var covariances = initial.covariances
    switch type {
    case .full: break
    case .diagonal: covariances = covariances.map { Covariance(a: $0.a, b: 0, c: $0.c) }
    case .spherical: covariances = covariances.map { let v = ($0.a + $0.c) / 2; return Covariance(a: v, b: 0, c: v) }
    case .tied:
        var a = 0.0, b = 0.0, c = 0.0
        for (index, value) in covariances.enumerated() { a += initial.weights[index] * value.a; b += initial.weights[index] * value.b; c += initial.weights[index] * value.c }
        covariances = Array(repeating: Covariance(a: a, b: b, c: c), count: initial.weights.count)
    }
    return Mixture(weights: initial.weights, means: initial.means, covariances: covariances, type: type)
}
func posterior(_ point: Vector2, _ model: Mixture) -> Posterior {
    let scores = (0..<model.count).map { weightedLogDensity(point, model.weights[$0], model.means[$0], model.covariances[$0]) }
    let maximum = scores.max()!, exponentials = scores.map { exp($0 - maximum) }, total = exponentials.reduce(0, +)
    return Posterior(probabilities: exponentials.map { $0 / total }, logDensity: maximum + log(total), scores: scores)
}
func expectation(_ points: [Observation], _ model: Mixture) -> Expectation {
    var records: [Posterior] = [], total = 0.0
    for point in points { let record = posterior(point.position, model); records.append(record); total += record.logDensity }
    return Expectation(records: records, logLikelihood: total)
}
func maximize(_ points: [Observation], _ records: [Posterior], _ type: CovarianceKind, _ epsilon: Double) -> Mixture {
    let count = records[0].probabilities.count, n = Double(points.count)
    var counts: [Double] = [], means: [Vector2] = [], scatter: [Covariance] = []
    for k in 0..<count {
        var size = 0.0, x = 0.0, y = 0.0
        for (i, point) in points.enumerated() { let r = records[i].probabilities[k]; size += r; x += r * point.position.x; y += r * point.position.y }
        counts.append(size); means.append(Vector2(x: x / size, y: y / size))
        var a = 0.0, b = 0.0, c = 0.0
        for (i, point) in points.enumerated() { let r = records[i].probabilities[k], dx = point.position.x - means[k].x, dy = point.position.y - means[k].y; a += r * dx * dx; b += r * dx * dy; c += r * dy * dy }
        scatter.append(Covariance(a: a, b: b, c: c))
    }
    var covariances: [Covariance] = []
    if type == .tied {
        let shared = Covariance(a: scatter.reduce(0) { $0 + $1.a } / n + epsilon, b: scatter.reduce(0) { $0 + $1.b } / n, c: scatter.reduce(0) { $0 + $1.c } / n + epsilon)
        covariances = Array(repeating: shared, count: count)
    } else {
        for k in 0..<count {
            let value = scatter[k], size = counts[k]
            if type == .spherical { let v = (value.a / size + value.c / size) / 2 + epsilon; covariances.append(Covariance(a: v, b: 0, c: v)) }
            else { covariances.append(Covariance(a: value.a / size + epsilon, b: type == .full ? value.b / size : 0, c: value.c / size + epsilon)) }
        }
    }
    return Mixture(weights: counts.map { $0 / n }, means: means, covariances: covariances, type: type)
}
func runEM(_ points: [Observation], _ initial: InitialValues, _ type: CovarianceKind, _ settings: Settings) -> EMFit {
    var model = adjustInitial(initial, type)
    var current = expectation(points, model)
    var trace = [current.logLikelihood]
    for _ in 0..<settings.iterations { model = maximize(points, current.records, type, settings.epsilon); current = expectation(points, model); trace.append(current.logLikelihood) }
    let final = trace.last!
    let settled = trace.indices.first { t in trace[t...].allSatisfy { abs($0 - final) <= settings.tolerance } }!
    var largest = 1, violations: [Int] = []
    for t in 1..<trace.count {
        if trace[t] - trace[t - 1] > trace[largest] - trace[largest - 1] { largest = t }
        if trace[t] < trace[t - 1] - 0.000001 * abs(trace[t - 1]) { violations.append(t) }
    }
    return EMFit(model: model, records: current.records, trace: trace, settledAt: settled, largestIteration: largest, largestIncrease: trace[largest] - trace[largest - 1], violations: violations)
}
