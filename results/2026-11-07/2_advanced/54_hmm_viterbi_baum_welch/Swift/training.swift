import Foundation

struct LabeledPair { let observations: [Int]; let path: [Int] }
func smoothedModel(_ template: Model, _ name: String, _ initial: [Double], _ transition: [[Double]], _ emission: [[Double]], _ alpha: Double) -> Model {
    Model(name, template.states, template.symbols, template.missing, initial.map { $0 + alpha }, transition.map { $0.map { $0 + alpha } }, emission.map { $0.map { $0 + alpha } })
}
func baumWelchStep(_ model: Model, _ sequences: [[Int]], _ pseudocount: Double) -> Model {
    let count = model.count
    var initial = Array(repeating: 0.0, count: count), transition = Array(repeating: Array(repeating: 0.0, count: count), count: count), emission = Array(repeating: Array(repeating: 0.0, count: model.symbols.count), count: count)
    for observations in sequences {
        let result = forwardBackward(model, observations)
        for i in 0..<count { initial[i] += result.posterior[0][i] }
        for (t, symbol) in observations.enumerated() {
            for i in 0..<count {
                if symbol != -1 { emission[i][symbol] += result.posterior[t][i] }
                if t + 1 < observations.count { for j in 0..<count { transition[i][j] += posteriorTransition(model, result, t, i, j) } }
            }
        }
    }
    return smoothedModel(model, "BAUM_WELCH", initial, transition, emission, pseudocount)
}
func estimateByCounting(_ template: Model, _ pairs: [LabeledPair], _ alpha: Double, _ name: String = "SUPERVISED") -> Model {
    let count = template.count
    var initial = Array(repeating: 0.0, count: count), transition = Array(repeating: Array(repeating: 0.0, count: count), count: count), emission = Array(repeating: Array(repeating: 0.0, count: template.symbols.count), count: count)
    for pair in pairs {
        initial[pair.path[0]] += 1
        for (t, state) in pair.path.enumerated() { if pair.observations[t] != -1 { emission[state][pair.observations[t]] += 1 }; if t + 1 < pair.path.count { transition[state][pair.path[t + 1]] += 1 } }
    }
    return smoothedModel(template, name, initial, transition, emission, alpha)
}
func totalLogLikelihood(_ model: Model, _ sequences: [[Int]]) -> Double { sequences.reduce(0) { $0 + scaledForward(model, $1).logLikelihood } }
