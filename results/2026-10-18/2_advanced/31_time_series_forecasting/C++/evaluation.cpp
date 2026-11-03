#include "forecasting.hpp"
double scale_delta(const Vector &training, int season) {
    double value = 0;
    for (int t = season; t < int(training.size()); ++t)
        value += std::abs(training[t] - training[t - season]);
    return value / double(training.size() - season);
}
double winkler(double actual, double low, double high, double penalty) {
    if (actual < low)
        return high - low + penalty * (low - actual);
    if (actual > high)
        return high - low + penalty * (actual - high);
    return high - low;
}
Accuracy evaluate(const Vector &actual, const Vector &forecast, const Vector &sigma, double z80, double z95,
                  double delta) {
    Accuracy result;
    double squares = 0;
    for (std::size_t i = 0; i < actual.size(); ++i) {
        const double error = actual[i] - forecast[i];
        result.me += error;
        result.mae += std::abs(error);
        squares += error * error;
        result.mape += std::abs(error) / actual[i];
        result.smape += 2 * std::abs(error) / (std::abs(actual[i]) + std::abs(forecast[i]));
        const double lo80 = forecast[i] - z80 * sigma[i], hi80 = forecast[i] + z80 * sigma[i],
                     lo95 = forecast[i] - z95 * sigma[i], hi95 = forecast[i] + z95 * sigma[i];
        if (lo80 <= actual[i] && actual[i] <= hi80)
            ++result.cover80;
        if (lo95 <= actual[i] && actual[i] <= hi95)
            ++result.cover95;
        result.winkler80 += winkler(actual[i], lo80, hi80, 10);
        result.winkler95 += winkler(actual[i], lo95, hi95, 40);
    }
    const double count = double(actual.size());
    result.me /= count;
    result.mae /= count;
    result.rmse = std::sqrt(squares / count);
    result.mape = 100 * result.mape / count;
    result.smape = 100 * result.smape / count;
    result.mase = result.mae / delta;
    result.winkler80 /= count;
    result.winkler95 /= count;
    return result;
}
std::vector<int> rank_accuracy(std::vector<Accuracy> &measures) {
    std::vector<int> order(measures.size());
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(),
                     [&](int a, int b) { return measures[a].rmse < measures[b].rmse; });
    for (std::size_t i = 0; i < order.size(); ++i)
        measures[order[i]].rank = int(i + 1);
    return order;
}
