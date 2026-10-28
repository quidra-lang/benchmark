import Foundation

struct IMM {
    var models: [Kalman]
    let transition: Matrix
    var probabilities: [Double]
    init(_ densities: [Double], _ transition: Matrix, _ probabilities: [Double], _ sigma: Double, _ velocityVariance: Double, _ measurement: [Double]) { models = densities.map { Kalman(.cv, $0, sigma, velocityVariance, 0, measurement) }; self.transition = transition; self.probabilities = probabilities }
    mutating func step(_ interval: Double, _ measurement: [Double]?) {
        let mu = probabilities, predicted = (0..<2).map { transition[0][$0] * mu[0] + transition[1][$0] * mu[1] }, oldStates = models.map { $0.state }, oldCovariances = models.map { $0.covariance }
        var likelihoods: [Double] = []
        for j in 0..<2 {
            let w0 = transition[0][j] * mu[0] / predicted[j], w1 = transition[1][j] * mu[1] / predicted[j], mixed = (0..<4).map { w0 * oldStates[0][$0] + w1 * oldStates[1][$0] }
            let covariance = (0..<4).map { r in (0..<4).map { s in w0 * (oldCovariances[0][r][s] + (oldStates[0][r] - mixed[r]) * (oldStates[0][s] - mixed[s])) + w1 * (oldCovariances[1][r][s] + (oldStates[1][r] - mixed[r]) * (oldStates[1][s] - mixed[s])) } }
            models[j].state = mixed; models[j].covariance = covariance; models[j].predict(interval)
            var likelihood = 1.0
            if let measurement { let result = models[j].update(measurement); likelihood = exp(-result.distanceSquared / 2) / (2 * Double.pi * sqrt(determinant2(result.covariance))) }
            likelihoods.append(likelihood)
        }
        let denominator = likelihoods[0] * predicted[0] + likelihoods[1] * predicted[1]
        probabilities = (0..<2).map { likelihoods[$0] * predicted[$0] / denominator }
    }
    func estimate() -> [Double] { (0..<4).map { probabilities[0] * models[0].state[$0] + probabilities[1] * models[1].state[$0] } }
}
