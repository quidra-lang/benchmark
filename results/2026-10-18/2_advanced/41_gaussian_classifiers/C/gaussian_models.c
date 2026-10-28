#include "gaussian.h"
Statistics statistics(const Rows *rows, Features features, int classes, bool empirical) {
    Statistics out = {.count = rows->count, .classes = classes, .size = features.count};
    for (int i = 0; i < rows->count; ++i)
        ++out.counts[rows->data[i].label];
    for (int k = 0; k < classes; ++k) {
        for (int j = 0; j < out.size; ++j) {
            double sum = 0;
            for (int i = 0; i < rows->count; ++i)
                if (rows->data[i].label == k)
                    sum += rows->data[i].values.v[features.v[j]];
            out.means[k].v[j] = sum / out.counts[k];
        }
        for (int a = 0; a < out.size; ++a)
            for (int b = 0; b < out.size; ++b) {
                double sum = 0;
                for (int i = 0; i < rows->count; ++i)
                    if (rows->data[i].label == k)
                        sum += (rows->data[i].values.v[features.v[a]] - out.means[k].v[a]) *
                               (rows->data[i].values.v[features.v[b]] - out.means[k].v[b]);
                out.scatter[k].v[a][b] = sum;
            }
        out.priors[k] = empirical ? (double)out.counts[k] / out.count : 1.0 / classes;
    }
    for (int j = 0; j < out.size; ++j) {
        double sum = 0;
        for (int i = 0; i < rows->count; ++i)
            sum += rows->data[i].values.v[features.v[j]];
        out.center.v[j] = sum / out.count;
        sum = 0;
        for (int i = 0; i < rows->count; ++i)
            sum += (rows->data[i].values.v[features.v[j]] - out.center.v[j]) *
                   (rows->data[i].values.v[features.v[j]] - out.center.v[j]);
        out.variance.v[j] = sum / out.count;
    }
    return out;
}
Model train(const Rows *rows, Features features, int classes, int kind, bool empirical, double smoothing,
            double gamma) {
    Model out = {.kind = kind, .features = features};
    out.stats = statistics(rows, features, classes, empirical);
    int size = features.count;
    out.max_variance = out.stats.variance.v[0];
    for (int j = 1; j < size; ++j)
        if (out.stats.variance.v[j] > out.max_variance)
            out.max_variance = out.stats.variance.v[j];
    out.added = smoothing * out.max_variance;
    for (int k = 0; k < classes; ++k) {
        for (int a = 0; a < size; ++a)
            for (int b = 0; b < size; ++b) {
                double value = 0;
                if (kind == 0) {
                    if (a == b)
                        value = out.stats.scatter[k].v[a][a] / out.stats.counts[k] + out.added;
                } else if (kind == 1) {
                    double sum = 0;
                    for (int j = 0; j < classes; ++j)
                        sum += out.stats.scatter[j].v[a][b];
                    value = sum / (out.stats.count - classes);
                } else {
                    value = out.stats.scatter[k].v[a][b] / (out.stats.counts[k] - 1);
                    if (a != b)
                        value = value * (1 - gamma);
                }
                out.covariance[k].v[a][b] = value;
            }
        out.lower[k] = cholesky(&out.covariance[k], size);
        out.log_det[k] = log_determinant(&out.lower[k], size);
    }
    return out;
}
Prediction predict(const Model *model, const Vector *values, const double costs[5][5]) {
    Prediction out = {0};
    int classes = model->stats.classes, size = model->stats.size;
    double scores[5] = {0}, h = size * log(2 * acos(-1.0)) / 2;
    for (int k = 0; k < classes; ++k) {
        Vector difference = {0};
        for (int j = 0; j < size; ++j)
            difference.v[j] = values->v[model->features.v[j]] - model->stats.means[k].v[j];
        out.distance[k] = quadratic(&model->lower[k], &difference, size);
        scores[k] = log(model->stats.priors[k]) - h - model->log_det[k] / 2 - out.distance[k] / 2;
        if (scores[k] > scores[out.predicted])
            out.predicted = k;
    }
    double maximum = scores[out.predicted], sum = 0;
    for (int k = 0; k < classes; ++k) {
        out.posterior[k] = exp(scores[k] - maximum);
        sum += out.posterior[k];
    }
    for (int k = 0; k < classes; ++k) {
        out.posterior[k] /= sum;
        out.log_posterior[k] = (scores[k] - maximum) - log(sum);
    }
    out.confidence = out.posterior[out.predicted];
    double best = 0;
    for (int b = 0; b < classes; ++b) {
        double risk = 0;
        for (int k = 0; k < classes; ++k)
            risk += out.posterior[k] * costs[k][b];
        if (b == 0 || risk < best) {
            best = risk;
            out.decision = b;
        }
    }
    return out;
}
