using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Magnitude {
    public record Values(double distance, double? ml, double md) {
    }
    public record Frequency(SortedDictionary<int, int> counts, int completeness, int nb, double b,
                            double sigma, double a) {
    }
    public static double Log10(double x) {
        return Math.Log(x) / 2.302585092994046;
    }
    public static double Median(List<Double> values) {
        List<Double> sorted = new(values);
        sorted.Sort();
        int k = sorted.Count / 2;
        return sorted.Count % 2 == 1 ? sorted[k] : (sorted[k - 1] + sorted[k]) / 2;
    }
    public static Values PerPick(Picker.Pick pick, double distance, WaveformIo.Params settings) {
        double[] l = settings.Row("local_magnitude"), d = settings.Row("duration_magnitude");
        double? ml = pick.clipped ? null
                                  : Log10(pick.amplitude) + l[0] * Log10(distance / 100) +
                                        l[1] * (distance - 100) + l[2];
        return new Values(distance, ml, d[0] + d[1] * Log10(pick.duration / 100.0) + d[2] * distance);
    }
    public static long Rounded(double value, int digits) {
        return (long)Math.Round(value * Math.Pow(10, digits), MidpointRounding.AwayFromZero);
    }
    public static long FloorDivision(long a, long b) {
        long q = a / b;
        return a % b < 0 ? q - 1 : q;
    }
    public static int ClassNumber(double ml) {
        return (int)Magnitude.FloorDivision(Rounded(ml, 2) + 5, 10);
    }
    public static string ClassText(int t) {
        return (t < 0 ? "-" : "") + Math.Abs(t) / 10 + "." + Math.Abs(t) % 10;
    }
    public static Frequency ComputeFrequency(List<Double> magnitudes) {
        SortedDictionary<int, int> counts = new();
        foreach (double ml in magnitudes) {
            int t = ClassNumber(ml);
            counts[t] = counts.GetValueOrDefault(t, 0) + 1;
        }
        int tc = counts.Keys.First(), maximum = 0;
        foreach (int t in counts.Keys)
            if (counts[t] > maximum) {
                tc = t;
                maximum = counts[t];
            }
        int nb = 0;
        long sum = 0;
        foreach (int t in counts.Keys)
            if (t >= tc) {
                nb += counts[t];
                sum += (long)t * counts[t];
            }
        double mc = tc / 10.0, mean = sum / (10.0 * nb), b = 0.4342944819032518 / (mean - (mc - 0.05));
        return new Frequency(counts, tc, nb, b, b / Math.Sqrt(nb), Log10(nb) + b * mc);
    }
}
