import java.util.*;

record SmoothState(double level, double slope, double[] components) {}
record SmoothRun(double[] errors, List<SmoothState> states) {}
final class Smoothing {
    static SmoothRun recurse(String name, double[] values, int season, double alpha, double beta,
                             double gamma, double phi) {
        boolean seasonal = name.startsWith("hw_");
        double level = values[0], slope = name.equals("ses") ? 0 : (values[season] - values[0]) / season;
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
                components[j] = name.equals("hw_add") ? values[j] - level : values[j] / level;
        }
        List<SmoothState> states = new ArrayList<>();
        double[] errors = new double[values.length];
        for (int t = 0; t < values.length; t++) {
            states.add(new SmoothState(level, slope, components.clone()));
            double observed = values[t], predicted, nextLevel, nextSlope;
            if (name.equals("ses")) {
                predicted = level;
                nextLevel = alpha * observed + (1 - alpha) * level;
                nextSlope = slope;
            } else if (seasonal) {
                int position = t % season;
                double previous = components[position], base = level + slope;
                if (name.equals("hw_add")) {
                    predicted = base + previous;
                    nextLevel = alpha * (observed - previous) + (1 - alpha) * base;
                    components[position] = gamma * (observed - base) + (1 - gamma) * previous;
                } else {
                    predicted = base * previous;
                    nextLevel = alpha * (observed / previous) + (1 - alpha) * base;
                    components[position] = gamma * (observed / base) + (1 - gamma) * previous;
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
        states.add(new SmoothState(level, slope, components.clone()));
        return new SmoothRun(errors, states);
    }
    static double[] forecast(String name, SmoothState state, int origin, int steps, int season, double phi) {
        double[] result = new double[steps];
        double power = phi, accumulated = 0;
        for (int k = 1; k <= steps; k++) {
            if (name.equals("ses"))
                result[k - 1] = state.level();
            else if (name.equals("holt") || name.equals("damped")) {
                accumulated += power;
                result[k - 1] = state.level() + accumulated * state.slope();
                power *= phi;
            } else {
                double base = state.level() + k * state.slope(),
                       component = state.components()[(origin + k - 1) % season];
                result[k - 1] = name.equals("hw_add") ? base + component : base * component;
            }
        }
        return result;
    }
}
