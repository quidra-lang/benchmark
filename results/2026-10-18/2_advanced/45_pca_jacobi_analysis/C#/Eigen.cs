using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Eigen {
    public record Result(double[] values, double[][] vectors, int sweeps) {
    }
    public static double Off(double[][] a) {
        double sum = 0;
        for (int p = 0; p < a.Length - 1; p++)
            for (int q = p + 1; q < a.Length; q++)
                sum += a[p][q] * a[p][q];
        return sum;
    }
    public static void Rotate(double[][] a, double[][] v, int p, int q) {
        double apq = a[p][q];
        if (apq == 0)
            return;
        double theta = (a[q][q] - a[p][p]) / (2 * apq),
               t = 1 / (Math.Abs(theta) + Math.Sqrt(theta * theta + 1));
        if (theta < 0)
            t = -t;
        double c = 1 / Math.Sqrt(t * t + 1), s = t * c;
        for (int r = 0; r < a.Length; r++)
            if (r != p && r != q) {
                double arp = a[r][p], arq = a[r][q];
                a[r][p] = a[p][r] = c * arp - s * arq;
                a[r][q] = a[q][r] = s * arp + c * arq;
            }
        a[p][p] -= t * apq;
        a[q][q] += t * apq;
        a[p][q] = a[q][p] = 0;
        for (int r = 0; r < v.Length; r++) {
            double first = v[r][p], second = v[r][q];
            v[r][p] = c * first - s * second;
            v[r][q] = s * first + c * second;
        }
    }
    public static Result Jacobi(double[][] matrix) {
        int n = matrix.Length;
        double[][] a = Matrix.Copy(matrix), v = Matrix.Identity(n);
        double initial = Off(a);
        int count = 0;
        if (initial > 0)
            for (int sweep = 1; sweep <= 100; sweep++) {
                for (int p = 0; p < n - 1; p++)
                    for (int q = p + 1; q < n; q++)
                        Rotate(a, v, p, q);
                double current = Off(a);
                if (count == 0 && current < 1e-16 * initial)
                    count = sweep;
                if (current < 1e-22 * initial)
                    break;
            }
        List<int> order = new();
        for (int k = 0; k < n; k++)
            order.Add(k);
        order.Sort((left, right) => {
            int comparison = a[right][right].CompareTo(a[left][left]);
            return comparison != 0 ? comparison : left.CompareTo(right);
        });
        double[] values = new double[n];
        double[][] vectors = new double [n][];
        for (int k = 0; k < n; k++) {
            int index = order[k];
            values[k] = a[index][index];
            vectors[k] = Matrix.Column(v, index);
            Matrix.Normalize(vectors[k]);
            Matrix.Orient(vectors[k]);
        }
        return new Result(values, vectors, count);
    }
    public record Power(double value, double[] vector, int agreement) {
    }
    public static List<Power> PowerIteration(double[][] matrix, double[][] reference) {
        int n = matrix.Length;
        double[][] b = Matrix.Copy(matrix);
        List<Power> result = new();
        for (int k = 0; k < n; k++) {
            double[] x = new double[n];
            Array.Fill(x, 1);
            int agreement = 0;
            for (int iteration = 1; iteration <= 1000; iteration++) {
                x = Matrix.Multiply(b, x);
                Matrix.Normalize(x);
                double positive = 0, negative = 0;
                for (int j = 0; j < n; j++) {
                    positive = Math.Max(positive, Math.Abs(x[j] - reference[k][j]));
                    negative = Math.Max(negative, Math.Abs(x[j] + reference[k][j]));
                }
                if (agreement == 0 && Math.Min(positive, negative) < 0.000001)
                    agreement = iteration;
            }
            double value = Matrix.Dot(x, Matrix.Multiply(b, x));
            Matrix.Normalize(x);
            Matrix.Orient(x);
            result.Add(new Power(value, x, agreement));
            Matrix.Deflate(b, value, x);
        }
        return result;
    }
}
