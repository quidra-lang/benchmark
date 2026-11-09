using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Matrix {
    public static double[][] Identity(int n) {
        double[][] a = Enumerable.Range(0, n)
                           .Select(
                               _ => new double[n])
                           .ToArray();
        for (int i = 0; i < n; i++)
            a[i][i] = 1;
        return a;
    }
    public static double[][] Copy(double[][] a) {
        double[][] result = new double [a.Length][];
        for (int i = 0; i < a.Length; i++)
            result[i] = a[i].ToArray();
        return result;
    }
    public static double[] Column(double[][] a, int k) {
        double[] result = new double[a.Length];
        for (int i = 0; i < a.Length; i++)
            result[i] = a[i][k];
        return result;
    }
    public static double Sum(double[] x) {
        double result = 0;
        foreach (double v in x)
            result += v;
        return result;
    }
    public static double Dot(double[] a, double[] b) {
        double result = 0;
        for (int j = 0; j < a.Length; j++)
            result += a[j] * b[j];
        return result;
    }
    public static double[] Multiply(double[][] a, double[] x) {
        double[] result = new double[a.Length];
        for (int i = 0; i < a.Length; i++)
            result[i] = Dot(a[i], x);
        return result;
    }
    public static double Length(double[] x) {
        return Math.Sqrt(Dot(x, x));
    }
    public static void Normalize(double[] x) {
        double length = Length(x);
        for (int j = 0; j < x.Length; j++)
            x[j] /= length;
    }
    public static void Orient(double[] x) {
        int largest = 0;
        for (int j = 1; j < x.Length; j++)
            if (Math.Abs(x[j]) > Math.Abs(x[largest]))
                largest = j;
        if (x[largest] < 0)
            for (int j = 0; j < x.Length; j++)
                x[j] = -x[j];
    }
    public static double Difference(double[] a, double[] b) {
        double result = 0;
        for (int j = 0; j < a.Length; j++)
            result = Math.Max(result, Math.Abs(a[j] - b[j]));
        return result;
    }
    public static void Deflate(double[][] a, double value, double[] x) {
        for (int i = 0; i < x.Length; i++)
            for (int j = 0; j < x.Length; j++)
                a[i][j] -= value * x[i] * x[j];
    }
    public record Inverse(double[][] matrix, double determinant) {
    }
    public static Inverse Invert(double[][] a) {
        int n = a.Length;
        double[][] augmented = Enumerable.Range(0, n)
                                   .Select(
                                       _ => new double[2 * n])
                                   .ToArray();
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++)
                augmented[i][j] = a[i][j];
            augmented[i][n + i] = 1;
        }
        double determinant = 1;
        for (int k = 0; k < n; k++) {
            double pivot = augmented[k][k];
            determinant *= pivot;
            for (int h = 0; h < 2 * n; h++)
                augmented[k][h] /= pivot;
            for (int i = 0; i < n; i++)
                if (i != k) {
                    double gamma = augmented[i][k];
                    for (int h = 0; h < 2 * n; h++)
                        augmented[i][h] -= gamma * augmented[k][h];
                }
        }
        double[][] result = Enumerable.Range(0, n)
                                .Select(
                                    _ => new double[n])
                                .ToArray();
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                result[i][j] = augmented[i][n + j];
        return new Inverse(result, determinant);
    }
}
