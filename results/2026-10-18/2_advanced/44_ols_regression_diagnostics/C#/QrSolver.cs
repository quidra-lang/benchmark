using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class QrSolver {
    public sealed class Fit {
        public int rank;
        public int[] accepted;
        public double[] beta, effects, variance, leverage, fitted, residual, epsilon;
        public double[][] inverse, g;
        public double rss;
    }
    public static Fit Solve(double[][] x, double[] y, double[] w, double tolerance) {
        int n = y.Length, p = x[0].Length;
        double[] a = new double[n], z = new double[n], norm = new double[p];
        double[][] original = Enumerable.Range(0, n)
                                  .Select(
                                      _ => new double[p])
                                  .ToArray(),
                   matrix = Enumerable.Range(0, n)
                                .Select(
                                    _ => new double[p])
                                .ToArray(),
                   r = Enumerable.Range(0, p)
                           .Select(
                               _ => new double[p])
                           .ToArray();
        for (int i = 0; i < n; i++) {
            a[i] = Math.Sqrt(w[i]);
            z[i] = a[i] * y[i];
            for (int j = 0; j < p; j++) {
                original[i][j] = a[i] * x[i][j];
                matrix[i][j] = original[i][j];
            }
        }
        for (int j = 0; j < p; j++) {
            double sum = 0;
            for (int i = 0; i < n; i++)
                sum += original[i][j] * original[i][j];
            norm[j] = Math.Sqrt(sum);
        }
        List<int> accepted = new();
        for (int j = 0; j < p; j++) {
            int k = accepted.Count;
            double sum = 0;
            for (int i = k; i < n; i++)
                sum += matrix[i][j] * matrix[i][j];
            double eta = Math.Sqrt(sum);
            if (eta <= tolerance * norm[j])
                continue;
            accepted.Add(j);
            double alpha = matrix[k][j] >= 0 ? -eta : eta;
            double[] v = new double[n];
            for (int i = k; i < n; i++)
                v[i] = matrix[i][j];
            v[k] -= alpha;
            double volume = 0;
            for (int i = k; i < n; i++)
                volume += v[i] * v[i];
            for (int l = 0; l < k; l++)
                r[l][k] = matrix[l][j];
            r[k][k] = alpha;
            for (int l = j + 1; l < p; l++) {
                sum = 0;
                for (int i = k; i < n; i++)
                    sum += v[i] * matrix[i][l];
                double delta = 2 * sum / volume;
                for (int i = k; i < n; i++)
                    matrix[i][l] -= delta * v[i];
            }
            sum = 0;
            for (int i = k; i < n; i++)
                sum += v[i] * z[i];
            double responseDelta = 2 * sum / volume;
            for (int i = k; i < n; i++)
                z[i] -= responseDelta * v[i];
        }
        Fit result = new Fit();
        result.rank = accepted.Count;
        result.accepted = new int[result.rank];
        for (int k = 0; k < result.rank; k++)
            result.accepted[k] = accepted[k];
        result.beta = new double[p];
        Array.Fill(result.beta, double.NaN);
        result.effects = z.Take(result.rank).ToArray();
        for (int k = result.rank - 1; k >= 0; k--) {
            double sum = 0;
            for (int l = k + 1; l < result.rank; l++)
                sum += r[k][l] * result.beta[result.accepted[l]];
            result.beta[result.accepted[k]] = (result.effects[k] - sum) / r[k][k];
        }
        result.inverse = Enumerable.Range(0, result.rank)
                             .Select(
                                 _ => new double[result.rank])
                             .ToArray();
        result.variance = new double[result.rank];
        for (int m = 0; m < result.rank; m++)
            for (int l = result.rank - 1; l >= 0; l--) {
                double sum = 0;
                for (int q = l + 1; q < result.rank; q++)
                    sum += r[l][q] * result.inverse[q][m];
                result.inverse[l][m] = ((l == m ? 1 : 0) - sum) / r[l][l];
            }
        for (int k = 0; k < result.rank; k++)
            for (int m = 0; m < result.rank; m++)
                result.variance[k] += result.inverse[k][m] * result.inverse[k][m];
        result.g = Enumerable.Range(0, n)
                       .Select(
                           _ => new double[result.rank])
                       .ToArray();
        result.leverage = new double[n];
        result.fitted = new double[n];
        result.residual = new double[n];
        result.epsilon = new double[n];
        for (int i = 0; i < n; i++) {
            double[] u = new double[result.rank];
            for (int k = 0; k < result.rank; k++)
                for (int m = 0; m < result.rank; m++)
                    u[k] += original[i][result.accepted[m]] * result.inverse[m][k];
            for (int k = 0; k < result.rank; k++) {
                result.leverage[i] += u[k] * u[k];
                for (int m = 0; m < result.rank; m++)
                    result.g[i][k] += result.inverse[k][m] * u[m];
                result.fitted[i] += x[i][result.accepted[k]] * result.beta[result.accepted[k]];
            }
            result.residual[i] = y[i] - result.fitted[i];
            result.epsilon[i] = a[i] * result.residual[i];
            result.rss += result.epsilon[i] * result.epsilon[i];
        }
        return result;
    }
}
