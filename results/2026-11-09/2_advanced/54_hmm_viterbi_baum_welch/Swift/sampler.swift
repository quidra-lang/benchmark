import Foundation

struct MINSTD {
    var state: Int
    mutating func random() -> Double { state = 48271 * state % 2147483647; return Double(state) / 2147483647 }
}
func draw(_ weights: [Double], _ generator: inout MINSTD) -> Int {
    let total = weights.reduce(0, +), threshold = generator.random() * total
    var cumulative = 0.0
    for (i, value) in weights.enumerated() { cumulative += value; if threshold < cumulative { return i } }
    return weights.count - 1
}
func syntheticSequence(_ model: Model, _ length: Int, _ generator: inout MINSTD) -> LabeledPair {
    var states: [Int] = [], observations: [Int] = []
    for t in 0..<length { let state = draw(t == 0 ? model.initial : model.transition[states.last!], &generator), symbol = draw(model.emission[state], &generator); states.append(state); observations.append(symbol) }
    return LabeledPair(observations: observations, path: states)
}
func posteriorPath(_ model: Model, _ forward: [[Double]], _ generator: inout MINSTD) -> [Int] {
    var path = Array(repeating: 0, count: forward.count)
    path[path.count - 1] = draw(forward.last!, &generator)
    if path.count > 1 {
        for t in (0..<(path.count - 1)).reversed() { let following = path[t + 1], weights = (0..<model.count).map { forward[t][$0] * model.transition[$0][following] }; path[t] = draw(weights, &generator) }
    }
    return path
}
