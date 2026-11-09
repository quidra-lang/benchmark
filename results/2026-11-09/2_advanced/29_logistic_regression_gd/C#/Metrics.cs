using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

record Fraction(long numerator, long denominator) {
    public double Value() {
        return (double)numerator / denominator;
    }
    public override string ToString() {
        long divisor = Metrics.Gcd(numerator, denominator);
        return numerator / divisor + "/" + denominator / divisor + " " +
               Metrics.Ratio(numerator, denominator);
    }
}
sealed record RocPoint(double threshold, int tp, int fp);
record Confusion(int tp, int fp, int tn, int fn) {
    public int Correct() {
        return tp + tn;
    }
}
static class Metrics {
    public static long Gcd(long a, long b) {
        while (b != 0) {
            long old = b;
            b = a % b;
            a = old;
        }
        return a;
    }
    public static string Fixed(double value, int places) {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text.StartsWith("-") && double.Parse(text, CultureInfo.InvariantCulture) == 0
                   ? text.Substring(1)
                   : text;
    }
    public static string Ratio(long numerator, long denominator) {
        if (denominator == 0)
            return "-";
        long rounded = (20000 * numerator + denominator) / (2 * denominator);
        return rounded / 10000 + "." + (rounded % 10000).ToString("D4", CultureInfo.InvariantCulture);
    }
    public static Confusion Confusion(double[] probabilities, int[] targets, double threshold) {
        int tp = 0, fp = 0, tn = 0, fn = 0;
        for (int i = 0; i < probabilities.Length; i++) {
            if (probabilities[i] >= threshold) {
                if (targets[i] == 1)
                    tp++;
                else
                    fp++;
            } else if (targets[i] == 0)
                tn++;
            else
                fn++;
        }
        return new Confusion(tp, fp, tn, fn);
    }
    public static List<int> Order(double[] scores, bool reverse) {
        List<int> order = new();
        for (int i = 0; i < scores.Length; i++)
            order.Add(i);
        order.Sort((a, b) => {
            int compare = scores[a].CompareTo(scores[b]);
            if (reverse)
                compare = -compare;
            return compare != 0 ? compare : (a).CompareTo(b);
        });
        return order;
    }
    public static Fraction Auc(double[] scores, int[] targets) {
        List<int> order = Order(scores, false);
        int positives = 0;
        foreach (int target in targets)
            positives += target;
        long ranks = 0;
        int start = 0;
        while (start < order.Count) {
            int end = start;
            while (end + 1 < order.Count && scores[order[end + 1]] == scores[order[start]])
                end++;
            for (int position = start; position <= end; position++)
                if (targets[order[position]] == 1)
                    ranks += start + end + 2;
            start = end + 1;
        }
        return new Fraction(ranks - (long)positives * (positives + 1),
                            2L * positives * (targets.Length - positives));
    }
    public static List<RocPoint> Roc(double[] probabilities, int[] targets) {
        List<int> order = Order(probabilities, true);
        List<RocPoint> points = new();
        int tp = 0, fp = 0;
        for (int position = 0; position < order.Count; position++) {
            int i = order[position];
            if (targets[i] == 1)
                tp++;
            else
                fp++;
            if (position + 1 == order.Count || probabilities[order[position + 1]] != probabilities[i])
                points.Add(new RocPoint(probabilities[i], tp, fp));
        }
        return points;
    }
}
