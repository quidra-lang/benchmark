using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public record Continuity(int covered, int breaks, int swaps, int delay) {
    }
    public static double Squared(double[] a, double[] b) {
        double x = a[0] - b[0], y = a[1] - b[1];
        return x * x + y * y;
    }
    public static double Distance(double[] a, double[] b) {
        return Math.Sqrt(Squared(a, b));
    }
    public static double Ospa(List<double[]> first, List<double[]> second, double cutoff) {
        if (first.Count == 0 && second.Count == 0)
            return 0;
        if (first.Count == 0 || second.Count == 0)
            return cutoff;
        List<double[]> smaller = first.Count <= second.Count ? first : second,
                       larger = first.Count <= second.Count ? second : first;
        double[][] costs = Enumerable.Range(0, smaller.Count)
                               .Select(
                                   _ => new double[larger.Count])
                               .ToArray();
        for (int r = 0; r < costs.Length; r++)
            for (int c = 0; c < costs[0].Length; c++) {
                double d = Math.Min(cutoff, Distance(smaller[r], larger[c]));
                costs[r][c] = d * d;
            }
        double sum = 0;
        foreach (Association.Pair pair in Association.Minimum(costs))
            sum += costs[pair.row][pair.column];
        return Math.Sqrt((sum + cutoff * cutoff * (larger.Count - smaller.Count)) / larger.Count);
    }
    public static Continuity MeasureContinuity(int[] labels) {
        int covered = 0, groups = 0, swaps = 0, previous = 0, delay = -1;
        bool previousCovered = false;
        for (int i = 0; i < labels.Length; i++) {
            int label = labels[i];
            if (label == 0) {
                previousCovered = false;
                continue;
            }
            covered++;
            if (delay < 0)
                delay = i;
            if (!previousCovered)
                groups++;
            if (previous != 0 && label != previous)
                swaps++;
            previous = label;
            previousCovered = true;
        }
        return new Continuity(covered, Math.Max(0, groups - 1), swaps, delay);
    }
    public static string Real(double value) {
        string s = value.ToString("F4", CultureInfo.InvariantCulture);
        return s.StartsWith("-") && double.Parse(s) == 0 ? s.Substring(1) : s;
    }
}
