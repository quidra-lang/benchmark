using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Correlations(double mean, double variance, double[] acf);
sealed record Durbin(double[][] coefficients, double[] partial, double[] variances);
static class Autoregression {
    public static readonly string[] KINDS = { "none", "first", "seasonal", "both" };
    public static int Offset(string kind, int season) {
        return kind.Equals("none")       ? 0
               : kind.Equals("first")    ? 1
               : kind.Equals("seasonal") ? season
                                         : season + 1;
    }
    public static double[] Difference(double[] values, int season, string kind) {
        int offset = Offset(kind, season);
        double[] result = new double[values.Length - offset];
        for (int t = offset; t < values.Length; t++)
            result[t - offset] =
                kind.Equals("none")    ? values[t]
                : kind.Equals("first") ? values[t] - values[t - 1]
                : kind.Equals("seasonal")
                    ? values[t] - values[t - season]
                    : (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1]);
        return result;
    }
    public static Correlations Correlations(double[] values, int maximum) {
        double mean = Decomposition.Sum(values) / values.Length;
        double[] centered = new double[values.Length];
        double variance = 0;
        for (int i = 0; i < values.Length; i++) {
            centered[i] = values[i] - mean;
            variance += centered[i] * centered[i];
        }
        variance /= values.Length;
        double[] acf = new double[maximum + 1];
        acf[0] = 1;
        for (int lag = 1; lag <= maximum; lag++) {
            double total = 0;
            for (int i = 0; i < values.Length - lag; i++)
                total += centered[i] * centered[i + lag];
            acf[lag] = total / values.Length / variance;
        }
        return new Correlations(mean, variance, acf);
    }
    public static Durbin Durbin(double[] correlations) {
        int count = correlations.Length;
        double[][] coefficients = new double [count][];
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
    public static double[] Residuals(double[] values, double mean, double[] coefficients) {
        int order = coefficients.Length;
        double[] errors = new double[values.Length - order];
        for (int i = order; i < values.Length; i++) {
            double total = 0;
            for (int j = 1; j <= order; j++)
                total += coefficients[j - 1] * (values[i - j] - mean);
            errors[i - order] = values[i] - mean - total;
        }
        return errors;
    }
    public static double[] Forecast(double[] values, double[] differenced, string kind, double mean,
                                    double[] coefficients, int origin, int steps, int season) {
        int offset = Offset(kind, season), count = origin - offset;
        double[] transformed = new double[count + steps], extended = new double[origin + steps],
                 result = new double[steps];
        Array.Copy(differenced, transformed, Math.Min(differenced.Length, transformed.Length));
        Array.Copy(values, extended, Math.Min(values.Length, extended.Length));
        for (int k = 0; k < steps; k++) {
            double total = 0;
            for (int j = 1; j <= coefficients.Length; j++)
                total += coefficients[j - 1] * (transformed[count + k - j] - mean);
            double predicted = mean + total;
            transformed[count + k] = predicted;
            int position = origin + k;
            if (kind.Equals("first"))
                predicted += extended[position - 1];
            else if (kind.Equals("seasonal"))
                predicted += extended[position - season];
            else if (kind.Equals("both"))
                predicted = predicted + extended[position - 1] + extended[position - season] -
                            extended[position - season - 1];
            extended[position] = predicted;
            result[k] = predicted;
        }
        return result;
    }
    public static double[] Ljung(double[] errors, int lag) {
        double[] correlations = Correlations(errors, lag).acf;
        int count = errors.Length;
        double total = 0;
        for (int k = 1; k <= lag; k++)
            total += correlations[k] * correlations[k] / (count - k);
        double q = count * (count + 2.0) * total, x = q / 2, term = 1, terms = 1;
        for (int i = 1; i < lag / 2; i++) {
            term = term * x / i;
            terms += term;
        }
        return new double[] { q, Math.Exp(-x) * terms };
    }
}
