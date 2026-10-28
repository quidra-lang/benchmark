#include "regression.h"
SoftPoint soft_point(SoftWeights weights, const double *row, int label) {
    SoftPoint result = {0};
    double scores[4], exponents[4], maximum = -INFINITY, total = 0;
    for (int k = 0; k < weights.count; ++k) {
        scores[k] = score(weights.classes[k], row);
        maximum = fmax(maximum, scores[k]);
    }
    for (int k = 0; k < weights.count; ++k) {
        exponents[k] = exp(scores[k] - maximum);
        total += exponents[k];
    }
    for (int k = 0; k < weights.count; ++k) {
        result.probabilities[k] = exponents[k] / total;
        if (result.probabilities[k] > result.probabilities[result.predicted])
            result.predicted = k;
    }
    result.loss = log(total) - (scores[label] - maximum);
    return result;
}
double soft_loss(SoftWeights weights, const Matrix *data, const Targets *labels_) {
    double total = 0;
    for (int i = 0; i < data->rows; ++i)
        total += soft_point(weights, data->values[i], labels_->values[i]).loss;
    return total / (double)data->rows;
}
double soft_objective(SoftWeights weights, const Matrix *data, const Targets *labels_, double lambda) {
    double penalty = 0;
    for (int k = 0; k < weights.count; ++k)
        for (int j = 1; j < weights.classes[k].count; ++j)
            penalty += weights.classes[k].values[j] * weights.classes[k].values[j];
    return soft_loss(weights, data, labels_) + lambda * penalty / 2;
}
SoftWeights soft_gradient(SoftWeights weights, const Matrix *data, const Targets *labels_, double lambda) {
    SoftWeights result = {.count = weights.count};
    SoftPoint points[300];
    for (int i = 0; i < data->rows; ++i)
        points[i] = soft_point(weights, data->values[i], labels_->values[i]);
    for (int k = 0; k < weights.count; ++k) {
        result.classes[k].count = weights.classes[k].count;
        for (int j = 0; j < weights.classes[k].count; ++j) {
            double total = 0;
            for (int i = 0; i < data->rows; ++i)
                total += (points[i].probabilities[k] - (labels_->values[i] == k)) * data->values[i][j];
            result.classes[k].values[j] = total / (double)data->rows;
            if (j)
                result.classes[k].values[j] += lambda * weights.classes[k].values[j];
        }
    }
    return result;
}
SoftTrace train_softmax(const Matrix *data, const Targets *labels_, int classes, const Params *p) {
    SoftWeights weights = {.count = classes};
    for (int k = 0; k < classes; ++k)
        weights.classes[k].count = data->columns;
    SoftTrace result = {0};
    result.points[result.count++] = (SoftCheckpoint){0, weights};
    for (int iteration = 1; iteration <= p->softmax_iterations; ++iteration) {
        SoftWeights g = soft_gradient(weights, data, labels_, p->softmax_lambda);
        for (int k = 0; k < classes; ++k)
            for (int j = 0; j < data->columns; ++j)
                weights.classes[k].values[j] -= p->softmax_rate * g.classes[k].values[j];
        if (iteration % 100 == 0)
            result.points[result.count++] = (SoftCheckpoint){iteration, weights};
    }
    return result;
}
