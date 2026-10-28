#include "gaussian.hpp"
Statistics statistics(const Rows &rows, const Features &features, int classes, bool empirical) {
    Statistics out;
    out.count = rows.size();
    out.classes = classes;
    out.size = features.size();
    for (const Row &row : rows)
        ++out.counts[row.label];
    for (int k = 0; k < classes; ++k) {
        for (int j = 0; j < out.size; ++j) {
            double sum = 0;
            for (const Row &row : rows)
                if (row.label == k)
                    sum += row.values[features[j]];
            out.means[k][j] = sum / out.counts[k];
        }
        for (int a = 0; a < out.size; ++a)
            for (int b = 0; b < out.size; ++b) {
                double sum = 0;
                for (const Row &row : rows)
                    if (row.label == k)
                        sum += (row.values[features[a]] - out.means[k][a]) *
                               (row.values[features[b]] - out.means[k][b]);
                out.scatter[k][a][b] = sum;
            }
        out.priors[k] = empirical ? double(out.counts[k]) / out.count : 1.0 / classes;
    }
    for (int j = 0; j < out.size; ++j) {
        double sum = 0;
        for (const Row &row : rows)
            sum += row.values[features[j]];
        out.center[j] = sum / out.count;
        sum = 0;
        for (const Row &row : rows)
            sum += (row.values[features[j]] - out.center[j]) * (row.values[features[j]] - out.center[j]);
        out.variance[j] = sum / out.count;
    }
    return out;
}
Model train(const Rows &rows, const Features &features, int classes, int kind, bool empirical,
            double smoothing, double gamma) {
    Model out;
    out.kind = kind;
    out.features = features;
    out.stats = statistics(rows, features, classes, empirical);
    const int size = features.size();
    out.max_variance = *std::max_element(out.stats.variance.begin(), out.stats.variance.begin() + size);
    out.added = smoothing * out.max_variance;
    for (int k = 0; k < classes; ++k) {
        for (int a = 0; a < size; ++a)
            for (int b = 0; b < size; ++b) {
                double value = 0;
                if (kind == 0) {
                    if (a == b)
                        value = out.stats.scatter[k][a][a] / out.stats.counts[k] + out.added;
                } else if (kind == 1) {
                    double sum = 0;
                    for (int j = 0; j < classes; ++j)
                        sum += out.stats.scatter[j][a][b];
                    value = sum / (out.stats.count - classes);
                } else {
                    value = out.stats.scatter[k][a][b] / (out.stats.counts[k] - 1);
                    if (a != b)
                        value = value * (1 - gamma);
                }
                out.covariance[k][a][b] = value;
            }
        out.lower[k] = cholesky(out.covariance[k], size);
        out.log_det[k] = log_determinant(out.lower[k], size);
    }
    return out;
}
Prediction predict(const Model &model, const Vector &values,
                   const std::array<std::array<double, 5>, 5> &costs) {
    Prediction out;
    const int classes = model.stats.classes, size = model.stats.size;
    std::array<double, 5> scores{};
    const double h = size * std::log(2 * std::acos(-1.0)) / 2;
    for (int k = 0; k < classes; ++k) {
        Vector difference{};
        for (int j = 0; j < size; ++j)
            difference[j] = values[model.features[j]] - model.stats.means[k][j];
        out.distance[k] = quadratic(model.lower[k], difference, size);
        scores[k] = std::log(model.stats.priors[k]) - h - model.log_det[k] / 2 - out.distance[k] / 2;
        if (scores[k] > scores[out.predicted])
            out.predicted = k;
    }
    const double maximum = scores[out.predicted];
    double sum = 0;
    for (int k = 0; k < classes; ++k) {
        out.posterior[k] = std::exp(scores[k] - maximum);
        sum += out.posterior[k];
    }
    for (int k = 0; k < classes; ++k) {
        out.posterior[k] /= sum;
        out.log_posterior[k] = (scores[k] - maximum) - std::log(sum);
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
