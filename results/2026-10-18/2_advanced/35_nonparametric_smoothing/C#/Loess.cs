using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Loess {
    public sealed record Round(double scale, int zeros, double change);
    public readonly Dataset.Series data;
    public readonly int degree, span;
    public readonly double[] rho, fitted, leverage;
    public readonly List<Round> rounds = new();
    public double edf;
    public static double Median(double[] values) {
        double[] sorted = values.ToArray();
        Array.Sort(sorted);
        int n = sorted.Length;
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }
    public static double[][] Cholesky(double[][] a) {
        int n = a.Length;
        double[][] l = Enumerable.Range(0, n)
                           .Select(
                               _ => new double[n])
                           .ToArray();
        for (int k = 0; k < n; k++)
            for (int j = 0; j <= k; j++) {
                double value = a[k][j];
                for (int i = 0; i < j; i++)
                    value -= l[k][i] * l[j][i];
                l[k][j] = k == j ? Math.Sqrt(value) : value / l[j][j];
            }
        return l;
    }
    public static double[] Solve(double[][] l, double[] right) {
        int n = l.Length;
        double[] eta = new double[n], result = new double[n];
        for (int k = 0; k < n; k++) {
            double value = right[k];
            for (int j = 0; j < k; j++)
                value -= l[k][j] * eta[j];
            eta[k] = value / l[k][k];
        }
        for (int k = n - 1; k >= 0; k--) {
            double value = eta[k];
            for (int j = k + 1; j < n; j++)
                value -= l[j][k] * result[j];
            result[k] = value / l[k][k];
        }
        return result;
    }
    public Kernels.Result Estimate(int position) {
        int n = data.n, count = span * n / 100, size = degree + 1;
        int[] ordered = new int[n];
        for (int i = 0; i < n; i++)
            ordered[i] = i;
        Array.Sort(ordered, Comparer<int>.Create(
                                (firstIndex, secondIndex) =>
                                    Math.Abs(data.positions[firstIndex] - position) !=
                                            Math.Abs(data.positions[secondIndex] - position)
                                        ? Math.Abs(data.positions[firstIndex] - position)
                                              .CompareTo(Math.Abs(data.positions[secondIndex] - position))
                                        : firstIndex.CompareTo(secondIndex)));
        bool[] selected = new bool[n];
        for (int i = 0; i < count; i++)
            selected[ordered[i]] = true;
        int extent = Math.Abs(data.positions[ordered[count - 1]] - position);
        double[][] a = Enumerable.Range(0, size)
                           .Select(
                               _ => new double[size])
                           .ToArray(),
                   basis = Enumerable.Range(0, n)
                               .Select(
                                   _ => new double[size])
                               .ToArray();
        double[] right = new double[size], v = new double[n];
        double x0 = position / 100.0;
        for (int j = 0; j < n; j++)
            if (selected[j]) {
                double ratio = (double)Math.Abs(data.positions[j] - position) / extent,
                       s = 1 - ratio * ratio * ratio, weight = s * s * s * rho[j], d = data.x[j] - x0;
                v[j] = weight;
                basis[j][0] = 1;
                basis[j][1] = d;
                if (degree == 2)
                    basis[j][2] = d * d;
                for (int k = 0; k < size; k++) {
                    right[k] += weight * basis[j][k] * data.y[j];
                    for (int l = 0; l < size; l++)
                        a[k][l] += weight * basis[j][k] * basis[j][l];
                }
            }
        double[][] factor = Cholesky(a);
        double[] beta = Solve(factor, right), unit = new double[size];
        unit[0] = 1;
        double[] zeta = Solve(factor, unit), weights = new double[n];
        for (int j = 0; j < n; j++)
            if (selected[j]) {
                double total = 0;
                for (int k = 0; k < size; k++)
                    total += zeta[k] * basis[j][k];
                weights[j] = v[j] * total;
            }
        return new Kernels.Result(beta[0], weights, zeta[0]);
    }
    public Loess(Dataset.Series data, int degree, int span, int iterations, bool diagnostics) {
        this.data = data;
        this.degree = degree;
        this.span = span;
        rho = new double[data.n];
        Array.Fill(rho, 1);
        fitted = new double[data.n];
        leverage = new double[data.n];
        if (!diagnostics)
            return;
        for (int i = 0; i < data.n; i++)
            fitted[i] = Estimate(data.positions[i]).value;
        for (int t = 0; t < iterations; t++) {
            double[] absolute = new double[data.n], errors = new double[data.n];
            for (int i = 0; i < data.n; i++) {
                errors[i] = data.y[i] - fitted[i];
                absolute[i] = Math.Abs(errors[i]);
            }
            double scale = Median(absolute);
            int zeros = 0;
            for (int i = 0; i < data.n; i++) {
                double u = errors[i] / (6 * scale), v = 1 - u * u;
                rho[i] = Math.Abs(u) < 1 ? v * v : 0;
                if (rho[i] == 0)
                    zeros++;
            }
            double[] next = new double[data.n];
            double change = 0;
            for (int i = 0; i < data.n; i++) {
                next[i] = Estimate(data.positions[i]).value;
                change = Math.Max(change, Math.Abs(next[i] - fitted[i]));
            }
            Array.Copy(next, 0, fitted, 0, data.n);
            rounds.Add(new Round(scale, zeros, change));
        }
        for (int i = 0; i < data.n; i++) {
            leverage[i] = rho[i] * Estimate(data.positions[i]).zeta;
            edf += leverage[i];
        }
    }
}
