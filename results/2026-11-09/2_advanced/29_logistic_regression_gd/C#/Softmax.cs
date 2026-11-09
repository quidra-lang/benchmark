using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record SoftCheckpoint(int iteration, double[][] weights);
static class Softmax {
    public static double[] Shifted(double[][] weights, double[] vector) {
        double[] scores = new double[weights.Length];
        double maximum = -double.MaxValue;
        for (int k = 0; k < scores.Length; k++) {
            scores[k] = Logistic.Score(weights[k], vector);
            maximum = Math.Max(maximum, scores[k]);
        }
        for (int k = 0; k < scores.Length; k++)
            scores[k] -= maximum;
        return scores;
    }
    public static double Total(double[] shifted) {
        double total = 0;
        foreach (double value in shifted)
            total += Math.Exp(value);
        return total;
    }
    public static double[] Probabilities(double[][] weights, double[] vector) {
        double[] shifted = Shifted(weights, vector);
        double total = Total(shifted);
        for (int k = 0; k < shifted.Length; k++)
            shifted[k] = Math.Exp(shifted[k]) / total;
        return shifted;
    }
    public static int Prediction(double[] probabilities) {
        int best = 0;
        for (int k = 1; k < probabilities.Length; k++)
            if (probabilities[k] > probabilities[best])
                best = k;
        return best;
    }
    public static double Loss(double[][] weights, double[] vector, int label) {
        double[] shifted = Shifted(weights, vector);
        return Math.Log(Total(shifted)) - shifted[label];
    }
    public static double Average(double[][] weights, double[][] vectors, int[] labels) {
        double total = 0;
        for (int i = 0; i < vectors.Length; i++)
            total += Loss(weights, vectors[i], labels[i]);
        return total / vectors.Length;
    }
    public static double Objective(double[][] weights, double[][] vectors, int[] labels, double lambda) {
        double total = 0;
        foreach (double[] row in weights)
            for (int j = 1; j < row.Length; j++)
                total += row[j] * row[j];
        return Average(weights, vectors, labels) + lambda * total / 2;
    }
    public static double[][] Gradient(double[][] weights, double[][] vectors, int[] labels, double lambda) {
        int classes = weights.Length, size = weights[0].Length;
        double[][] totals = Enumerable.Range(0, classes)
                                .Select(
                                    _ => new double[size])
                                .ToArray();
        for (int i = 0; i < vectors.Length; i++) {
            double[] probabilities = Probabilities(weights, vectors[i]);
            for (int k = 0; k < classes; k++) {
                double error = probabilities[k] - (labels[i] == k ? 1.0 : 0.0);
                for (int j = 0; j < size; j++)
                    totals[k][j] += error * vectors[i][j];
            }
        }
        for (int k = 0; k < classes; k++)
            for (int j = 0; j < size; j++) {
                totals[k][j] /= vectors.Length;
                if (j >= 1)
                    totals[k][j] += lambda * weights[k][j];
            }
        return totals;
    }
    public static List<SoftCheckpoint> Train(double[][] vectors, int[] labels, int classes, double lambda,
                                             double rate, int iterations) {
        double[][] weights = Enumerable.Range(0, classes)
                                 .Select(
                                     _ => new double[vectors[0].Length])
                                 .ToArray();
        List<SoftCheckpoint> checkpoints = new();
        checkpoints.Add(new SoftCheckpoint(0, weights));
        for (int t = 1; t <= iterations; t++) {
            double[][] gradient = Gradient(weights, vectors, labels, lambda),
                       next = Enumerable.Range(0, classes)
                                  .Select(
                                      _ => new double[vectors[0].Length])
                                  .ToArray();
            for (int k = 0; k < classes; k++)
                for (int j = 0; j < next[k].Length; j++)
                    next[k][j] = weights[k][j] - rate * gradient[k][j];
            weights = next;
            if (t % 100 == 0)
                checkpoints.Add(new SoftCheckpoint(t, weights));
        }
        return checkpoints;
    }
}
