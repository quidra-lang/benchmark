#include "trainer.hpp"
void add_layer(Network &network, int units, const std::string &function, bool output) {
    const int inputs = network.layers.empty() ? network.inputs : network.layers.back().units,
              weights = int(network.initial.size()), biases = weights + units * inputs;
    network.layers.push_back({inputs, units, function, weights, biases, output});
    network.initial.resize(biases + units);
    for (int i = 0; i < units * inputs; ++i)
        network.is_weight.push_back(true);
    for (int i = 0; i < units; ++i)
        network.is_weight.push_back(false);
    network.weight_count += units * inputs;
    if (output)
        network.classes = units;
}
Forward forward(const Network &network, const Field &weights, const Image &image) {
    Forward out;
    out.activations.push_back(image.input);
    for (const Layer &layer : network.layers) {
        out.z.push_back(preactivation(weights, out.activations.back(), layer));
        if (layer.output) {
            const Output result = output_layer(layer.function, out.z.back(), image.label);
            out.scores = result.scores;
            out.delta = result.delta;
            out.loss = result.loss;
            out.activations.push_back(result.scores);
        } else {
            Field values;
            for (double z : out.z.back())
                values.push_back(activation(layer.function, z));
            out.activations.push_back(values);
        }
    }
    return out;
}
Backward backward(const Network &network, const Field &weights, const Forward &record) {
    const int count = int(network.layers.size());
    std::vector<Field> errors(count);
    errors.back() = record.delta;
    for (int l = count - 2; l >= 0; --l) {
        const Field carried = propagate(weights, network.layers[l + 1], errors[l + 1]);
        errors[l].resize(network.layers[l].units);
        for (int j = 0; j < network.layers[l].units; ++j)
            errors[l][j] = carried[j] * derivative(network.layers[l].function, record.z[l][j],
                                                   record.activations[l + 1][j]);
    }
    Backward out{Field(weights.size()), propagate(weights, network.layers[0], errors[0])};
    for (int l = 0; l < count; ++l) {
        const Layer &layer = network.layers[l];
        for (int j = 0; j < layer.units; ++j) {
            for (int i = 0; i < layer.inputs; ++i)
                out.parameters[layer.weights + j * layer.inputs + i] =
                    errors[l][j] * record.activations[l][i];
            out.parameters[layer.biases + j] = errors[l][j];
        }
    }
    return out;
}
