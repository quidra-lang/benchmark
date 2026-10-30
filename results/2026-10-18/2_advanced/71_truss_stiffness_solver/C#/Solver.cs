using System;
using System.Linq;
public static class Solver {
    public record Factorization(double[][] lower, int unstable);
    public static Factorization Cholesky(double[][] matrix, int[] free) {
        int size = matrix.Length;
        double[][] lower = Enumerable.Range(0, size)
                               .Select(
                                   _ => new double[size])
                               .ToArray();
        for (int i = 0; i < size; i++)
            for (int j = 0; j <= i; j++) {
                double value = matrix[i][j];
                for (int h = 0; h < j; h++)
                    value -= lower[i][h] * lower[j][h];
                if (j < i)
                    lower[i][j] = value / lower[j][j];
                else {
                    if (value <= 0.000000001 * matrix[i][i])
                        return new(null, free[i]);
                    lower[i][i] = Math.Sqrt(value);
                }
            }
        return new(lower, -1);
    }
    public static double[] Solve(double[][] lower, double[] right) {
        int size = right.Length;
        double[] intermediate = new double[size], result = new double[size];
        for (int i = 0; i < size; i++) {
            double value = right[i];
            for (int h = 0; h < i; h++)
                value -= lower[i][h] * intermediate[h];
            intermediate[i] = value / lower[i][i];
        }
        for (int i = size - 1; i >= 0; i--) {
            double value = intermediate[i];
            for (int h = i + 1; h < size; h++)
                value -= lower[h][i] * result[h];
            result[i] = value / lower[i][i];
        }
        return result;
    }
}
