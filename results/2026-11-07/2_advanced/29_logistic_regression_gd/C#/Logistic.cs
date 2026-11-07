using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Logistic {
    public static double Score(double[] weights, double[] vector) {
        double total = 0;
        for (int j = 0; j < weights.Length; j++)
            total += weights[j] * vector[j];
        return total;
    }
    public static double Probability(double score) {
        if (score >= 0)
            return 1 / (1 + Math.Exp(-score));
        double exponential = Math.Exp(score);
        return exponential / (1 + exponential);
    }
    public static double Loss(double score, int target) {
        return Math.Max(score, 0) - target * score + Math.Log(1 + Math.Exp(-Math.Abs(score)));
    }
    public static double Average(double[] weights, double[][] vectors, int[] targets) {
        double total = 0;
        for (int i = 0; i < vectors.Length; i++)
            total += Loss(Score(weights, vectors[i]), targets[i]);
        return total / vectors.Length;
    }
    public static double Penalty(double[] weights) {
        double total = 0;
        for (int j = 1; j < weights.Length; j++)
            total += weights[j] * weights[j];
        return total;
    }
    public static double Objective(double[] weights, double[][] vectors, int[] targets, double lambda) {
        return Average(weights, vectors, targets) + lambda * Penalty(weights) / 2;
    }
    public static double[] Gradient(double[] weights, double[][] vectors, int[] targets, double lambda) {
        double[] totals = new double[weights.Length];
        for (int i = 0; i < vectors.Length; i++) {
            double error = Probability(Score(weights, vectors[i])) - targets[i];
            for (int j = 0; j < totals.Length; j++)
                totals[j] += error * vectors[i][j];
        }
        for (int j = 0; j < totals.Length; j++) {
            totals[j] /= vectors.Length;
            if (j != 0)
                totals[j] += lambda * weights[j];
        }
        return totals;
    }
    public static double[][] Hessian(double[] weights, double[][] vectors, double lambda) {
        int size = weights.Length;
        double[][] totals = Enumerable.Range(0, size)
                                .Select(
                                    _ => new double[size])
                                .ToArray();
        foreach (double[] vector in vectors) {
            double probability = Probability(Score(weights, vector)),
                   variance = probability * (1 - probability);
            for (int j = 0; j < size; j++)
                for (int k = 0; k <= j; k++)
                    totals[j][k] += variance * vector[j] * vector[k];
        }
        for (int j = 0; j < size; j++)
            for (int k = 0; k <= j; k++) {
                double value = totals[j][k] / vectors.Length;
                if (j == k && j >= 1)
                    value += lambda;
                totals[j][k] = totals[k][j] = value;
            }
        return totals;
    }
}
