using System;
using System.Collections.Generic;
public static class Distances {
    public static readonly string[] MODELS = { "P", "JC", "K2P" };
    public record Pair(int first, int second, int sites, int transitions, int transversions);
    public record Correction(double value, bool saturated);
    public record Matrix(double[][] values, List<Pair> saturated);
    public static List<Pair> Pairs(List<string> sequences, int[] weights) {
        List<Pair> result = new();
        for (int i = 0; i < sequences.Count; i++)
            for (int j = i + 1; j < sequences.Count; j++) {
                int n = 0, s = 0, v = 0;
                for (int c = 0; c < weights.Length; c++) {
                    char a = sequences[i][c], b = sequences[j][c];
                    if (Alignment.BASES.IndexOf(a) < 0 || Alignment.BASES.IndexOf(b) < 0)
                        continue;
                    n += weights[c];
                    if (a != b) {
                        if ((a == 'A' && b == 'G') || (a == 'G' && b == 'A') ||
                            (a == 'C' && b == 'T') || (a == 'T' && b == 'C'))
                            s += weights[c];
                        else
                            v += weights[c];
                    }
                }
                result.Add(new(i, j, n, s, v));
            }
        return result;
    }
    public static Correction Correct(string model, int n, int s, int v, double replacement) {
        bool saturated = n == 0 || (model == "JC" && 4 * (s + v) >= 3 * n) ||
                         (model == "K2P" && (2 * s + v >= n || 2 * v >= n));
        if (saturated)
            return new(replacement, true);
        double value = model == "P"    ? (s + v) / (double)n
                       : model == "JC" ? -0.75 * Math.Log(1 - 4.0 * (s + v) / (3 * n))
                                       : -0.5 * Math.Log(1 - 2.0 * s / n - v / (double)n) -
                                             0.25 * Math.Log(1 - 2.0 * v / n);
        return new(value, false);
    }
    public static Matrix BuildMatrix(List<Pair> pairs, int count, string model,
                                     double replacement) {
        double[][] values = new double [count][];
        for (int i = 0; i < count; i++)
            values[i] = new double[count];
        List<Pair> saturated = new();
        foreach (Pair p in pairs) {
            Correction c = Correct(model, p.sites, p.transitions, p.transversions, replacement);
            values[p.first][p.second] = values[p.second][p.first] = c.value;
            if (c.saturated)
                saturated.Add(p);
        }
        return new(values, saturated);
    }
}
