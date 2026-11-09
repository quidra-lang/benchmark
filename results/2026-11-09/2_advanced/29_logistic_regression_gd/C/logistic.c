#include "regression.h"
double score(Vector weights, const double *row) {
    double total = 0;
    for (int j = 0; j < weights.count; ++j)
        total += weights.values[j] * row[j];
    return total;
}
double sigmoid(double value) {
    if (value >= 0)
        return 1 / (1 + exp(-value));
    double e = exp(value);
    return e / (1 + e);
}
double logistic_loss(double value, int target) {
    return fmax(value, 0) - target * value + log(1 + exp(-fabs(value)));
}
Scores probabilities(Vector weights, const Matrix *data) {
    Scores result = {.count = data->rows};
    for (int i = 0; i < data->rows; ++i)
        result.values[i] = sigmoid(score(weights, data->values[i]));
    return result;
}
double average_loss(Vector weights, const Matrix *data, const Targets *targets) {
    double total = 0;
    for (int i = 0; i < data->rows; ++i)
        total += logistic_loss(score(weights, data->values[i]), targets->values[i]);
    return total / (double)data->rows;
}
double objective(Vector weights, const Matrix *data, const Targets *targets, double lambda) {
    double penalty = 0;
    for (int j = 1; j < weights.count; ++j)
        penalty += weights.values[j] * weights.values[j];
    return average_loss(weights, data, targets) + lambda * penalty / 2;
}
Vector gradient(Vector weights, const Matrix *data, const Targets *targets, double lambda) {
    Vector result = {.count = weights.count};
    double errors[300];
    for (int i = 0; i < data->rows; ++i)
        errors[i] = sigmoid(score(weights, data->values[i])) - targets->values[i];
    for (int j = 0; j < weights.count; ++j) {
        double total = 0;
        for (int i = 0; i < data->rows; ++i)
            total += errors[i] * data->values[i][j];
        result.values[j] = total / (double)data->rows;
        if (j)
            result.values[j] += lambda * weights.values[j];
    }
    return result;
}
Square hessian(Vector weights, const Matrix *data, double lambda) {
    Scores p = probabilities(weights, data);
    double variance[300];
    for (int i = 0; i < data->rows; ++i)
        variance[i] = p.values[i] * (1 - p.values[i]);
    Square result = {.size = weights.count};
    for (int j = 0; j < weights.count; ++j)
        for (int k = 0; k <= j; ++k) {
            double total = 0;
            for (int i = 0; i < data->rows; ++i)
                total += variance[i] * data->values[i][j] * data->values[i][k];
            result.values[j][k] = total / (double)data->rows;
            if (j == k && j)
                result.values[j][k] += lambda;
            result.values[k][j] = result.values[j][k];
        }
    return result;
}
double length(Vector vector) {
    double total = 0;
    for (int j = 0; j < vector.count; ++j)
        total += vector.values[j] * vector.values[j];
    return sqrt(total);
}
