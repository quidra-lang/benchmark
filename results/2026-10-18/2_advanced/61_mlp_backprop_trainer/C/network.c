#include "trainer.h"
void add_layer(Network *network, int units, const char *function, bool output) {
    int inputs = network->layer_count ? network->layers[network->layer_count - 1].units
                                      : network->inputs,
        weights = network->param_count, biases = weights + units * inputs;
    Layer *layer = &network->layers[network->layer_count++];
    layer->inputs = inputs;
    layer->units = units;
    layer->weights = weights;
    layer->biases = biases;
    layer->output = output;
    strcpy(layer->function, function);
    network->param_count = biases + units;
    for (int p = weights; p < biases; ++p)
        network->is_weight[p] = true;
    network->weight_count += units * inputs;
    if (output)
        network->classes = units;
}
void forward(const Network *network, const double *weights, const Image *image, Forward *out) {
    memcpy(out->activations[0], image->input, (size_t)network->inputs * sizeof(double));
    for (int l = 0; l < network->layer_count; ++l) {
        const Layer *layer = &network->layers[l];
        preactivation(weights, out->activations[l], layer, out->z[l]);
        if (layer->output) {
            output_layer(layer->function, out->z[l], layer->units, image->label, out->scores,
                         out->delta, &out->loss);
            memcpy(out->activations[l + 1], out->scores, (size_t)layer->units * sizeof(double));
        } else
            for (int j = 0; j < layer->units; ++j)
                out->activations[l + 1][j] = activation(layer->function, out->z[l][j]);
    }
}
void backward(const Network *network, const double *weights, const Forward *record, Backward *out) {
    double errors[3][12], carried[64];
    int last = network->layer_count - 1;
    memcpy(errors[last], record->delta, (size_t)network->classes * sizeof(double));
    for (int l = last - 1; l >= 0; --l) {
        const Layer *layer = &network->layers[l];
        propagate(weights, &network->layers[l + 1], errors[l + 1], carried);
        for (int j = 0; j < layer->units; ++j)
            errors[l][j] = carried[j] * derivative(layer->function, record->z[l][j],
                                                   record->activations[l + 1][j]);
    }
    propagate(weights, &network->layers[0], errors[0], out->input);
    for (int l = 0; l < network->layer_count; ++l) {
        const Layer *layer = &network->layers[l];
        for (int j = 0; j < layer->units; ++j) {
            for (int i = 0; i < layer->inputs; ++i)
                out->parameters[layer->weights + j * layer->inputs + i] =
                    errors[l][j] * record->activations[l][i];
            out->parameters[layer->biases + j] = errors[l][j];
        }
    }
}
