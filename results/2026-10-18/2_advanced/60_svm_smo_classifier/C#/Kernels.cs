using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Kernels {
    public record Point(double x, double y) {
    }
    public record Kernel(string name, string kind, int degree, double gamma, double offset) {
        public double Value(Point a, Point b) {
            if (kind.Equals("linear"))
                return a.x * b.x + a.y * b.y;
            if (kind.Equals("poly")) {
                double s = gamma * (a.x * b.x + a.y * b.y) + offset, value = 1;
                for (int i = 0; i < degree; i++)
                    value *= s;
                return value;
            }
            double e1 = a.x - b.x, e2 = a.y - b.y;
            return Math.Exp(-gamma * (e1 * e1 + e2 * e2));
        }
        public string Description() {
            return kind.Equals("linear") ? "linear"
                   : kind.Equals("poly") ? "poly degree " + degree + " gamma " + Evaluation.Fixed(gamma, 4) +
                                               " coef0 " + Evaluation.Fixed(offset, 4)
                                         : "rbf gamma " + Evaluation.Fixed(gamma, 4);
        }
        public double[][] Matrix(List<Point> points) {
            int n = points.Count;
            double[][] matrix = Enumerable.Range(0, n)
                                    .Select(
                                        _ => new double[n])
                                    .ToArray();
            for (int i = 0; i < n; i++)
                for (int j = 0; j < n; j++)
                    matrix[i][j] = Value(points[i], points[j]);
            return matrix;
        }
    }
    public static double[][] Submatrix(double[][] matrix, List<int> indices) {
        int n = indices.Count;
        double[][] result = Enumerable.Range(0, n)
                                .Select(
                                    _ => new double[n])
                                .ToArray();
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                result[i][j] = matrix[indices[i]][indices[j]];
        return result;
    }
}
