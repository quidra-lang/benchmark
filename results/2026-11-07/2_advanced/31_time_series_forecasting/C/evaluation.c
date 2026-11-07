#include "forecasting.h"
double scale_delta(Vector training, int season) {
    double value = 0;
    for (int t = season; t < training.count; ++t)
        value += fabs(training.values[t] - training.values[t - season]);
    return value / (double)(training.count - season);
}
double winkler(double actual, double low, double high, double penalty) {
    if (actual < low)
        return high - low + penalty * (low - actual);
    if (actual > high)
        return high - low + penalty * (actual - high);
    return high - low;
}
Accuracy evaluate(Vector actual, Vector forecast, Vector sigma, double z80, double z95, double delta) {
    Accuracy result = {0};
    double squares = 0;
    for (int i = 0; i < actual.count; ++i) {
        double a = actual.values[i], f = forecast.values[i], error = a - f;
        result.me += error;
        result.mae += fabs(error);
        squares += error * error;
        result.mape += fabs(error) / a;
        result.smape += 2 * fabs(error) / (fabs(a) + fabs(f));
        double lo80 = f - z80 * sigma.values[i], hi80 = f + z80 * sigma.values[i],
               lo95 = f - z95 * sigma.values[i], hi95 = f + z95 * sigma.values[i];
        if (lo80 <= a && a <= hi80)
            ++result.cover80;
        if (lo95 <= a && a <= hi95)
            ++result.cover95;
        result.winkler80 += winkler(a, lo80, hi80, 10);
        result.winkler95 += winkler(a, lo95, hi95, 40);
    }
    double count = actual.count;
    result.me /= count;
    result.mae /= count;
    result.rmse = sqrt(squares / count);
    result.mape = 100 * result.mape / count;
    result.smape = 100 * result.smape / count;
    result.mase = result.mae / delta;
    result.winkler80 /= count;
    result.winkler95 /= count;
    return result;
}
Indices rank_accuracy(Accuracy *measures, int count) {
    Indices order = {.count = count};
    for (int i = 0; i < count; ++i) {
        int at = i;
        while (at && measures[i].rmse < measures[order.values[at - 1]].rmse) {
            order.values[at] = order.values[at - 1];
            --at;
        }
        order.values[at] = i;
    }
    for (int i = 0; i < count; ++i)
        measures[order.values[i]].rank = i + 1;
    return order;
}
