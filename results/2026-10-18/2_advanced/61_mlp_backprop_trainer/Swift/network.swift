import Foundation

struct Layer { let inputs: Int; let outputs: Int; let activation: Activation; let weightStart: Int; let weightEnd: Int; let biasStart: Int; let biasEnd: Int }
struct ForwardCache { let z: [[Double]]; let activations: [[Double]]; let weights: [[[Double]]]; let scores: [Double]; let loss: Double; let outputError: [Double] }
struct Gradient { let parameters: [Double]; let cache: ForwardCache; let input: [Double] }
struct Network {
    let name: String
    let width: Int
    let height: Int
    let layers: [Layer]
    let initial: [Double]
    let isWeight: [Bool]
    let weightCount: Int
    var classes: Int { layers.last!.outputs }
    var parameterCount: Int { initial.count }
    init(name: String, width: Int, height: Int, definitions: [LayerDefinition], initial: [Double]) {
        var inputs = width * height, cursor = 0, layers: [Layer] = [], mask: [Bool] = []
        for definition in definitions { let count = inputs * definition.units; layers.append(Layer(inputs: inputs, outputs: definition.units, activation: definition.activation, weightStart: cursor, weightEnd: cursor + count, biasStart: cursor + count, biasEnd: cursor + count + definition.units)); mask += Array(repeating: true, count: count) + Array(repeating: false, count: definition.units); cursor += count + definition.units; inputs = definition.units }
        self.name = name; self.width = width; self.height = height; self.initial = initial; self.layers = layers; isWeight = mask; weightCount = mask.filter { $0 }.count
    }
    func forward(_ theta: [Double], _ image: Image) -> ForwardCache {
        var activations = [image.vector], zValues: [[Double]] = [], allWeights: [[[Double]]] = []
        var output = OutputValues(scores: [], loss: 0, error: [])
        for (index, layer) in layers.enumerated() {
            let weights = (0..<layer.outputs).map { row in Array(theta[(layer.weightStart + row * layer.inputs)..<(layer.weightStart + (row + 1) * layer.inputs)]) }, biases = Array(theta[layer.biasStart..<layer.biasEnd]), z = preactivations(weights, biases, activations.last!)
            allWeights.append(weights); zValues.append(z)
            if index == layers.count - 1 { output = outputValues(layer.activation, z, image.label); activations.append(output.scores) } else { activations.append(z.map { hiddenActivation(layer.activation, $0) }) }
        }
        return ForwardCache(z: zValues, activations: activations, weights: allWeights, scores: output.scores, loss: output.loss, outputError: output.error)
    }
    func gradient(_ theta: [Double], _ image: Image) -> Gradient {
        let cache = forward(theta, image)
        var deltas = Array(repeating: [Double](), count: layers.count), parameters = Array(repeating: 0.0, count: parameterCount)
        deltas[layers.count - 1] = cache.outputError
        for index in stride(from: layers.count - 2, through: 0, by: -1) { let values = backwardSum(cache.weights[index + 1], deltas[index + 1]), layer = layers[index]; deltas[index] = values.indices.map { values[$0] * hiddenDerivative(layer.activation, cache.z[index][$0], cache.activations[index + 1][$0]) } }
        for (index, layer) in layers.enumerated() { for j in 0..<layer.outputs { for i in 0..<layer.inputs { parameters[layer.weightStart + j * layer.inputs + i] = deltas[index][j] * cache.activations[index][i] }; parameters[layer.biasStart + j] = deltas[index][j] } }
        return Gradient(parameters: parameters, cache: cache, input: backwardSum(cache.weights[0], deltas[0]))
    }
}
