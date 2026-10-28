#include "forecasting.h"
Vector difference(Vector values, int kind, int season) {
    int offset = kind == 0 ? 0 : kind == 1 ? 1 : kind == 2 ? season : season + 1;
    Vector result = {0};
    for (int t = offset; t < values.count; ++t)
        result.values[result.count++] = kind == 0   ? values.values[t]
                                        : kind == 1 ? values.values[t] - values.values[t - 1]
                                        : kind == 2
                                            ? values.values[t] - values.values[t - season]
                                            : (values.values[t] - values.values[t - 1]) -
                                                  (values.values[t - season] - values.values[t - season - 1]);
    return result;
}
Correlation autocorrelation(Vector values, int lag) {
    double average = mean(values), deltas[168], squares = 0;
    for (int i = 0; i < values.count; ++i) {
        deltas[i] = values.values[i] - average;
        squares += deltas[i] * deltas[i];
    }
    Correlation result = {
        .mean = average, .variance = squares / (double)values.count, .acf = {.count = lag + 1}};
    result.acf.values[0] = 1;
    for (int k = 1; k <= lag; ++k) {
        double value = 0;
        for (int i = 0; i < values.count - k; ++i)
            value += deltas[i] * deltas[i + k];
        result.acf.values[k] = value / (double)values.count / result.variance;
    }
    return result;
}
Levinson durbin_levinson(Vector acf, int lag) {
    Levinson result = {0};
    result.partial.count = result.variance.count = lag + 1;
    result.variance.values[0] = 1;
    for (int k = 1; k <= lag; ++k) {
        double value = 0;
        for (int j = 1; j < k; ++j)
            value += result.coefficients[k - 1][j] * acf.values[k - j];
        double theta = (acf.values[k] - value) / result.variance.values[k - 1];
        result.partial.values[k] = theta;
        for (int j = 1; j < k; ++j)
            result.coefficients[k][j] =
                result.coefficients[k - 1][j] - theta * result.coefficients[k - 1][k - j];
        result.coefficients[k][k] = theta;
        result.variance.values[k] = result.variance.values[k - 1] * (1 - theta * theta);
    }
    return result;
}
Vector ar_residuals(Vector values, double average, Vector coefficients) {
    Vector result = {0};
    for (int i = coefficients.count; i < values.count; ++i) {
        double value = 0;
        for (int j = 0; j < coefficients.count; ++j)
            value += coefficients.values[j] * (values.values[i - j - 1] - average);
        result.values[result.count++] = values.values[i] - average - value;
    }
    return result;
}
Vector ar_forecast(Vector values, Vector differenced, int kind, int season, int origin, int steps,
                   double average, Vector coefficients) {
    int offset = kind == 0 ? 0 : kind == 1 ? 1 : kind == 2 ? season : season + 1;
    Vector working = differenced, predictions = {0}, levels = values, result = {0};
    working.count = origin - offset;
    levels.count = origin;
    for (int k = 0; k < steps; ++k) {
        double value = 0;
        for (int j = 0; j < coefficients.count; ++j)
            value += coefficients.values[j] * (working.values[working.count - j - 1] - average);
        working.values[working.count++] = average + value;
        predictions.values[predictions.count++] = average + value;
    }
    for (int k = 0; k < steps; ++k) {
        double value = predictions.values[k];
        if (kind == 1)
            value += levels.values[levels.count - 1];
        else if (kind == 2)
            value += levels.values[levels.count - season];
        else if (kind == 3)
            value = value + levels.values[levels.count - 1] + levels.values[levels.count - season] -
                    levels.values[levels.count - season - 1];
        levels.values[levels.count++] = value;
        result.values[result.count++] = value;
    }
    return result;
}
void ljung_box(Vector residuals, int lag, double *statistic, double *probability) {
    Vector acf = autocorrelation(residuals, lag).acf;
    double value = 0;
    for (int k = 1; k <= lag; ++k)
        value += acf.values[k] * acf.values[k] / (double)(residuals.count - k);
    double q = (double)residuals.count * (double)(residuals.count + 2) * value, x = q / 2, term = 1, sum = 1;
    for (int i = 1; i < lag / 2; ++i) {
        term = term * x / i;
        sum += term;
    }
    *statistic = q;
    *probability = exp(-x) * sum;
}
