#include "forecasting.hpp"
Vector difference(const Vector &values, int kind, int season) {
    const int offset = kind == 0 ? 0 : kind == 1 ? 1 : kind == 2 ? season : season + 1;
    Vector result;
    for (int t = offset; t < int(values.size()); ++t)
        result.push_back(kind == 0   ? values[t]
                         : kind == 1 ? values[t] - values[t - 1]
                         : kind == 2
                             ? values[t] - values[t - season]
                             : (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1]));
    return result;
}
Correlation autocorrelation(const Vector &values, int lag) {
    const double average = mean(values);
    Vector deltas;
    double squares = 0;
    for (double value : values) {
        const double delta = value - average;
        deltas.push_back(delta);
        squares += delta * delta;
    }
    Correlation result{average, squares / double(values.size()), Vector(lag + 1, 1)};
    for (int k = 1; k <= lag; ++k) {
        double value = 0;
        for (int i = 0; i < int(values.size()) - k; ++i)
            value += deltas[i] * deltas[i + k];
        result.acf[k] = value / double(values.size()) / result.variance;
    }
    return result;
}
Levinson durbin_levinson(const Vector &acf, int lag) {
    Levinson result{Matrix(lag + 1, Vector(lag + 1)), Vector(lag + 1), Vector(lag + 1, 1)};
    for (int k = 1; k <= lag; ++k) {
        double value = 0;
        for (int j = 1; j < k; ++j)
            value += result.coefficients[k - 1][j] * acf[k - j];
        const double theta = (acf[k] - value) / result.variance[k - 1];
        result.partial[k] = theta;
        for (int j = 1; j < k; ++j)
            result.coefficients[k][j] =
                result.coefficients[k - 1][j] - theta * result.coefficients[k - 1][k - j];
        result.coefficients[k][k] = theta;
        result.variance[k] = result.variance[k - 1] * (1 - theta * theta);
    }
    return result;
}
Vector ar_residuals(const Vector &values, double average, const Vector &coefficients) {
    Vector result;
    for (int i = int(coefficients.size()); i < int(values.size()); ++i) {
        double value = 0;
        for (std::size_t j = 0; j < coefficients.size(); ++j)
            value += coefficients[j] * (values[i - int(j) - 1] - average);
        result.push_back(values[i] - average - value);
    }
    return result;
}
Vector ar_forecast(const Vector &values, const Vector &differenced, int kind, int season, int origin,
                   int steps, double average, const Vector &coefficients) {
    const int offset = kind == 0 ? 0 : kind == 1 ? 1 : kind == 2 ? season : season + 1;
    Vector working(differenced.begin(), differenced.begin() + origin - offset), predictions;
    for (int k = 0; k < steps; ++k) {
        double value = 0;
        for (std::size_t j = 0; j < coefficients.size(); ++j)
            value += coefficients[j] * (working[working.size() - j - 1] - average);
        working.push_back(average + value);
        predictions.push_back(working.back());
    }
    Vector levels(values.begin(), values.begin() + origin), result;
    for (double prediction : predictions) {
        double value = prediction;
        if (kind == 1)
            value += levels.back();
        else if (kind == 2)
            value += levels[levels.size() - season];
        else if (kind == 3)
            value =
                value + levels.back() + levels[levels.size() - season] - levels[levels.size() - season - 1];
        levels.push_back(value);
        result.push_back(value);
    }
    return result;
}
std::pair<double, double> ljung_box(const Vector &residuals, int lag) {
    const Vector acf = autocorrelation(residuals, lag).acf;
    double value = 0;
    for (int k = 1; k <= lag; ++k)
        value += acf[k] * acf[k] / double(residuals.size() - k);
    const double q = double(residuals.size()) * double(residuals.size() + 2) * value, x = q / 2;
    double term = 1, sum = 1;
    for (int i = 1; i < lag / 2; ++i) {
        term = term * x / i;
        sum += term;
    }
    return {q, std::exp(-x) * sum};
}
