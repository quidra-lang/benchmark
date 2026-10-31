using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Hrv {
    public static long Sum(List<long> values) {
        long result = 0;
        foreach (long value in values)
            result += value;
        return result;
    }
    public static long Squares(List<long> values) {
        long result = 0;
        foreach (long value in values)
            result += value * value;
        return result;
    }
    public static long Mean(List<long> values) {
        return values.Count == 0 ? -1 : Report.Rdiv(100 * Sum(values), values.Count);
    }
    public static long HeartRate(List<long> values) {
        return values.Count == 0 ? -1 : Report.Rdiv(6000000L * values.Count, Sum(values));
    }
    public sealed class Rr {
        public int count, shortBeat, longBeat;
        public long mean = -1, hr = -1, shortest = long.MaxValue, longest = -1;
    }
    public static Rr CalculateRr(List<Program.Beat> beats) {
        Rr result = new Rr();
        List<long> values = new();
        foreach (Program.Beat b in beats)
            if (b.number > 1) {
                values.Add(b.rr);
                if (b.rr < result.shortest) {
                    result.shortest = b.rr;
                    result.shortBeat = b.number;
                }
                if (b.rr > result.longest) {
                    result.longest = b.rr;
                    result.longBeat = b.number;
                }
            }
        result.count = values.Count;
        result.mean = Mean(values);
        result.hr = HeartRate(values);
        return result;
    }
    public sealed class Nn {
        public int e, k, nn50, maximum;
        public long mean = -1, sdnn = -1, rmssd = -1, sdsd = -1, pnn50 = -1, sd1 = -1, sd2 = -1;
        public SortedDictionary<long, int> histogram = new();
    }
    public static Nn CalculateNn(List<Program.Beat> beats) {
        Nn result = new Nn();
        bool[] normal = new bool[beats.Count];
        List<long> values = new(), differences = new(), sums = new();
        for (int i = 2; i < beats.Count; i++) {
            Program.Beat b = beats[i], previous = beats[i - 1];
            if (b.label.Equals("N") && previous.label.Equals("N") &&
                5 * Math.Abs(b.rr - previous.rr) <= previous.rr) {
                normal[i] = true;
                values.Add(b.rr);
                if (normal[i - 1]) {
                    differences.Add(b.rr - previous.rr);
                    sums.Add(b.rr + previous.rr);
                }
            }
        }
        int e = values.Count, k = differences.Count;
        result.e = e;
        result.k = k;
        result.mean = Mean(values);
        long total = Sum(values);
        if (e >= 2)
            result.sdnn = Report.Root(e * Squares(values) - total * total, (long)e * (e - 1));
        long ds = Sum(differences), ys = Sum(sums), d2 = Squares(differences);
        foreach (long d in differences)
            if (Math.Abs(d) > 50)
                result.nn50++;
        if (k > 0) {
            result.rmssd = Report.Root(d2, k);
            result.pnn50 = Report.Rdiv(10000L * result.nn50, k);
        }
        if (k >= 2) {
            long numerator = k * d2 - ds * ds, denominator = (long)k * (k - 1);
            result.sdsd = Report.Root(numerator, denominator);
            result.sd1 = Report.Root(numerator, 2 * denominator);
            result.sd2 = Report.Root(k * Squares(sums) - ys * ys, 2 * denominator);
        }
        foreach (long u in values) {
            long bin = 16 * u / 125;
            result.histogram[bin] = result.histogram.GetValueOrDefault(bin, 0) + 1;
        }
        foreach (int value in result.histogram.Values)
            result.maximum = Math.Max(result.maximum, value);
        return result;
    }
    public static List<int[]> Ranges(List<int> indices) {
        List<int[]> result = new();
        foreach (int i in indices) {
            if (result.Count != 0 && result[^1][1] + 1 == i)
                result[^1][1] = i;
            else
                result.Add(new int[] { i, i });
        }
        return result;
    }
}
