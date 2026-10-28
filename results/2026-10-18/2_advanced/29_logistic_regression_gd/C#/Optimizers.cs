using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Checkpoint(int iteration, double[] weights);
sealed class Minstd {
    private long state;
    public Minstd(int seed) {
        state = seed;
    }
    public int Draw() {
        state = 48271 * state % 2147483647;
        return (int)state;
    }
    public void Shuffle(int[] order) {
        for (int i = order.Length; i >= 2; i--) {
            int index = Draw() % i, old = order[i - 1];
            order[i - 1] = order[index];
            order[index] = old;
        }
    }
}
static class Optimizers {
    public static double[][] Cholesky(double[][] matrix) {
        int size = matrix.Length;
        double[][] lower = Enumerable.Range(0, size)
                               .Select(
                                   _ => new double[size])
                               .ToArray();
        for (int j = 0; j < size; j++)
            for (int i = j; i < size; i++) {
                double total = 0;
                for (int k = 0; k < j; k++)
                    total += lower[i][k] * lower[j][k];
                double remainder = matrix[i][j] - total;
                lower[i][j] = i == j ? Math.Sqrt(remainder) : remainder / lower[j][j];
            }
        return lower;
    }
    public static double[] Solve(double[][] lower, double[] values) {
        int size = lower.Length;
        double[] middle = new double[size], solution = new double[size];
        for (int i = 0; i < size; i++) {
            double total = 0;
            for (int k = 0; k < i; k++)
                total += lower[i][k] * middle[k];
            middle[i] = (values[i] - total) / lower[i][i];
        }
        for (int i = size - 1; i >= 0; i--) {
            double total = 0;
            for (int k = i + 1; k < size; k++)
                total += lower[k][i] * solution[k];
            solution[i] = (middle[i] - total) / lower[i][i];
        }
        return solution;
    }
    public static List<Checkpoint> Newton(double[][] vectors, int[] targets, double lambda) {
        double[] weights = new double[vectors[0].Length];
        List<Checkpoint> checkpoints = new();
        checkpoints.Add(new Checkpoint(0, weights));
        for (int t = 1; t <= 10; t++) {
            double[] step = Solve(Cholesky(Logistic.Hessian(weights, vectors, lambda)),
                                  Logistic.Gradient(weights, vectors, targets, lambda));
            double[] next = new double[weights.Length];
            for (int j = 0; j < next.Length; j++)
                next[j] = weights[j] - step[j];
            weights = next;
            checkpoints.Add(new Checkpoint(t, weights));
        }
        return checkpoints;
    }
    public static List<Checkpoint> Gd(double[][] vectors, int[] targets, double lambda, double rate,
                                      int iterations) {
        double[] weights = new double[vectors[0].Length];
        List<Checkpoint> checkpoints = new();
        checkpoints.Add(new Checkpoint(0, weights));
        for (int t = 1; t <= iterations; t++) {
            double[] gradient = Logistic.Gradient(weights, vectors, targets, lambda);
            double[] next = new double[weights.Length];
            for (int j = 0; j < next.Length; j++)
                next[j] = weights[j] - rate * gradient[j];
            weights = next;
            if (t % 100 == 0)
                checkpoints.Add(new Checkpoint(t, weights));
        }
        return checkpoints;
    }
    public static List<Checkpoint> Sgd(double[][] vectors, int[] targets, double lambda, double rate,
                                       int batch, int epochs, int seed) {
        Minstd random = new Minstd(seed);
        int[] order = new int[vectors.Length];
        for (int i = 0; i < order.Length; i++)
            order[i] = i;
        double[] weights = new double[vectors[0].Length];
        List<Checkpoint> checkpoints = new();
        checkpoints.Add(new Checkpoint(0, weights));
        for (int epoch = 1; epoch <= epochs; epoch++) {
            random.Shuffle(order);
            for (int start = 0; start < order.Length; start += batch) {
                int count = Math.Min(batch, order.Length - start);
                double[][] x = new double [count][];
                int[] y = new int[count];
                for (int i = 0; i < count; i++) {
                    x[i] = vectors[order[start + i]];
                    y[i] = targets[order[start + i]];
                }
                double[] gradient = Logistic.Gradient(weights, x, y, lambda);
                double[] next = new double[weights.Length];
                for (int j = 0; j < next.Length; j++)
                    next[j] = weights[j] - rate * gradient[j];
                weights = next;
            }
            checkpoints.Add(new Checkpoint(epoch, weights));
        }
        return checkpoints;
    }
}
