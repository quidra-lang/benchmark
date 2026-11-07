#include "trainer.hpp"
double activation(const std::string &function, double z) {
    if (function == "TANH")
        return std::tanh(z);
    if (function == "SIGMOID")
        return 1 / (1 + std::exp(-z));
    return z > 0 ? z : 0;
}
double derivative(const std::string &function, double z, double a) {
    if (function == "TANH")
        return 1 - a * a;
    if (function == "SIGMOID")
        return a * (1 - a);
    return z > 0 ? 1 : 0;
}
Field preactivation(const Field &weights, const Field &input, const Layer &layer) {
    Field out(layer.units);
    for (int j = 0; j < layer.units; ++j) {
        double sum = 0;
        for (int i = 0; i < layer.inputs; ++i)
            sum += weights[layer.weights + j * layer.inputs + i] * input[i];
        out[j] = sum + weights[layer.biases + j];
    }
    return out;
}
Field propagate(const Field &weights, const Layer &next, const Field &delta) {
    Field out(next.inputs);
    for (int j = 0; j < next.inputs; ++j)
        for (int k = 0; k < next.units; ++k)
            out[j] += weights[next.weights + k * next.inputs + j] * delta[k];
    return out;
}
Output output_layer(const std::string &function, const Field &z, int label) {
    const int count = int(z.size());
    Output out{Field(count), Field(count), 0};
    if (function == "SOFTMAX") {
        const double maximum = *std::max_element(z.begin(), z.end());
        double total = 0;
        for (int k = 0; k < count; ++k) {
            out.scores[k] = std::exp(z[k] - maximum);
            total += out.scores[k];
        }
        for (double &score : out.scores)
            score /= total;
        out.loss = std::log(total) - (z[label] - maximum);
        for (int k = 0; k < count; ++k)
            out.delta[k] = out.scores[k] - (k == label ? 1 : 0);
    } else {
        for (int k = 0; k < count; ++k) {
            const double score = 1 / (1 + std::exp(-z[k])),
                         difference = score - (k == label ? 1 : 0);
            out.scores[k] = score;
            out.loss += difference * difference;
            out.delta[k] = 2 * difference * score * (1 - score) / count;
        }
        out.loss /= count;
    }
    return out;
}
