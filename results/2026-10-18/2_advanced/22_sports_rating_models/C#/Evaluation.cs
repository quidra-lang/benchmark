using System;
using System.Collections.Generic;

sealed record Link(double Alpha, double Beta);
static class Evaluation {
    public static double Sigma(double value) => 1 / (1 + Math.Exp(-value));
    public static Link FitLink(double[] features, List<Match> matches, long iterations) {
        double alpha = 0, beta = 0;
        for (long iteration = 0; iteration < iterations; iteration++) {
            double g0 = 0, g1 = 0, h00 = 0, h01 = 0, h11 = 0;
            for (int i = 0; i < features.Length; i++) {
                double z = features[i], p = Sigma(alpha + beta * z), w = p * (1 - p), delta = matches[i].Result - p;
                g0 += delta; g1 += delta * z; h00 += w; h01 += w * z; h11 += w * z * z;
            }
            double determinant = h00 * h11 - h01 * h01;
            double nextAlpha = alpha + (h11 * g0 - h01 * g1) / determinant, nextBeta = beta + (h00 * g1 - h01 * g0) / determinant;
            alpha = nextAlpha; beta = nextBeta;
        }
        return new Link(alpha, beta);
    }
    public static double LogLoss(double p, int resultTwice) => resultTwice == 2 ? -Math.Log(p) : resultTwice == 0 ? -Math.Log(1 - p) : -(Math.Log(p) / 2 + Math.Log(1 - p) / 2);
    public static double Brier(double p, int resultTwice) { double difference = p - resultTwice / 2.0; return difference * difference; }
    public static int CorrectnessTwice(double p, int resultTwice) => resultTwice == 1 ? 1 : p > 0.5 && resultTwice == 2 || p < 0.5 && resultTwice == 0 ? 2 : 0;
    static int[] AverageRanksTwice(Fraction[] values) {
        int[] ranks = new int[values.Length];
        for (int i = 0; i < values.Length; i++) {
            int greater = 0, equal = 0;
            foreach (Fraction value in values) { int comparison = value.CompareTo(values[i]); if (comparison > 0) greater++; else if (comparison == 0) equal++; }
            ranks[i] = 2 * greater + equal + 1;
        }
        return ranks;
    }
    public static Fraction Kendall(Fraction[] first, Fraction[] second) {
        int count = first.Length, concordant = 0, discordant = 0;
        for (int t = 0; t < count; t++) for (int u = t + 1; u < count; u++) {
            int agreement = Math.Sign(first[t].CompareTo(first[u])) * Math.Sign(second[t].CompareTo(second[u]));
            if (agreement > 0) concordant++; else if (agreement < 0) discordant++;
        }
        return new Fraction(concordant - discordant, count * (count - 1) / 2);
    }
    public static Fraction Spearman(Fraction[] first, Fraction[] second) {
        int count = first.Length;
        int[] a = AverageRanksTwice(first), b = AverageRanksTwice(second);
        long squares = 0;
        for (int i = 0; i < count; i++) { long difference = a[i] - b[i]; squares += difference * difference; }
        return new Fraction(1).Subtract(new Fraction(6 * squares, 4L * count * (count * count - 1)));
    }
}
