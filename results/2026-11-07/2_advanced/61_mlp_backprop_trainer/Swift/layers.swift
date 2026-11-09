import Foundation

enum Activation: String { case tanh = "TANH", sigmoid = "SIGMOID", relu = "RELU", softmax = "SOFTMAX" }
struct LayerDefinition { let units: Int; let activation: Activation }
func hiddenActivation(_ kind: Activation, _ value: Double) -> Double { switch kind { case .tanh: return tanh(value); case .sigmoid: return 1 / (1 + exp(-value)); default: return value > 0 ? value : 0 } }
func hiddenDerivative(_ kind: Activation, _ z: Double, _ activated: Double) -> Double { switch kind { case .tanh: return 1 - activated * activated; case .sigmoid: return activated * (1 - activated); default: return z > 0 ? 1 : 0 } }
struct OutputValues { let scores: [Double]; let loss: Double; let error: [Double] }
func outputValues(_ kind: Activation, _ z: [Double], _ label: Int) -> OutputValues {
    if kind == .softmax {
        let maximum = z.max()!, terms = z.map { exp($0 - maximum) }
        var total = 0.0
        for term in terms { total += term }
        let scores = terms.map { $0 / total }, error = scores.indices.map { scores[$0] - ($0 == label ? 1 : 0) }
        return OutputValues(scores: scores, loss: log(total) - (z[label] - maximum), error: error)
    }
    let scores = z.map { 1 / (1 + exp(-$0)) }
    var loss = 0.0, error: [Double] = []
    for k in scores.indices { let residual = scores[k] - (k == label ? 1 : 0); loss += residual * residual; error.append(2 * residual * scores[k] * (1 - scores[k]) / Double(z.count)) }
    return OutputValues(scores: scores, loss: loss / Double(z.count), error: error)
}
func preactivations(_ weights: [[Double]], _ biases: [Double], _ activation: [Double]) -> [Double] { weights.indices.map { j in var total = 0.0; for i in activation.indices { total += weights[j][i] * activation[i] }; return total + biases[j] } }
func backwardSum(_ weights: [[Double]], _ errors: [Double]) -> [Double] { weights[0].indices.map { i in var total = 0.0; for j in errors.indices { total += weights[j][i] * errors[j] }; return total } }
