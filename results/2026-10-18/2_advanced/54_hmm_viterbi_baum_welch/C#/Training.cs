using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Training {
    public record Pair(int[] observations, int[] path) {
    }
    public static ModelIo.Model Smooth(ModelIo.Model template, string name, double[] pi, double[][] a,
                                       double[][] b, double alpha) {
        for (int i = 0; i < pi.Length; i++) {
            pi[i] += alpha;
            for (int j = 0; j < a[i].Length; j++)
                a[i][j] += alpha;
            for (int c = 0; c < b[i].Length; c++)
                b[i][c] += alpha;
        }
        return new ModelIo.Model(name, template.states, template.symbols, template.missing, pi, a, b);
    }
    public static ModelIo.Model BaumWelch(ModelIo.Model model, List<int[]> sequences, double alpha) {
        int k = model.states.Length, m = model.symbols.Length;
        double[] pi = new double[k];
        double[][] a = Enumerable.Range(0, k)
                           .Select(
                               _ => new double[k])
                           .ToArray(),
                   b = Enumerable.Range(0, k)
                           .Select(
                               _ => new double[m])
                           .ToArray();
        foreach (int[] observations in sequences) {
            Inference.Fb fb = Inference.Backward(model, observations);
            for (int i = 0; i < k; i++)
                pi[i] += fb.gamma[0][i];
            for (int t = 0; t < observations.Length; t++)
                for (int i = 0; i < k; i++) {
                    if (observations[t] >= 0)
                        b[i][observations[t]] += fb.gamma[t][i];
                    if (t + 1 < observations.Length)
                        for (int j = 0; j < k; j++)
                            a[i][j] += Inference.Xi(model, fb, t, i, j);
                }
        }
        return Smooth(model, "BAUM_WELCH", pi, a, b, alpha);
    }
    public static ModelIo.Model Count(ModelIo.Model template, List<Pair> pairs, double alpha, string name) {
        int k = template.states.Length, m = template.symbols.Length;
        double[] pi = new double[k];
        double[][] a = Enumerable.Range(0, k)
                           .Select(
                               _ => new double[k])
                           .ToArray(),
                   b = Enumerable.Range(0, k)
                           .Select(
                               _ => new double[m])
                           .ToArray();
        foreach (Pair pair in pairs) {
            int[] path = pair.path, observations = pair.observations;
            pi[path[0]]++;
            for (int t = 0; t < path.Length; t++) {
                if (observations[t] >= 0)
                    b[path[t]][observations[t]]++;
                if (t + 1 < path.Length)
                    a[path[t]][path[t + 1]]++;
            }
        }
        return Smooth(template, name, pi, a, b, alpha);
    }
    public static double Loglik(ModelIo.Model model, List<int[]> sequences) {
        double sum = 0;
        foreach (int[] observations in sequences)
            sum += Inference.ScaledForward(model, observations).loglik;
        return sum;
    }
}
