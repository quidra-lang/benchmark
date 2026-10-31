using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record SmoothState(double level, double slope, double[] components);
sealed record SmoothRun(double[] errors, List<SmoothState> states);
static class Smoothing {
    public static SmoothRun Recurse(string name, double[] values, int season, double alpha, double beta,
                                    double gamma, double phi) {
        bool seasonal = name.StartsWith("hw_");
        double level = values[0], slope = name.Equals("ses") ? 0 : (values[season] - values[0]) / season;
        double[] components = new double[season];
        if (seasonal) {
            double first = 0, second = 0;
            for (int t = 0; t < season; t++)
                first += values[t];
            for (int t = season; t < 2 * season; t++)
                second += values[t];
            level = first / season;
            slope = (second / season - level) / season;
            for (int j = 0; j < season; j++)
                components[j] = name.Equals("hw_add") ? values[j] - level : values[j] / level;
        }
        List<SmoothState> states = new();
        double[] errors = new double[values.Length];
        for (int t = 0; t < values.Length; t++) {
            states.Add(new SmoothState(level, slope, components.ToArray()));
            double observed = values[t], predicted, nextLevel, nextSlope;
            if (name.Equals("ses")) {
                predicted = level;
                nextLevel = alpha * observed + (1 - alpha) * level;
                nextSlope = slope;
            } else if (seasonal) {
                int position = t % season;
                double previous = components[position], baseValue = level + slope;
                if (name.Equals("hw_add")) {
                    predicted = baseValue + previous;
                    nextLevel = alpha * (observed - previous) + (1 - alpha) * baseValue;
                    components[position] = gamma * (observed - baseValue) + (1 - gamma) * previous;
                } else {
                    predicted = baseValue * previous;
                    nextLevel = alpha * (observed / previous) + (1 - alpha) * baseValue;
                    components[position] = gamma * (observed / baseValue) + (1 - gamma) * previous;
                }
                nextSlope = beta * (nextLevel - level) + (1 - beta) * slope;
            } else {
                predicted = level + phi * slope;
                nextLevel = alpha * observed + (1 - alpha) * predicted;
                nextSlope = beta * (nextLevel - level) + (1 - beta) * phi * slope;
            }
            errors[t] = observed - predicted;
            level = nextLevel;
            slope = nextSlope;
        }
        states.Add(new SmoothState(level, slope, components.ToArray()));
        return new SmoothRun(errors, states);
    }
    public static double[] Forecast(string name, SmoothState state, int origin, int steps, int season,
                                    double phi) {
        double[] result = new double[steps];
        double power = phi, accumulated = 0;
        for (int k = 1; k <= steps; k++) {
            if (name.Equals("ses"))
                result[k - 1] = state.level;
            else if (name.Equals("holt") || name.Equals("damped")) {
                accumulated += power;
                result[k - 1] = state.level + accumulated * state.slope;
                power *= phi;
            } else {
                double baseValue = state.level + k * state.slope,
                       component = state.components[(origin + k - 1) % season];
                result[k - 1] = name.Equals("hw_add") ? baseValue + component : baseValue * component;
            }
        }
        return result;
    }
}
