#include "forecasting.h"
double total(Vector values) {
    double result = 0;
    for (int i = 0; i < values.count; ++i)
        result += values.values[i];
    return result;
}
double mean(Vector values) {
    return total(values) / (double)values.count;
}
double sample_variance(Vector values) {
    double average = mean(values), squares = 0;
    for (int i = 0; i < values.count; ++i)
        squares += (values.values[i] - average) * (values.values[i] - average);
    return squares / (double)(values.count - 1);
}
double rmse(Vector values) {
    double squares = 0;
    for (int i = 0; i < values.count; ++i)
        squares += values.values[i] * values.values[i];
    return sqrt(squares / (double)values.count);
}
Decomposition decompose(Vector values, int season) {
    int size = values.count, half = season / 2;
    Decomposition result = {0};
    result.trend.count = result.residual_add.count = result.residual_mult.count = size;
    result.additive.count = result.multiplicative.count = season;
    for (int t = 0; t < size; ++t)
        result.trend.values[t] = result.residual_add.values[t] = result.residual_mult.values[t] = NAN;
    for (int t = half; t < size - half; ++t) {
        double value = 0.5 * values.values[t - half];
        for (int i = t - half + 1; i < t + half; ++i)
            value += values.values[i];
        value += 0.5 * values.values[t + half];
        result.trend.values[t] = value / season;
    }
    for (int j = 0; j < season; ++j) {
        double additive = 0, multiplicative = 0;
        int count = 0;
        for (int t = half; t < size - half; ++t)
            if (t % season == j) {
                additive += values.values[t] - result.trend.values[t];
                multiplicative += values.values[t] / result.trend.values[t];
                ++count;
            }
        result.additive.values[j] = additive / count;
        result.multiplicative.values[j] = multiplicative / count;
    }
    double average_add = mean(result.additive), average_mult = mean(result.multiplicative);
    for (int j = 0; j < season; ++j) {
        result.additive.values[j] -= average_add;
        result.multiplicative.values[j] /= average_mult;
    }
    for (int t = half; t < size - half; ++t) {
        result.residual_add.values[t] =
            values.values[t] - result.trend.values[t] - result.additive.values[t % season];
        result.residual_mult.values[t] =
            values.values[t] / (result.trend.values[t] * result.multiplicative.values[t % season]);
    }
    return result;
}
void regression(Vector values, double *intercept, double *slope) {
    double center = ((double)values.count + 1) / 2, average = mean(values), numerator = 0, denominator = 0;
    for (int t = 0; t < values.count; ++t) {
        double delta = (double)(t + 1) - center;
        numerator += delta * (values.values[t] - average);
        denominator += delta * delta;
    }
    *slope = numerator / denominator;
    *intercept = average - *slope * center;
}
