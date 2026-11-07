import Foundation

func maximumIndex(_ values: [Double]) -> Int { var best = 0; for i in values.indices.dropFirst() { if values[i] > values[best] { best = i } }; return best }
func emissionFactors(_ model: Model, _ symbol: Int) -> [Double] { symbol == -1 ? Array(repeating: 1, count: model.count) : model.emission.map { $0[symbol] } }
func logEmissionFactors(_ model: Model, _ symbol: Int) -> [Double] { symbol == -1 ? Array(repeating: 0, count: model.count) : model.emission.map { log($0[symbol]) } }
struct ForwardResult { let values: [[Double]]; let scales: [Double]; let emissions: [[Double]]; let logLikelihood: Double }
struct ForwardBackwardResult {
    let forward: [[Double]]
    let backward: [[Double]]
    let scales: [Double]
    let emissions: [[Double]]
    let posterior: [[Double]]
    let logLikelihood: Double
}
struct ViterbiResult { let path: [Int]; let logProbability: Double }
struct Decoding { let viterbi: [Int]; let viterbiLogProbability: Double; let posterior: [Int]; let confidence: [Double]; let fb: ForwardBackwardResult }
func scaledForward(_ model: Model, _ observations: [Int]) -> ForwardResult {
    let emissions = observations.map { emissionFactors(model, $0) }
    var values: [[Double]] = [], scales: [Double] = [], logLikelihood = 0.0
    for t in observations.indices {
        var unscaled: [Double] = []
        for j in 0..<model.count {
            let before = t == 0 ? model.initial[j] : (0..<model.count).reduce(0) { $0 + values[t - 1][$1] * model.transition[$1][j] }
            unscaled.append(before * emissions[t][j])
        }
        let scale = unscaled.reduce(0, +)
        scales.append(scale); values.append(unscaled.map { $0 / scale }); logLikelihood += log(scale)
    }
    return ForwardResult(values: values, scales: scales, emissions: emissions, logLikelihood: logLikelihood)
}
func forwardBackward(_ model: Model, _ observations: [Int]) -> ForwardBackwardResult {
    let result = scaledForward(model, observations), length = observations.count, count = model.count
    var backward = Array(repeating: Array(repeating: 0.0, count: count), count: length)
    backward[length - 1] = Array(repeating: 1, count: count)
    if length > 1 {
        for t in (0..<(length - 1)).reversed() {
            for i in 0..<count {
                let total = (0..<count).reduce(0.0) { $0 + model.transition[i][$1] * result.emissions[t + 1][$1] * backward[t + 1][$1] }
                backward[t][i] = total / result.scales[t + 1]
            }
        }
    }
    let posterior = observations.indices.map { t in (0..<count).map { result.values[t][$0] * backward[t][$0] } }
    return ForwardBackwardResult(forward: result.values, backward: backward, scales: result.scales, emissions: result.emissions, posterior: posterior, logLikelihood: result.logLikelihood)
}
func posteriorTransition(_ model: Model, _ result: ForwardBackwardResult, _ t: Int, _ i: Int, _ j: Int) -> Double { result.forward[t][i] * model.transition[i][j] * result.emissions[t + 1][j] * result.backward[t + 1][j] / result.scales[t + 1] }
func viterbi(_ model: Model, _ observations: [Int]) -> ViterbiResult {
    let count = model.count, transitions = model.transition.map { $0.map { log($0) } }, initialFactors = logEmissionFactors(model, observations[0])
    var scores = (0..<count).map { log(model.initial[$0]) + initialFactors[$0] }, predecessors = [Array(repeating: 0, count: count)]
    for observation in observations.dropFirst() {
        let factors = logEmissionFactors(model, observation)
        var next: [Double] = [], previous: [Int] = []
        for j in 0..<count { let candidates = (0..<count).map { scores[$0] + transitions[$0][j] }, i = maximumIndex(candidates); previous.append(i); next.append(candidates[i] + factors[j]) }
        scores = next; predecessors.append(previous)
    }
    var path = Array(repeating: 0, count: observations.count)
    path[path.count - 1] = maximumIndex(scores)
    let logProbability = scores[path.last!]
    if path.count > 1 { for t in (1..<path.count).reversed() { path[t - 1] = predecessors[t][path[t]] } }
    return ViterbiResult(path: path, logProbability: logProbability)
}
func decode(_ model: Model, _ observations: [Int]) -> Decoding {
    let fb = forwardBackward(model, observations), best = viterbi(model, observations), posterior = fb.posterior.map { maximumIndex($0) }
    return Decoding(viterbi: best.path, viterbiLogProbability: best.logProbability, posterior: posterior, confidence: posterior.enumerated().map { fb.posterior[$0.offset][$0.element] }, fb: fb)
}
