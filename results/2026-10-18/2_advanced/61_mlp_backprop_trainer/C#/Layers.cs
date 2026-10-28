using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Layers {
    public record Output(double[] scores, double[] delta, double loss) {
    }
    public static double Activation(string kind, double z) {
        return kind.Equals("TANH")      ? Math.Tanh(z)
               : kind.Equals("SIGMOID") ? 1 / (1 + Math.Exp(-z))
               : z > 0                  ? z
                                        : 0;
    }
    public static double Derivative(string kind, double z, double a) {
        return kind.Equals("TANH") ? 1 - a * a : kind.Equals("SIGMOID") ? a * (1 - a) : z > 0 ? 1 : 0;
    }
    public static double[] Linear(double[] theta, int start, int bias, int inputs, int units,
                                  double[] previous) {
        double[] z = new double[units];
        for (int j = 0; j < units; j++) {
            double sum = 0;
            for (int i = 0; i < inputs; i++)
                sum += theta[start + j * inputs + i] * previous[i];
            z[j] = sum + theta[bias + j];
        }
        return z;
    }
    public static double Backward(double[] theta, int start, int inputs, int units, int own, double[] delta) {
        double sum = 0;
        for (int j = 0; j < units; j++)
            sum += theta[start + j * inputs + own] * delta[j];
        return sum;
    }
    public static Output ComputeOutput(string kind, double[] z, int label) {
        int k = z.Length;
        double[] scores = new double[k], delta = new double[k];
        double loss = 0;
        if (kind.Equals("SOFTMAX")) {
            double maximum = z[0];
            for (int j = 1; j < k; j++)
                maximum = Math.Max(maximum, z[j]);
            double sum = 0;
            for (int j = 0; j < k; j++) {
                scores[j] = Math.Exp(z[j] - maximum);
                sum += scores[j];
            }
            for (int j = 0; j < k; j++) {
                scores[j] /= sum;
                delta[j] = scores[j] - (j == label ? 1 : 0);
            }
            loss = Math.Log(sum) - (z[label] - maximum);
        } else {
            for (int j = 0; j < k; j++) {
                scores[j] = 1 / (1 + Math.Exp(-z[j]));
                double error = scores[j] - (j == label ? 1 : 0);
                loss += error * error;
                delta[j] = 2 * error * scores[j] * (1 - scores[j]) / k;
            }
            loss /= k;
        }
        return new Output(scores, delta, loss);
    }
}
