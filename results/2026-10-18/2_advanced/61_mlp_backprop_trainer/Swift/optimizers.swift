import Foundation

struct OptimizerState {
    var momentum: [Double]
    var first: [Double]
    var second: [Double]
    var power1 = 1.0
    var power2 = 1.0
    init(_ count: Int) { momentum = Array(repeating: 0, count: count); first = momentum; second = momentum }
    mutating func update(_ theta: inout [Double], _ gradient: [Double], _ kind: OptimizerKind, _ rate: Double) {
        switch kind {
        case .sgd: for i in theta.indices { theta[i] -= rate * gradient[i] }
        case .momentum(let mu): for i in theta.indices { momentum[i] = mu * momentum[i] + gradient[i]; theta[i] -= rate * momentum[i] }
        case .adam(let beta1, let beta2, let epsilon):
            power1 *= beta1; power2 *= beta2
            for i in theta.indices { let value = gradient[i]; first[i] = beta1 * first[i] + (1 - beta1) * value; second[i] = beta2 * second[i] + (1 - beta2) * value * value; let correctedFirst = first[i] / (1 - power1), correctedSecond = second[i] / (1 - power2); theta[i] -= rate * correctedFirst / (sqrt(correctedSecond) + epsilon) }
        }
    }
}
func epochRate(_ definition: RunDefinition, _ epoch: Int, _ settings: Settings) -> Double { var rate = definition.rate; for _ in 0..<((epoch - 1) / settings.rateStep) { rate *= settings.rateGamma }; return rate }
