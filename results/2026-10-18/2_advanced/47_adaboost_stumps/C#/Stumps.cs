using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Stumps {
    public record Stump(int feature, double[] thresholds, double[] values) {
        public double Output(double[] x) {
            int bin = 0;
            foreach (double threshold in thresholds)
                if (x[feature] > threshold)
                    bin++;
            return values[bin];
        }
        public double Magnitude() {
            double result = 0;
            foreach (double value in values)
                result = Math.Max(result, Math.Abs(value));
            return result;
        }
    }
    public record Candidate(Stump stump, double error, int polarity) {
    }
    public sealed class Search {
        public List<Dataset.Row> rows;
        public int[][] sorted, ends;
        public double[][] thresholds;
        public Search(List<Dataset.Row> rows) {
            this.rows = rows;
            int d = rows[0].x.Length, n = rows.Count;
            sorted = Enumerable.Range(0, d)
                         .Select(
                             _ => new int[n])
                         .ToArray();
            ends = new int [d][];
            thresholds = new double [d][];
            for (int j = 0; j < d; j++) {
                int feature = j;
                List<int> order = new();
                for (int i = 0; i < n; i++)
                    order.Add(i);
                order.Sort((a, b) => {
                    int comparison = rows[a].x[feature].CompareTo(rows[b].x[feature]);
                    return comparison != 0 ? comparison : a.CompareTo(b);
                });
                List<double> distinct = new();
                List<int> starts = new();
                for (int i = 0; i < n; i++) {
                    sorted[j][i] = order[i];
                    double value = rows[order[i]].x[j];
                    if (i == 0 || value != rows[order[i - 1]].x[j]) {
                        distinct.Add(value);
                        starts.Add(i);
                    }
                }
                int q = distinct.Count;
                ends[j] = new int[q];
                thresholds[j] = new double[q];
                for (int c = 0; c < q; c++) {
                    ends[j][c] = starts[c];
                    thresholds[j][c] = c == 0 ? distinct[0] - 1 : (distinct[c - 1] + distinct[c]) / 2;
                }
            }
        }
    }
    public static Candidate Choose(List<Candidate> candidates) {
        double minimum = double.PositiveInfinity;
        foreach (Candidate candidate in candidates)
            minimum = Math.Min(minimum, candidate.error);
        foreach (Candidate candidate in candidates)
            if (candidate.error <= minimum + 0.000000001)
                return candidate;
        throw new InvalidOperationException();
    }
    public static Candidate Discrete(Search search, double[] weights) {
        double plus = 0, minus = 0;
        for (int i = 0; i < weights.Length; i++)
            if (search.rows[i].label == 1)
                plus += weights[i];
            else
                minus += weights[i];
        List<Candidate> candidates = new();
        for (int j = 0; j < search.sorted.Length; j++) {
            int position = 0;
            double leftPlus = 0, leftMinus = 0;
            for (int c = 0; c < search.thresholds[j].Length; c++) {
                while (position < search.ends[j][c]) {
                    int i = search.sorted[j][position++];
                    if (search.rows[i].label == 1)
                        leftPlus += weights[i];
                    else
                        leftMinus += weights[i];
                }
                double threshold = search.thresholds[j][c];
                candidates.Add(new Candidate(new Stump(j, new double[] { threshold }, new double[] { -1, 1 }),
                                             leftPlus + (minus - leftMinus), 1));
                candidates.Add(new Candidate(new Stump(j, new double[] { threshold }, new double[] { 1, -1 }),
                                             leftMinus + (plus - leftPlus), -1));
            }
        }
        return Choose(candidates);
    }
    public static Candidate Regression(Search search, double[] targets, double[] weights) {
        double total = 0, s = 0, q = 0;
        for (int i = 0; i < weights.Length; i++) {
            total += weights[i];
            s += weights[i] * targets[i];
            q += weights[i] * targets[i] * targets[i];
        }
        List<Candidate> candidates = new();
        for (int j = 0; j < search.sorted.Length; j++) {
            int position = 0;
            double wl = 0, sl = 0;
            for (int c = 0; c < search.thresholds[j].Length; c++) {
                while (position < search.ends[j][c]) {
                    int i = search.sorted[j][position++];
                    wl += weights[i];
                    sl += weights[i] * targets[i];
                }
                double wr = total - wl, sr = s - sl, left = c == 0 ? 0 : sl / wl, right = sr / wr,
                       g = c == 0 ? sr * sr / wr : sl * sl / wl + sr * sr / wr;
                candidates.Add(new Candidate(
                    new Stump(j, new double[] { search.thresholds[j][c] }, new double[] { left, right }),
                    q - g, 0));
            }
        }
        return Choose(candidates);
    }
    public static Candidate Multiclass(Search search, double[] weights, int classes) {
        double total = 0;
        double[] totals = new double[classes];
        for (int i = 0; i < weights.Length; i++) {
            total += weights[i];
            totals[search.rows[i].label - 1] += weights[i];
        }
        List<Candidate> candidates = new();
        for (int j = 0; j < search.sorted.Length; j++) {
            int position = 0;
            double[] left = new double[classes];
            for (int c = 0; c < search.thresholds[j].Length; c++) {
                while (position < search.ends[j][c]) {
                    int i = search.sorted[j][position++];
                    left[search.rows[i].label - 1] += weights[i];
                }
                int a = 0, b = 0;
                for (int h = 1; h < classes; h++) {
                    if (left[h] > left[a])
                        a = h;
                    if (totals[h] - left[h] > totals[b] - left[b])
                        b = h;
                }
                candidates.Add(new Candidate(
                    new Stump(j, new double[] { search.thresholds[j][c] }, new double[] { a + 1, b + 1 }),
                    total - (left[a] + (totals[b] - left[b])), 0));
            }
        }
        return Choose(candidates);
    }
    public static double[][] Cuts(Search search, int bins) {
        double[][] result = Enumerable.Range(0, search.sorted.Length)
                                .Select(
                                    _ => new double[bins - 1])
                                .ToArray();
        int n = search.rows.Count;
        for (int j = 0; j < result.Length; j++)
            for (int b = 1; b < bins; b++) {
                int r = b * n / bins;
                result[j][b - 1] =
                    (search.rows[search.sorted[j][r - 1]].x[j] + search.rows[search.sorted[j][r]].x[j]) / 2;
            }
        return result;
    }
    public static Candidate Real(Search search, double[] weights, double[][] cuts, int bins,
                                 double smoothing) {
        List<Candidate> candidates = new();
        for (int j = 0; j < cuts.Length; j++) {
            double[] plus = new double[bins], minus = new double[bins];
            for (int i = 0; i < weights.Length; i++) {
                int bin = 0;
                foreach (double cut in cuts[j])
                    if (cut < search.rows[i].x[j])
                        bin++;
                if (search.rows[i].label == 1)
                    plus[bin] += weights[i];
                else
                    minus[bin] += weights[i];
            }
            double z = 0;
            double[] values = new double[bins];
            for (int bin = 0; bin < bins; bin++) {
                z += Math.Sqrt(plus[bin] * minus[bin]);
                values[bin] = 0.5 * Math.Log((plus[bin] + smoothing) / (minus[bin] + smoothing));
            }
            candidates.Add(new Candidate(new Stump(j, cuts[j], values), 2 * z, 0));
        }
        return Choose(candidates);
    }
}
