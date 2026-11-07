using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Diagnostics {
    public sealed class Result {
        public double[] standardized, studentized, cooks, dffits;
        public string[] flags;
        public double[][] dfbetas;
        public double dw, bp, bpP, jb, jbP, skewness, kurtosis;
        public int bpDegrees;
    }
    public static Result Compute(double[][] x, double[] y, double[] w, QrSolver.Fit fit, double sigma,
                                 int degrees, Dataframe.Settings settings) {
        int n = y.Length, r = fit.rank;
        Result result = new Result();
        result.standardized = new double[n];
        result.studentized = new double[n];
        result.cooks = new double[n];
        result.dffits = new double[n];
        result.flags = new string[n];
        result.dfbetas = Enumerable.Range(0, n)
                             .Select(
                                 _ => new double[r])
                             .ToArray();
        for (int i = 0; i < n; i++) {
            double h = fit.leverage[i], z = fit.epsilon[i] / (sigma * Math.Sqrt(1 - h));
            result.standardized[i] = z;
            result.studentized[i] = z * Math.Sqrt((degrees - 1) / (degrees - z * z));
            result.cooks[i] = z * z * h / (r * (1 - h));
            result.dffits[i] = result.studentized[i] * Math.Sqrt(h / (1 - h));
            string flags = "";
            if (h > settings.Number("LEVERAGE") * r / n)
                flags += "H";
            if (Math.Abs(result.studentized[i]) > settings.Number("STUDENTIZED"))
                flags += "O";
            if (result.cooks[i] > settings.Number("COOK") / n)
                flags += "C";
            if (Math.Abs(result.dffits[i]) > settings.Number("DFFITS") * Math.Sqrt((double)r / n))
                flags += "F";
            result.flags[i] = flags.Length == 0 ? "-" : flags;
            double deleted = sigma * Math.Sqrt((degrees - z * z) / (degrees - 1));
            for (int k = 0; k < r; k++)
                result.dfbetas[i][k] =
                    fit.g[i][k] * fit.epsilon[i] / (1 - h) / (deleted * Math.Sqrt(fit.variance[k]));
        }
        double dw = 0;
        for (int i = 1; i < n; i++) {
            double difference = fit.epsilon[i] - fit.epsilon[i - 1];
            dw += difference * difference;
        }
        result.dw = dw / fit.rss;
        double[][] accepted = Enumerable.Range(0, n)
                                  .Select(
                                      _ => new double[r])
                                  .ToArray();
        double[] squares = new double[n], ones = new double[n];
        double sum = 0;
        for (int i = 0; i < n; i++) {
            for (int k = 0; k < r; k++)
                accepted[i][k] = x[i][fit.accepted[k]];
            squares[i] = fit.epsilon[i] * fit.epsilon[i];
            sum += squares[i];
            ones[i] = 1;
        }
        QrSolver.Fit auxiliary = QrSolver.Solve(accepted, squares, ones, settings.Number("RANK_TOL"));
        double mean = sum / n, total = 0;
        foreach (double value in squares)
            total += (value - mean) * (value - mean);
        result.bp = n * (1 - auxiliary.rss / total);
        result.bpDegrees = auxiliary.rank - 1;
        result.bpP = Inference.Pchi(result.bp, result.bpDegrees);
        sum = 0;
        foreach (double value in fit.epsilon)
            sum += value;
        mean = sum / n;
        double m2 = 0, m3 = 0, m4 = 0;
        foreach (double value in fit.epsilon) {
            double delta = value - mean;
            m2 += delta * delta;
            m3 += delta * delta * delta;
            m4 += delta * delta * delta * delta;
        }
        m2 /= n;
        m3 /= n;
        m4 /= n;
        result.skewness = m3 / (m2 * Math.Sqrt(m2));
        result.kurtosis = m4 / (m2 * m2);
        result.jb =
            n / 6.0 * (result.skewness * result.skewness + (result.kurtosis - 3) * (result.kurtosis - 3) / 4);
        result.jbP = Inference.Pchi(result.jb, 2);
        return result;
    }
}
