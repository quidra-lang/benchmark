using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Em {
    public sealed class Model {
        public int k;
        public double[] weights;
        public double[][] means, cov;
        public Model(int k) {
            this.k = k;
            weights = new double[k];
            means = Enumerable.Range(0, k)
                        .Select(
                            _ => new double[2])
                        .ToArray();
            cov = Enumerable.Range(0, k)
                      .Select(
                          _ => new double[3])
                      .ToArray();
        }
    }
    public record Step(double[][] responsibilities, double[] density, double[][] scores, double loglik) {
    }
    public record Run(Model model, Step step, List<Double> trace) {
    }
    public static Model Adjust(Model source, string type) {
        int k = source.k;
        Model result = new Model(k);
        for (int j = 0; j < k; j++) {
            result.weights[j] = source.weights[j];
            result.means[j] = source.means[j].ToArray();
            result.cov[j] = source.cov[j].ToArray();
        }
        if (type.Equals("TIED")) {
            double[] shared = new double[3];
            for (int j = 0; j < k; j++)
                for (int c = 0; c < 3; c++)
                    shared[c] += source.weights[j] * source.cov[j][c];
            for (int j = 0; j < k; j++)
                result.cov[j] = shared.ToArray();
        } else if (type.Equals("DIAG"))
            for (int j = 0; j < k; j++)
                result.cov[j][1] = 0;
        else if (type.Equals("SPHERICAL"))
            for (int j = 0; j < k; j++) {
                double v = (source.cov[j][0] + source.cov[j][2]) / 2;
                result.cov[j] = new double[] { v, 0, v };
            }
        return result;
    }
    public static Step Expectation(List<Dataset.Point> points, Model model) {
        int n = points.Count, k = model.k;
        double[][] r = Enumerable.Range(0, n)
                           .Select(
                               _ => new double[k])
                           .ToArray(),
                   scores = Enumerable.Range(0, n)
                                .Select(
                                    _ => new double[k])
                                .ToArray();
        double[] density = new double[n];
        double loglik = 0;
        for (int i = 0; i < n; i++) {
            Dataset.Point point = points[i];
            double maximum = double.NegativeInfinity;
            for (int j = 0; j < k; j++) {
                scores[i][j] =
                    Gaussian.LogDensity(point.x, point.y, model.weights[j], model.means[j], model.cov[j]);
                maximum = Math.Max(maximum, scores[i][j]);
            }
            double sum = 0;
            for (int j = 0; j < k; j++) {
                r[i][j] = Math.Exp(scores[i][j] - maximum);
                sum += r[i][j];
            }
            for (int j = 0; j < k; j++)
                r[i][j] /= sum;
            density[i] = maximum + Math.Log(sum);
            loglik += density[i];
        }
        return new Step(r, density, scores, loglik);
    }
    public static Model Maximization(List<Dataset.Point> points, Step step, string type, double eps) {
        int n = points.Count, k = step.responsibilities[0].Length;
        Model result = new Model(k);
        double[] counts = new double[k];
        double[][] scatter = Enumerable.Range(0, k)
                                 .Select(
                                     _ => new double[3])
                                 .ToArray();
        for (int j = 0; j < k; j++) {
            double x = 0, y = 0;
            for (int i = 0; i < n; i++) {
                double r = step.responsibilities[i][j];
                counts[j] += r;
                x += r * points[i].x;
                y += r * points[i].y;
            }
            result.weights[j] = counts[j] / n;
            result.means[j][0] = x / counts[j];
            result.means[j][1] = y / counts[j];
            for (int i = 0; i < n; i++) {
                double r = step.responsibilities[i][j], dx = points[i].x - result.means[j][0],
                       dy = points[i].y - result.means[j][1];
                scatter[j][0] += r * dx * dx;
                scatter[j][1] += r * dx * dy;
                scatter[j][2] += r * dy * dy;
            }
        }
        if (type.Equals("TIED")) {
            double[] shared = new double[3];
            for (int j = 0; j < k; j++)
                for (int c = 0; c < 3; c++)
                    shared[c] += scatter[j][c];
            shared[0] = shared[0] / n + eps;
            shared[1] /= n;
            shared[2] = shared[2] / n + eps;
            for (int j = 0; j < k; j++)
                result.cov[j] = shared.ToArray();
        } else
            for (int j = 0; j < k; j++) {
                double a = scatter[j][0] / counts[j], b = scatter[j][1] / counts[j],
                       c = scatter[j][2] / counts[j];
                if (type.Equals("SPHERICAL")) {
                    double v = (a + c) / 2 + eps;
                    result.cov[j] = new double[] { v, 0, v };
                } else
                    result.cov[j] = new double[] { a + eps, type.Equals("DIAG") ? 0 : b, c + eps };
            }
        return result;
    }
    public static Run Fit(List<Dataset.Point> points, Model initial, string type, int iterations,
                          double eps) {
        Model model = Adjust(initial, type);
        Step step = Expectation(points, model);
        List<Double> trace = new();
        trace.Add(step.loglik);
        for (int t = 1; t <= iterations; t++) {
            model = Maximization(points, step, type, eps);
            step = Expectation(points, model);
            trace.Add(step.loglik);
        }
        return new Run(model, step, trace);
    }
}
