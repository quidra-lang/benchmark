using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Smo {
    public record Pass(bool full, int examined, int changed, double[] alpha) {
    }
    public sealed class Model {
        public List<Kernels.Point> points;
        public int[] labels;
        public Kernels.Kernel kernel;
        public double[][] matrix;
        public double c, tolerance, eps, b;
        public double[] alpha, errors;
        public int maximum, fullPasses, nonboundPasses, examined, steps;
        public int[] choices = new int[3], clipping = new int[3];
        public List<Pass> records = new();
        public bool converged;
        public Model(List<Kernels.Point> points, int[] labels, Kernels.Kernel kernel, double[][] matrix,
                     double c, Dataset.Settings settings) {
            this.points = points;
            this.labels = labels;
            this.kernel = kernel;
            this.matrix = matrix;
            this.c = c;
            tolerance = settings.tolerance;
            eps = settings.eps;
            maximum = settings.maximum;
            alpha = new double[points.Count];
            errors = new double[points.Count];
            for (int i = 0; i < labels.Length; i++)
                errors[i] = -labels[i];
        }
        public int Passes() {
            return fullPasses + nonboundPasses;
        }
        public bool Nonbound(int i) {
            return alpha[i] > 0 && alpha[i] < c;
        }
        public double Snap(double a) {
            return a < 0.00000001 ? 0 : a > c - 0.00000001 ? c : a;
        }
        public bool Take(int first, int second) {
            if (first == second)
                return false;
            double alpha1 = alpha[first], alpha2 = alpha[second], e1 = errors[first], e2 = errors[second];
            int y1 = labels[first], y2 = labels[second];
            double lo = y1 != y2 ? Math.Max(0, alpha2 - alpha1) : Math.Max(0, alpha2 + alpha1 - c),
                   hi = y1 != y2 ? Math.Min(c, c + alpha2 - alpha1) : Math.Min(c, alpha2 + alpha1);
            if (lo == hi)
                return false;
            double k11 = matrix[first][first], k12 = matrix[first][second], k22 = matrix[second][second],
                   eta = k11 + k22 - 2 * k12;
            if (eta <= 0)
                return false;
            double a2 = alpha2 + y2 * (e1 - e2) / eta;
            int clip = 0;
            if (a2 < lo) {
                a2 = lo;
                clip = 1;
            } else if (a2 > hi) {
                a2 = hi;
                clip = 2;
            }
            a2 = Snap(a2);
            if (Math.Abs(a2 - alpha2) < eps * (a2 + alpha2 + eps))
                return false;
            double a1 = Snap(alpha1 + y1 * y2 * (alpha2 - a2)), t1 = y1 * (a1 - alpha1),
                   t2 = y2 * (a2 - alpha2), b1 = e1 + t1 * k11 + t2 * k12 + b,
                   b2 = e2 + t1 * k12 + t2 * k22 + b;
            double threshold = a1 > 0 && a1 < c   ? b1
                               : a2 > 0 && a2 < c ? b2
                                                  : (b1 + b2) / 2,
                   delta = threshold - b;
            for (int i = 0; i < errors.Length; i++)
                errors[i] = errors[i] + (t1 * matrix[first][i] + t2 * matrix[second][i] - delta);
            if (a1 > 0 && a1 < c)
                errors[first] = 0;
            if (a2 > 0 && a2 < c)
                errors[second] = 0;
            alpha[first] = a1;
            alpha[second] = a2;
            b = threshold;
            steps++;
            clipping[clip]++;
            return true;
        }
        public int Examine(int second) {
            examined++;
            double r = errors[second] * labels[second];
            if (!(r < -tolerance && alpha[second] < c || r > tolerance && alpha[second] > 0))
                return 0;
            int partner = -1;
            double largest = -1;
            for (int i = 0; i < alpha.Length; i++)
                if (i != second && Nonbound(i)) {
                    double difference = Math.Abs(errors[i] - errors[second]);
                    if (difference > largest) {
                        largest = difference;
                        partner = i;
                    }
                }
            if (partner >= 0 && Take(partner, second)) {
                choices[0]++;
                return 1;
            }
            for (int i = 0; i < alpha.Length; i++)
                if (Nonbound(i) && Take(i, second)) {
                    choices[1]++;
                    return 1;
                }
            for (int i = 0; i < alpha.Length; i++)
                if (Take(i, second)) {
                    choices[2]++;
                    return 1;
                }
            return 0;
        }
        public Model Fit() {
            bool all = true;
            while (true) {
                int before = examined, changed = 0;
                for (int i = 0; i < alpha.Length; i++)
                    if (all || Nonbound(i))
                        changed += Examine(i);
                if (all)
                    fullPasses++;
                else
                    nonboundPasses++;
                records.Add(new Pass(all, examined - before, changed, all ? alpha.ToArray() : null));
                if (all && changed == 0) {
                    converged = true;
                    break;
                }
                if (Passes() == maximum)
                    break;
                if (all)
                    all = false;
                else if (changed == 0)
                    all = true;
            }
            return this;
        }
        public double Decision(Kernels.Point point) {
            double sum = 0;
            for (int i = 0; i < alpha.Length; i++)
                if (alpha[i] > 0)
                    sum += alpha[i] * labels[i] * kernel.Value(points[i], point);
            return sum - b;
        }
        public double[] Raw(double[] coefficients) {
            double[] values = new double[alpha.Length];
            for (int i = 0; i < values.Length; i++)
                for (int j = 0; j < alpha.Length; j++)
                    if (coefficients[j] > 0)
                        values[i] += coefficients[j] * labels[j] * matrix[i][j];
            return values;
        }
        public double[] Training() {
            double[] values = Raw(alpha);
            for (int i = 0; i < values.Length; i++)
                values[i] -= b;
            return values;
        }
        public double[] Decisions(List<Dataset.Example> examples) {
            double[] values = new double[examples.Count];
            for (int i = 0; i < values.Length; i++)
                values[i] = Decision(examples[i].point);
            return values;
        }
    }
    public static Model Train(List<Kernels.Point> points, int[] labels, Kernels.Kernel kernel,
                              double[][] matrix, double c, Dataset.Settings settings) {
        return new Model(points, labels, kernel, matrix, c, settings).Fit();
    }
}
