using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Cleaning {
    public record Run(int first, int last, double value) {}
    public record Spike(int time, double value, double residual, double median, double mad,
                        double limit) {}
    public record Gap(int first, int last, string cause) {}
    public sealed class Record {
        public int first, last, numeric, tested;
        public double prefitRms;
        public double[] values = new double[10001];
        public bool[] candidate = new bool[10001], usable = new bool[10001];
        public string[] reasons = new string[10001];
        public List<int> candidates = new(), times = new();
        public List<Run> runs = new();
        public List<Spike> spikes = new();
        public List<Gap> gaps = new();
    }
    public static double Median(List<double> values) {
        List<double> sorted = new(values);
        sorted.Sort();
        int n = sorted.Count;
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }
    public static Record Prepare(Records.Station station, int minimumRun) {
        Record r = new Record();
        List<int> numeric = new();
        foreach (var entry in station.values)
            if (entry.Value != null) {
                numeric.Add(entry.Key);
                r.values[entry.Key] = entry.Value.Value / 1000.0;
            }
        r.first = numeric[0];
        r.last = numeric[^1];
        r.numeric = numeric.Count;
        for (int t = r.first; t <= r.last; t++) {
            if (!station.values.ContainsKey(t))
                r.reasons[t] = "absent";
            else if (station.values[t] == null)
                r.reasons[t] = "na";
        }
        int i = 0;
        while (i < numeric.Count) {
            int first = numeric[i], last = first;
            while (i + 1 < numeric.Count && numeric[i + 1] == last + 1 &&
                   station.values[numeric[i + 1]].Equals(station.values[first])) {
                last = numeric[++i];
            }
            if (last - first + 1 >= minimumRun) {
                r.runs.Add(new Run(first, last, r.values[first]));
                for (int t = first + 1; t <= last; t++)
                    r.reasons[t] = "flat";
            }
            i++;
        }
        foreach (int t in numeric)
            if (r.reasons[t] == null) {
                r.candidates.Add(t);
                r.candidate[t] = true;
            }
        return r;
    }
    public static void Spikes(Record r, double[] residuals, Records.Settings s) {
        int width = s.Integer("spike", 0), required = s.Integer("spike", 1);
        foreach (int t in r.candidates) {
            List<double> values = new();
            for (int u = Math.Max(r.first, t - width); u <= Math.Min(r.last, t + width); u++)
                if (r.candidate[u])
                    values.Add(residuals[u]);
            if (values.Count < required)
                continue;
            r.tested++;
            double center = Median(values);
            List<double> deviations = new();
            foreach (double value in values)
                deviations.Add(Math.Abs(value - center));
            double mad = Median(deviations),
                   limit = Math.Max(s.Real("spike", 2) * 1.4826 * mad, s.Real("spike", 3));
            if (Math.Abs(residuals[t] - center) > limit) {
                r.reasons[t] = "spike";
                r.spikes.Add(new Spike(t, r.values[t], residuals[t], center, mad, limit));
            }
        }
        foreach (int t in r.candidates)
            if (r.reasons[t] == null) {
                r.usable[t] = true;
                r.times.Add(t);
            }
        int gapTime = r.first;
        while (gapTime <= r.last) {
            if (r.reasons[gapTime] == null) {
                gapTime++;
                continue;
            }
            int first = gapTime;
            string cause = r.reasons[gapTime];
            while (gapTime + 1 <= r.last && r.reasons[gapTime + 1] != null) {
                gapTime++;
                if (!cause.Equals(r.reasons[gapTime]))
                    cause = "mixed";
            }
            r.gaps.Add(new Gap(first, gapTime, cause));
            gapTime++;
        }
    }
}
