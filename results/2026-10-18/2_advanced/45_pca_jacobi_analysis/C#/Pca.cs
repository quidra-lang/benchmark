using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Pca {
    public static double[] Means(double[][] values) {
        int n = values.Length, p = values[0].Length;
        double[] result = new double[p];
        for (int j = 0; j < p; j++) {
            for (int i = 0; i < n; i++)
                result[j] += values[i][j];
            result[j] /= n;
        }
        return result;
    }
    public static double[][] Covariance(double[][] values, double[] mean) {
        int p = mean.Length, n = values.Length;
        double[][] result = Enumerable.Range(0, p)
                                .Select(
                                    _ => new double[p])
                                .ToArray();
        for (int j = 0; j < p; j++)
            for (int k = j; k < p; k++) {
                double sum = 0;
                for (int i = 0; i < n; i++)
                    sum += (values[i][j] - mean[j]) * (values[i][k] - mean[k]);
                result[j][k] = result[k][j] = sum / (n - 1);
            }
        return result;
    }
    public static double[] Deviations(double[][] covariance) {
        double[] result = new double[covariance.Length];
        for (int j = 0; j < result.Length; j++)
            result[j] = Math.Sqrt(covariance[j][j]);
        return result;
    }
    public static double[][] Correlation(double[][] covariance, double[] sd) {
        int p = sd.Length;
        double[][] result = Enumerable.Range(0, p)
                                .Select(
                                    _ => new double[p])
                                .ToArray();
        for (int j = 0; j < p; j++)
            for (int k = 0; k < p; k++)
                result[j][k] = j == k ? 1 : covariance[j][k] / (sd[j] * sd[k]);
        return result;
    }
    public static double[] Standardize(double[] values, double[] means, double[] scales) {
        double[] result = new double[values.Length];
        for (int j = 0; j < result.Length; j++)
            result[j] = double.IsNaN(values[j]) ? 0 : (values[j] - means[j]) / scales[j];
        return result;
    }
    public static double[] Scores(double[] z, double[][] vectors) {
        double[] result = new double[vectors.Length];
        for (int k = 0; k < result.Length; k++)
            result[k] = Matrix.Dot(z, vectors[k]);
        return result;
    }
    public static double[] Residuals(double[] z, double[] scores, double[][] vectors, int count) {
        double[] result = new double[z.Length];
        for (int j = 0; j < z.Length; j++) {
            double sum = 0;
            for (int k = 0; k < count; k++)
                sum += scores[k] * vectors[k][j];
            result[j] = z[j] - sum;
        }
        return result;
    }
    public static double T2(double[] scores, double[] eigenvalues, int count) {
        double sum = 0;
        for (int k = 0; k < count; k++)
            sum += scores[k] * scores[k] / eigenvalues[k];
        return sum;
    }
}
