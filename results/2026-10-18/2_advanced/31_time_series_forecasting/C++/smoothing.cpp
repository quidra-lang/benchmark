#include "forecasting.hpp"
Smoothed smooth(int method, const Vector &values, int season, SmoothParameters p) {
    const bool winters = method == 6 || method == 7;
    State state{values[0], 0, {}};
    if (winters) {
        state.level = total(Vector(values.begin(), values.begin() + season)) / season;
        state.slope =
            (total(Vector(values.begin() + season, values.begin() + 2 * season)) / season - state.level) /
            season;
        for (int j = 0; j < season; ++j)
            state.seasonal.push_back(method == 6 ? values[j] - state.level : values[j] / state.level);
    } else if (method != 3)
        state.slope = (values[season] - values[0]) / season;
    Smoothed result;
    for (std::size_t t = 0; t < values.size(); ++t) {
        result.states.push_back(state);
        const double observed = values[t];
        double predicted, next_level, next_slope;
        if (method == 3) {
            predicted = state.level;
            next_level = p.alpha * observed + (1 - p.alpha) * state.level;
            next_slope = state.slope;
        } else if (winters) {
            const int position = int(t) % season;
            const double previous = state.seasonal[position], base = state.level + state.slope;
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
        result.residuals.push_back(observed - predicted);
        state.level = next_level;
        state.slope = next_slope;
    }
    result.states.push_back(state);
    return result;
}
Vector smooth_forecast(int method, const State &state, SmoothParameters p, int origin, int steps,
                       int season) {
    Vector result;
    double power = p.phi, accumulated = 0;
    for (int k = 1; k <= steps; ++k) {
        if (method == 3)
            result.push_back(state.level);
        else if (method == 4 || method == 5) {
            accumulated += power;
            result.push_back(state.level + accumulated * state.slope);
            power *= p.phi;
        } else {
            const double component = state.seasonal[(origin + k - 1) % season],
                         base = state.level + k * state.slope;
            result.push_back(method == 6 ? base + component : base * component);
        }
    }
    return result;
}
