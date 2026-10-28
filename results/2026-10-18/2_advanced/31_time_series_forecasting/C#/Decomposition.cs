using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class Decomposition {
    public readonly double[] trend, additive, multiplicative, residualAdd, residualMult;
    public readonly int half, count;
    public Decomposition(double[] values, int season) {
        count = values.Length;
        half = season / 2;
        trend = new double[count];
        residualAdd = new double[count];
        residualMult = new double[count];
        Array.Fill(trend, double.NaN);
        Array.Fill(residualAdd, double.NaN);
        Array.Fill(residualMult, double.NaN);
        additive = new double[season];
        multiplicative = new double[season];
        int[] counts = new int[season];
        for (int t = half; t < count - half; t++) {
            double total = 0.5 * values[t - half];
            for (int i = t - half + 1; i < t + half; i++)
                total += values[i];
            total += 0.5 * values[t + half];
            trend[t] = total / season;
            int position = t % season;
            additive[position] += values[t] - trend[t];
            multiplicative[position] += values[t] / trend[t];
            counts[position]++;
        }
        for (int j = 0; j < season; j++) {
            additive[j] /= counts[j];
            multiplicative[j] /= counts[j];
        }
        double addMean = Sum(additive) / season, multMean = Sum(multiplicative) / season;
        for (int j = 0; j < season; j++) {
            additive[j] -= addMean;
            multiplicative[j] /= multMean;
        }
        for (int t = half; t < count - half; t++) {
            residualAdd[t] = values[t] - trend[t] - additive[t % season];
            residualMult[t] = values[t] / (trend[t] * multiplicative[t % season]);
        }
    }
    public static double Sum(double[] values) {
        double total = 0;
        foreach (double value in values)
            total += value;
        return total;
    }
    public static double Variance(double[] values) {
        double mean = Sum(values) / values.Length, total = 0;
        foreach (double value in values)
            total += (value - mean) * (value - mean);
        return total / (values.Length - 1);
    }
    public static double[] Regression(double[] values) {
        int count = values.Length;
        double center = (count + 1) / 2.0, average = Sum(values) / count, numerator = 0, denominator = 0;
        for (int t = 0; t < count; t++) {
            numerator += (t + 1 - center) * (values[t] - average);
            denominator += (t + 1 - center) * (t + 1 - center);
        }
        double slope = numerator / denominator;
        return new double[] { average - slope * center, slope };
    }
}
