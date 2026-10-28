#include "forecasting.hpp"
double total(const Vector &values) {
    double result = 0;
    for (double value : values)
        result += value;
    return result;
}
double mean(const Vector &values) {
    return total(values) / double(values.size());
}
double sample_variance(const Vector &values) {
    const double average = mean(values);
    double squares = 0;
    for (double value : values)
        squares += (value - average) * (value - average);
    return squares / double(values.size() - 1);
}
double rmse(const Vector &values) {
    double squares = 0;
    for (double value : values)
        squares += value * value;
    return std::sqrt(squares / double(values.size()));
}
Decomposition decompose(const Vector &values, int season) {
    const int size = int(values.size()), half = season / 2;
    const double undefined = std::numeric_limits<double>::quiet_NaN();
    Decomposition result{Vector(size, undefined), Vector(season), Vector(season), Vector(size, undefined),
                         Vector(size, undefined)};
    for (int t = half; t < size - half; ++t) {
        double value = 0.5 * values[t - half];
        for (int i = t - half + 1; i < t + half; ++i)
            value += values[i];
        value += 0.5 * values[t + half];
        result.trend[t] = value / season;
    }
    for (int j = 0; j < season; ++j) {
        double additive = 0, multiplicative = 0;
        int count = 0;
        for (int t = half; t < size - half; ++t)
            if (t % season == j) {
                additive += values[t] - result.trend[t];
                multiplicative += values[t] / result.trend[t];
                ++count;
            }
        result.additive[j] = additive / count;
        result.multiplicative[j] = multiplicative / count;
    }
    const double average_add = mean(result.additive), average_mult = mean(result.multiplicative);
    for (int j = 0; j < season; ++j) {
        result.additive[j] -= average_add;
        result.multiplicative[j] /= average_mult;
    }
    for (int t = half; t < size - half; ++t) {
        result.residual_add[t] = values[t] - result.trend[t] - result.additive[t % season];
        result.residual_mult[t] = values[t] / (result.trend[t] * result.multiplicative[t % season]);
    }
    return result;
}
std::pair<double, double> regression(const Vector &values) {
    const double center = (double(values.size()) + 1) / 2, average = mean(values);
    double numerator = 0, denominator = 0;
    for (std::size_t t = 0; t < values.size(); ++t) {
        const double delta = double(t + 1) - center;
        numerator += delta * (values[t] - average);
        denominator += delta * delta;
    }
    const double slope = numerator / denominator;
    return {average - slope * center, slope};
}
