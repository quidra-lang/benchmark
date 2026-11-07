import java.util.*;

record Correlations(double mean, double variance, double[] acf) {}
record Durbin(double[][] coefficients, double[] partial, double[] variances) {}
final class Autoregression {
    static final String[] KINDS = {"none", "first", "seasonal", "both"};
    static int offset(String kind, int season) {
        return kind.equals("none") ? 0
        : kind.equals("first")     ? 1
        : kind.equals("seasonal")  ? season
                                   : season + 1;
    }
    static double[] difference(double[] values, int season, String kind) {
        int offset = offset(kind, season);
        double[] result = new double[values.length - offset];
        for (int t = offset; t < values.length; t++)
            result[t - offset] =
                kind.equals("none")    ? values[t]
                : kind.equals("first") ? values[t] - values[t - 1]
                : kind.equals("seasonal")
                    ? values[t] - values[t - season]
                    : (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1]);
        return result;
    }
    static Correlations correlations(double[] values, int maximum) {
        double mean = Decomposition.sum(values) / values.length;
        double[] centered = new double[values.length];
        double variance = 0;
        for (int i = 0; i < values.length; i++) {
            centered[i] = values[i] - mean;
            variance += centered[i] * centered[i];
        }
        variance /= values.length;
        double[] acf = new double[maximum + 1];
        acf[0] = 1;
        for (int lag = 1; lag <= maximum; lag++) {
            double total = 0;
            for (int i = 0; i < values.length - lag; i++)
                total += centered[i] * centered[i + lag];
            acf[lag] = total / values.length / variance;
        }
        return new Correlations(mean, variance, acf);
    }
    static Durbin durbin(double[] correlations) {
        int count = correlations.length;
        double[][] coefficients = new double[count][];
        coefficients[0] = new double[0];
        double[] partial = new double[count], variances = new double[count];
        variances[0] = 1;
        for (int order = 1; order < count; order++) {
            double[] previous = coefficients[order - 1];
            double correction = 0;
            for (int j = 1; j < order; j++)
                correction += previous[j - 1] * correlations[order - j];
            double theta = (correlations[order] - correction) / variances[order - 1];
            double[] current = new double[order];
            for (int j = 1; j < order; j++)
                current[j - 1] = previous[j - 1] - theta * previous[order - j - 1];
            current[order - 1] = theta;
            coefficients[order] = current;
            partial[order] = theta;
            variances[order] = variances[order - 1] * (1 - theta * theta);
        }
        return new Durbin(coefficients, partial, variances);
    }
    static double[] residuals(double[] values, double mean, double[] coefficients) {
        int order = coefficients.length;
        double[] errors = new double[values.length - order];
        for (int i = order; i < values.length; i++) {
            double total = 0;
            for (int j = 1; j <= order; j++)
                total += coefficients[j - 1] * (values[i - j] - mean);
            errors[i - order] = values[i] - mean - total;
        }
        return errors;
    }
    static double[] forecast(double[] values, double[] differenced, String kind, double mean,
                             double[] coefficients, int origin, int steps, int season) {
        int offset = offset(kind, season), count = origin - offset;
        double[] transformed = Arrays.copyOf(differenced, count + steps),
                 extended = Arrays.copyOf(values, origin + steps), result = new double[steps];
        for (int k = 0; k < steps; k++) {
            double total = 0;
            for (int j = 1; j <= coefficients.length; j++)
                total += coefficients[j - 1] * (transformed[count + k - j] - mean);
            double predicted = mean + total;
            transformed[count + k] = predicted;
            int position = origin + k;
            if (kind.equals("first"))
                predicted += extended[position - 1];
            else if (kind.equals("seasonal"))
                predicted += extended[position - season];
            else if (kind.equals("both"))
                predicted = predicted + extended[position - 1] + extended[position - season] -
                            extended[position - season - 1];
            extended[position] = predicted;
            result[k] = predicted;
        }
        return result;
    }
    static double[] ljung(double[] errors, int lag) {
        double[] correlations = correlations(errors, lag).acf();
        int count = errors.length;
        double total = 0;
        for (int k = 1; k <= lag; k++)
            total += correlations[k] * correlations[k] / (count - k);
        double q = count * (count + 2.0) * total, x = q / 2, term = 1, terms = 1;
        for (int i = 1; i < lag / 2; i++) {
            term = term * x / i;
            terms += term;
        }
        return new double[] {q, Math.exp(-x) * terms};
    }
}
