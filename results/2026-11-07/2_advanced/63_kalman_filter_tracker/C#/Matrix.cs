using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Matrix {
    public static double Total(double[] values) {
        double result = 0;
        foreach (double value in values)
            result += value;
        return result;
    }
    public static double[][] Diagonal(double[] values) {
        double[][] result = Enumerable.Range(0, values.Length)
                                .Select(
                                    _ => new double[values.Length])
                                .ToArray();
        for (int i = 0; i < values.Length; i++)
            result[i][i] = values[i];
        return result;
    }
    public static double[][] Identity(int n) {
        double[] values = new double[n];
        Array.Fill(values, 1);
        return Diagonal(values);
    }
    public static double[][] Transpose(double[][] a) {
        double[][] result = Enumerable.Range(0, a[0].Length)
                                .Select(
                                    _ => new double[a.Length])
                                .ToArray();
        for (int i = 0; i < a.Length; i++)
            for (int k = 0; k < a[0].Length; k++)
                result[k][i] = a[i][k];
        return result;
    }
    public static double[][] Add(double[][] a, double[][] b) {
        double[][] c = Enumerable.Range(0, a.Length)
                           .Select(
                               _ => new double[a[0].Length])
                           .ToArray();
        for (int i = 0; i < a.Length; i++)
            for (int k = 0; k < a[0].Length; k++)
                c[i][k] = a[i][k] + b[i][k];
        return c;
    }
    public static double[][] Subtract(double[][] a, double[][] b) {
        double[][] c = Enumerable.Range(0, a.Length)
                           .Select(
                               _ => new double[a[0].Length])
                           .ToArray();
        for (int i = 0; i < a.Length; i++)
            for (int k = 0; k < a[0].Length; k++)
                c[i][k] = a[i][k] - b[i][k];
        return c;
    }
    public static double[] Add(double[] a, double[] b) {
        double[] c = new double[a.Length];
        for (int i = 0; i < a.Length; i++)
            c[i] = a[i] + b[i];
        return c;
    }
    public static double[] Subtract(double[] a, double[] b) {
        double[] c = new double[a.Length];
        for (int i = 0; i < a.Length; i++)
            c[i] = a[i] - b[i];
        return c;
    }
    public static double[][] Product(double[][] a, double[][] b) {
        double[][] c = Enumerable.Range(0, a.Length)
                           .Select(
                               _ => new double[b[0].Length])
                           .ToArray();
        for (int i = 0; i < a.Length; i++)
            for (int j = 0; j < b[0].Length; j++)
                for (int k = 0; k < b.Length; k++)
                    c[i][j] += a[i][k] * b[k][j];
        return c;
    }
    public static double[] Product(double[][] a, double[] b) {
        double[] c = new double[a.Length];
        for (int i = 0; i < a.Length; i++)
            for (int k = 0; k < b.Length; k++)
                c[i] += a[i][k] * b[k];
        return c;
    }
    public static double[][] Inverse(double[][] a) {
        int n = a.Length;
        double[][] x = Enumerable.Range(0, n)
                           .Select(
                               _ => new double[2 * n])
                           .ToArray();
        for (int i = 0; i < n; i++) {
            Array.Copy(a[i], 0, x[i], 0, n);
            x[i][n + i] = 1;
        }
        for (int c = 0; c < n; c++) {
            double p = x[c][c];
            for (int j = 0; j < 2 * n; j++)
                x[c][j] /= p;
            for (int i = 0; i < n; i++)
                if (i != c) {
                    double f = x[i][c];
                    for (int j = 0; j < 2 * n; j++)
                        x[i][j] -= f * x[c][j];
                }
        }
        double[][] result = Enumerable.Range(0, n)
                                .Select(
                                    _ => new double[n])
                                .ToArray();
        for (int i = 0; i < n; i++)
            Array.Copy(x[i], n, result[i], 0, n);
        return result;
    }
    public static double Determinant2(double[][] a) {
        return a[0][0] * a[1][1] - a[0][1] * a[1][0];
    }
    public static double Quadratic2(double[] u, double[][] a) {
        return u[0] * (a[0][0] * u[0] + a[0][1] * u[1]) + u[1] * (a[1][0] * u[0] + a[1][1] * u[1]);
    }
}
