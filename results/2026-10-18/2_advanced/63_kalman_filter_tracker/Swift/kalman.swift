import Foundation

enum MotionModel: String { case cv = "CV", ca = "CA" }
func transition(_ model: MotionModel, _ interval: Double) -> Matrix { var result = identity(model == .cv ? 4 : 6); result[0][2] = interval; result[1][3] = interval; if model == .ca { result[0][4] = interval * interval / 2; result[1][5] = interval * interval / 2; result[2][4] = interval; result[3][5] = interval }; return result }
func processNoise(_ model: MotionModel, _ t: Double, _ q: Double) -> Matrix {
    let entries: [(Int, Int, Double)] = model == .cv ? [(0, 0, q * t * t * t / 3), (0, 2, q * t * t / 2), (2, 2, q * t)] : [(0, 0, q * t * t * t * t * t / 20), (0, 2, q * t * t * t * t / 8), (0, 4, q * t * t * t / 6), (2, 2, q * t * t * t / 3), (2, 4, q * t * t / 2), (4, 4, q * t)]
    var result = zeros(model == .cv ? 4 : 6)
    for axis in 0..<2 { for (row, column, value) in entries { result[row + axis][column + axis] = value; result[column + axis][row + axis] = value } }
    return result
}
struct Innovation { let residual: [Double]; let covariance: Matrix; let precision: Matrix; let distanceSquared: Double }
struct UpdateResult { let distanceSquared: Double; let logLikelihood: Double; let covariance: Matrix }
struct FilterSnapshot { let state: [Double]; let covariance: Matrix; let predictedState: [Double]?; let predictedCovariance: Matrix?; let transition: Matrix? }
struct Kalman {
    let model: MotionModel
    let q: Double
    let measurementMatrix: Matrix
    let noise: Matrix
    var state: [Double]
    var covariance: Matrix
    var predictedState: [Double]?
    var predictedCovariance: Matrix?
    var transitionMatrix: Matrix?
    init(_ model: MotionModel, _ q: Double, _ sigma: Double, _ velocityVariance: Double, _ accelerationVariance: Double, _ measurement: [Double]) {
        let count = model == .cv ? 4 : 6
        var variances = [sigma * sigma, sigma * sigma, velocityVariance, velocityVariance], h = zeros(2, count)
        if model == .ca { variances += [accelerationVariance, accelerationVariance] }; h[0][0] = 1; h[1][1] = 1
        self.model = model; self.q = q; measurementMatrix = h; noise = diagonal([sigma * sigma, sigma * sigma]); state = measurement + Array(repeating: 0, count: count - 2); covariance = diagonal(variances)
    }
    mutating func predict(_ interval: Double) { let f = transition(model, interval); state = matrixVector(f, state); covariance = add(product(product(f, covariance), transpose(f)), processNoise(model, interval, q)); transitionMatrix = f; predictedState = state; predictedCovariance = covariance }
    func innovation(_ measurement: [Double]) -> Innovation { let residual = vectorSubtract(measurement, matrixVector(measurementMatrix, state)), s = add(product(product(measurementMatrix, covariance), transpose(measurementMatrix)), noise), precision = inverse(s); return Innovation(residual: residual, covariance: s, precision: precision, distanceSquared: quadratic2(residual, precision)) }
    @discardableResult mutating func update(_ measurement: [Double], _ prepared: Innovation? = nil) -> UpdateResult {
        let innovation = prepared ?? self.innovation(measurement), gain = product(product(covariance, transpose(measurementMatrix)), innovation.precision), correction = subtract(identity(state.count), product(gain, measurementMatrix))
        state = vectorAdd(state, matrixVector(gain, innovation.residual)); covariance = add(product(product(correction, covariance), transpose(correction)), product(product(gain, noise), transpose(gain)))
        return UpdateResult(distanceSquared: innovation.distanceSquared, logLikelihood: -log(2 * Double.pi) - log(determinant2(innovation.covariance)) / 2 - innovation.distanceSquared / 2, covariance: innovation.covariance)
    }
    func snapshot() -> FilterSnapshot { FilterSnapshot(state: state, covariance: covariance, predictedState: predictedState, predictedCovariance: predictedCovariance, transition: transitionMatrix) }
}
func smooth(_ history: [FilterSnapshot]) -> [[Double]] { var states = history.map { $0.state }; if history.count >= 2 { for index in stride(from: history.count - 2, through: 0, by: -1) { let current = history[index], following = history[index + 1], gain = product(product(current.covariance, transpose(following.transition!)), inverse(following.predictedCovariance!)), difference = vectorSubtract(states[index + 1], following.predictedState!); states[index] = vectorAdd(current.state, matrixVector(gain, difference)) } }; return states }
