#include "regression.hpp"
SoftPoint soft_point(const Matrix &weights, const Vector &row, int label) {
    Vector scores;
    for (const Vector &w : weights)
        scores.push_back(score(w, row));
    const double maximum = *std::max_element(scores.begin(), scores.end());
    double total = 0;
    Vector exponents;
    for (double value : scores) {
        const double e = std::exp(value - maximum);
        exponents.push_back(e);
        total += e;
    }
    Vector probabilities_;
    for (double e : exponents)
        probabilities_.push_back(e / total);
    int predicted = 0;
    for (std::size_t k = 1; k < weights.size(); ++k)
        if (probabilities_[k] > probabilities_[predicted])
            predicted = int(k);
    return {probabilities_, std::log(total) - (scores[label] - maximum), predicted};
}
double soft_loss(const Matrix &weights, const Matrix &data, const std::vector<int> &labels_) {
    double total = 0;
    for (std::size_t i = 0; i < data.size(); ++i)
        total += soft_point(weights, data[i], labels_[i]).loss;
    return total / double(data.size());
}
double soft_objective(const Matrix &weights, const Matrix &data, const std::vector<int> &labels_,
                      double lambda) {
    double penalty = 0;
    for (const Vector &w : weights)
        for (std::size_t j = 1; j < w.size(); ++j)
            penalty += w[j] * w[j];
    return soft_loss(weights, data, labels_) + lambda * penalty / 2;
}
Matrix soft_gradient(const Matrix &weights, const Matrix &data, const std::vector<int> &labels_,
                     double lambda) {
    Matrix probabilities_;
    for (std::size_t i = 0; i < data.size(); ++i)
        probabilities_.push_back(soft_point(weights, data[i], labels_[i]).probabilities);
    Matrix result(weights.size(), Vector(weights[0].size()));
    for (std::size_t k = 0; k < weights.size(); ++k)
        for (std::size_t j = 0; j < weights[k].size(); ++j) {
            double total = 0;
            for (std::size_t i = 0; i < data.size(); ++i)
                total += (probabilities_[i][k] - int(labels_[i] == int(k))) * data[i][j];
            result[k][j] = total / double(data.size());
            if (j)
                result[k][j] += lambda * weights[k][j];
        }
    return result;
}
std::vector<SoftCheckpoint> train_softmax(const Matrix &data, const std::vector<int> &labels_, int classes,
                                          const Params &p) {
    Matrix weights(classes, Vector(data[0].size()));
    std::vector<SoftCheckpoint> result{{0, weights}};
    for (int iteration = 1; iteration <= p.softmax_iterations; ++iteration) {
        const Matrix g = soft_gradient(weights, data, labels_, p.softmax_lambda);
        for (int k = 0; k < classes; ++k)
            for (std::size_t j = 0; j < weights[k].size(); ++j)
                weights[k][j] -= p.softmax_rate * g[k][j];
        if (iteration % 100 == 0)
            result.push_back({iteration, weights});
    }
    return result;
}
