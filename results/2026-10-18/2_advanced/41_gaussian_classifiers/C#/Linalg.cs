using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Linalg {
    public static double[][] Zeros(int n) {
        return Enumerable.Range(0, n)
            .Select(
                _ => new double[n])
            .ToArray();
    }
    public static double Dot(double[] a, double[] b) {
        double sum = 0;
        for (int i = 0; i < a.Length; i++)
            sum += a[i] * b[i];
        return sum;
    }
    public static double[][] Cholesky(double[][] a) {
        int n = a.Length;
        double[][] l = Zeros(n);
        for (int i = 0; i < n; i++)
            for (int j = 0; j <= i; j++) {
                double sum = 0;
                for (int k = 0; k < j; k++)
                    sum += l[i][k] * l[j][k];
                double s = a[i][j] - sum;
                l[i][j] = i == j ? Math.Sqrt(s) : s / l[j][j];
            }
        return l;
    }
    public static double[] Forward(double[][] l, double[] r) {
        double[] z = new double[l.Length];
        for (int i = 0; i < l.Length; i++) {
            double sum = 0;
            for (int k = 0; k < i; k++)
                sum += l[i][k] * z[k];
            z[i] = (r[i] - sum) / l[i][i];
        }
        return z;
    }
    public static double[] Backward(double[][] l, double[] u) {
        int n = l.Length;
        double[] v = new double[n];
        for (int i = n - 1; i >= 0; i--) {
            double sum = 0;
            for (int k = i + 1; k < n; k++)
                sum += l[k][i] * v[k];
            v[i] = (u[i] - sum) / l[i][i];
        }
        return v;
    }
    public static double LogDet(double[][] l) {
        double sum = 0;
        for (int i = 0; i < l.Length; i++)
            sum += Math.Log(l[i][i]);
        return 2 * sum;
    }
    public static double Quadratic(double[][] l, double[] r) {
        double[] z = Forward(l, r);
        return Dot(z, z);
    }
    public record Eigen(double[] values, double[][] vectors, int sweeps) {
    }
    public static Eigen Jacobi(double[][] a) {
        int n = a.Length;
        double[][] m = Zeros(n), v = Zeros(n);
        for (int i = 0; i < n; i++) {
            m[i] = a[i].ToArray();
            v[i][i] = 1;
        }
        int sweeps = 0;
        while (true) {
            double sum = 0;
            for (int i = 0; i < n - 1; i++)
                for (int j = i + 1; j < n; j++)
                    sum += m[i][j] * m[i][j];
            if (Math.Sqrt(sum) < 1e-12 || sweeps == 50)
                break;
            for (int a0 = 0; a0 < n - 1; a0++)
                for (int b0 = a0 + 1; b0 < n; b0++) {
                    if (m[a0][b0] == 0)
                        continue;
                    double theta = (m[b0][b0] - m[a0][a0]) / (2 * m[a0][b0]),
                           t = (theta >= 0 ? 1 : -1) / (Math.Abs(theta) + Math.Sqrt(theta * theta + 1)),
                           co = 1 / Math.Sqrt(t * t + 1), si = t * co;
                    for (int k = 0; k < n; k++) {
                        if (k == a0 || k == b0)
                            continue;
                        double x = m[k][a0], y = m[k][b0];
                        m[k][a0] = m[a0][k] = co * x - si * y;
                        m[k][b0] = m[b0][k] = si * x + co * y;
                    }
                    double w = m[a0][b0];
                    m[a0][a0] -= t * w;
                    m[b0][b0] += t * w;
                    m[a0][b0] = m[b0][a0] = 0;
                    for (int k = 0; k < n; k++) {
                        double x = v[k][a0], y = v[k][b0];
                        v[k][a0] = co * x - si * y;
                        v[k][b0] = si * x + co * y;
                    }
                }
            sweeps++;
        }
        double[] values = new double[n];
        for (int i = 0; i < n; i++)
            values[i] = m[i][i];
        return new Eigen(values, v, sweeps);
    }
    public static List<int> Decreasing(double[] values) {
        List<int> indices = new();
        for (int i = 0; i < values.Length; i++)
            indices.Add(i);
        indices.Sort((a, b) => values[a] != values[b] ? values[b].CompareTo(values[a]) : a.CompareTo(b));
        return indices;
    }
}
