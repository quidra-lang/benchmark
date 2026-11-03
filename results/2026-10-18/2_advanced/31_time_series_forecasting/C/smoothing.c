#include "forecasting.h"
Smoothed smooth(int method, Vector values, int season, SmoothParameters p) {
    bool winters = method == 6 || method == 7;
    State state = {.level = values.values[0]};
    if (winters) {
        double first = 0, second = 0;
        for (int j = 0; j < season; ++j)
            first += values.values[j];
        for (int j = season; j < 2 * season; ++j)
            second += values.values[j];
        state.level = first / season;
        state.slope = (second / season - state.level) / season;
        for (int j = 0; j < season; ++j)
            state.seasonal[j] = method == 6 ? values.values[j] - state.level : values.values[j] / state.level;
    } else if (method != 3)
        state.slope = (values.values[season] - values.values[0]) / season;
    Smoothed result = {0};
    result.residuals.count = values.count;
    for (int t = 0; t < values.count; ++t) {
        result.states[t] = state;
        double observed = values.values[t], predicted, next_level, next_slope;
        if (method == 3) {
            predicted = state.level;
            next_level = p.alpha * observed + (1 - p.alpha) * state.level;
            next_slope = state.slope;
        } else if (winters) {
            int position = t % season;
            double previous = state.seasonal[position], base = state.level + state.slope;
            if (method == 6) {
                predicted = base + previous;
                next_level = p.alpha * (observed - previous) + (1 - p.alpha) * base;
                state.seasonal[position] = p.gamma * (observed - base) + (1 - p.gamma) * previous;
            } else {
                predicted = base * previous;
                next_level = p.alpha * (observed / previous) + (1 - p.alpha) * base;
                state.seasonal[position] = p.gamma * (observed / base) + (1 - p.gamma) * previous;
            }
            next_slope = p.beta * (next_level - state.level) + (1 - p.beta) * state.slope;
        } else {
            predicted = state.level + p.phi * state.slope;
            next_level = p.alpha * observed + (1 - p.alpha) * predicted;
            next_slope = p.beta * (next_level - state.level) + (1 - p.beta) * p.phi * state.slope;
        }
        result.residuals.values[t] = observed - predicted;
        state.level = next_level;
        state.slope = next_slope;
    }
    result.states[values.count] = state;
    return result;
}
Vector smooth_forecast(int method, State state, SmoothParameters p, int origin, int steps, int season) {
    Vector result = {.count = steps};
    double power = p.phi, accumulated = 0;
    for (int k = 1; k <= steps; ++k) {
        double value;
        if (method == 3)
            value = state.level;
        else if (method == 4 || method == 5) {
            accumulated += power;
            value = state.level + accumulated * state.slope;
            power *= p.phi;
        } else {
            double component = state.seasonal[(origin + k - 1) % season],
                   base = state.level + k * state.slope;
            value = method == 6 ? base + component : base * component;
        }
        result.values[k - 1] = value;
    }
    return result;
}
