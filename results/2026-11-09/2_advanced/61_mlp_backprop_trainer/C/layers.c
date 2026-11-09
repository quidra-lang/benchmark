#include "trainer.h"
double activation(const char *function, double z) {
    if (strcmp(function, "TANH") == 0)
        return tanh(z);
    if (strcmp(function, "SIGMOID") == 0)
        return 1 / (1 + exp(-z));
    return z > 0 ? z : 0;
}
double derivative(const char *function, double z, double a) {
    if (strcmp(function, "TANH") == 0)
        return 1 - a * a;
    if (strcmp(function, "SIGMOID") == 0)
        return a * (1 - a);
    return z > 0 ? 1 : 0;
}
void preactivation(const double *weights, const double *input, const Layer *layer, double *out) {
    for (int j = 0; j < layer->units; ++j) {
        double sum = 0;
        for (int i = 0; i < layer->inputs; ++i)
            sum += weights[layer->weights + j * layer->inputs + i] * input[i];
        out[j] = sum + weights[layer->biases + j];
    }
}
void propagate(const double *weights, const Layer *next, const double *delta, double *out) {
    for (int j = 0; j < next->inputs; ++j) {
        out[j] = 0;
        for (int k = 0; k < next->units; ++k)
            out[j] += weights[next->weights + k * next->inputs + j] * delta[k];
    }
}
void output_layer(const char *function, const double *z, int count, int label, double *scores,
                  double *delta, double *loss) {
    if (strcmp(function, "SOFTMAX") == 0) {
        double maximum = z[0], total = 0;
        for (int k = 1; k < count; ++k)
            if (z[k] > maximum)
                maximum = z[k];
        for (int k = 0; k < count; ++k) {
            scores[k] = exp(z[k] - maximum);
            total += scores[k];
        }
        for (int k = 0; k < count; ++k) {
            scores[k] /= total;
            delta[k] = scores[k] - (k == label ? 1 : 0);
        }
        *loss = log(total) - (z[label] - maximum);
    } else {
        *loss = 0;
        for (int k = 0; k < count; ++k) {
            double score = 1 / (1 + exp(-z[k])), difference = score - (k == label ? 1 : 0);
            scores[k] = score;
            *loss += difference * difference;
            delta[k] = 2 * difference * score * (1 - score) / count;
        }
        *loss /= count;
    }
}
