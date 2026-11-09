#include "regression.hpp"
double score(const Vector &weights, const Vector &row) {
    double value = 0;
    for (std::size_t j = 0; j < weights.size(); ++j)
        value += weights[j] * row[j];
    return value;
}
double sigmoid(double value) {
    if (value >= 0)
        return 1 / (1 + std::exp(-value));
    const double e = std::exp(value);
    return e / (1 + e);
}
double logistic_loss(double value, int target) {
    return std::max(value, 0.0) - target * value + std::log(1 + std::exp(-std::abs(value)));
}
Vector probabilities(const Vector &weights, const Matrix &data) {
    Vector result;
    for (const Vector &row : data)
        result.push_back(sigmoid(score(weights, row)));
    return result;
}
double average_loss(const Vector &weights, const Matrix &data, const std::vector<int> &targets) {
    double total = 0;
    for (std::size_t i = 0; i < data.size(); ++i)
        total += logistic_loss(score(weights, data[i]), targets[i]);
    return total / double(data.size());
}
double objective(const Vector &weights, const Matrix &data, const std::vector<int> &targets, double lambda) {
    double penalty = 0;
    for (std::size_t j = 1; j < weights.size(); ++j)
        penalty += weights[j] * weights[j];
    return average_loss(weights, data, targets) + lambda * penalty / 2;
}
Vector gradient(const Vector &weights, const Matrix &data, const std::vector<int> &targets, double lambda) {
    Vector result(weights.size()), errors;
    for (std::size_t i = 0; i < data.size(); ++i)
        errors.push_back(sigmoid(score(weights, data[i])) - targets[i]);
    for (std::size_t j = 0; j < weights.size(); ++j) {
        double total = 0;
        for (std::size_t i = 0; i < data.size(); ++i)
            total += errors[i] * data[i][j];
        result[j] = total / double(data.size());
        if (j)
            result[j] += lambda * weights[j];
    }
    return result;
}
Matrix hessian(const Vector &weights, const Matrix &data, double lambda) {
    const Vector probabilities_ = probabilities(weights, data);
    Vector variance;
    for (double probability : probabilities_)
        variance.push_back(probability * (1 - probability));
    Matrix result(weights.size(), Vector(weights.size()));
    for (std::size_t j = 0; j < weights.size(); ++j)
        for (std::size_t k = 0; k <= j; ++k) {
            double total = 0;
            for (std::size_t i = 0; i < data.size(); ++i)
                total += variance[i] * data[i][j] * data[i][k];
            result[j][k] = total / double(data.size());
            if (j == k && j)
                result[j][k] += lambda;
            result[k][j] = result[j][k];
        }
    return result;
}
double length(const Vector &values) {
    double total = 0;
    for (double value : values)
        total += value * value;
    return std::sqrt(total);
}
