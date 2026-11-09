using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Numerics {
    public static string Repeat(this string s, int count) => string.Concat(Enumerable.Repeat(s, count));
    public static readonly double Z = 1.959963984540054;
    public static double[][] Zeros(int n) {
        return Enumerable.Range(0, n)
            .Select(
                _ => new double[n])
            .ToArray();
    }
    public static double[] Solve(double[][] matrix, double[] right) {
        int n = right.Length;
        double[][] a = Zeros(n);
        for (int i = 0; i < n; i++)
            a[i] = matrix[i].ToArray();
        double[] b = right.ToArray(), x = new double[n];
        for (int k = 0; k < n; k++)
            for (int i = k + 1; i < n; i++) {
                double f = a[i][k] / a[k][k];
                for (int j = k; j < n; j++)
                    a[i][j] -= f * a[k][j];
                b[i] -= f * b[k];
            }
        for (int i = n - 1; i >= 0; i--) {
            double value = b[i];
            for (int j = i + 1; j < n; j++)
                value -= a[i][j] * x[j];
            x[i] = value / a[i][i];
        }
        return x;
    }
    public static double[][] Inverse(double[][] matrix) {
        int n = matrix.Length;
        double[][] result = Zeros(n);
        for (int c = 0; c < n; c++) {
            double[] unit = new double[n];
            unit[c] = 1;
            double[] y = Solve(matrix, unit);
            for (int a = 0; a < n; a++)
                result[a][c] = y[a];
        }
        return result;
    }
    public static double LogGamma(double a) {
        double[] coefficients = { 76.18009172947146,  -86.50532032941677,   24.01409824083091,
                                  -1.231739572450155, 0.001208650973866179, -0.000005395239384953 };
        double xi0 = a + 5.5, xi1 = xi0 - (a + 0.5) * Math.Log(xi0), sigma = 1.000000000190015, y = a;
        foreach (double coefficient in coefficients) {
            y += 1;
            sigma += coefficient / y;
        }
        return -xi1 + Math.Log(2.5066282746310005 * sigma / a);
    }
    public static double GammaQ(double a, double x) {
        if (x == 0)
            return 1;
        double pref = Math.Exp(-x + a * Math.Log(x) - LogGamma(a));
        if (x < a + 1) {
            double alpha = a, xi = 1 / a, sigma = xi;
            for (int i = 0; i < 1000; i++) {
                alpha += 1;
                xi *= x / alpha;
                sigma += xi;
                if (Math.Abs(xi) < Math.Abs(sigma) * 1e-15)
                    break;
            }
            return 1 - sigma * pref;
        }
        double eps = 1e-300, b = x + 1 - a, c = 1 / eps, d = 1 / b, h = d;
        for (int i = 1; i <= 1000; i++) {
            double an = -i * (i - a);
            b += 2;
            d = an * d + b;
            if (Math.Abs(d) < eps)
                d = eps;
            c = b + an / c;
            if (Math.Abs(c) < eps)
                c = eps;
            d = 1 / d;
            double delta = d * c;
            h *= delta;
            if (Math.Abs(delta - 1) < 1e-15)
                break;
        }
        return pref * h;
    }
    public static double Pvalue(double chi2, int degrees) {
        return GammaQ(degrees / 2.0, chi2 / 2);
    }
}
