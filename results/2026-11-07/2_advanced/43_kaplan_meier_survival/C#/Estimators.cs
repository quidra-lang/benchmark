using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Estimators {
    public static int Risk(List<Dataset.Subject> subjects, int time) {
        int result = 0;
        foreach (Dataset.Subject s in subjects)
            if (s.time >= time)
                result++;
        return result;
    }
    public static List<int> EventTimes(List<Dataset.Subject> subjects, bool reverse) {
        SortedSet<int> result = new(StringComparer.Ordinal);
        foreach (Dataset.Subject s in subjects)
            if (s.eventFlag == (reverse ? 0 : 1))
                result.Add(s.time);
        return new(result);
    }
    public sealed class Row {
        public int time, risk, events, censored;
        public double survival = 1, se, lower = double.NaN, upper = double.NaN, hazard, hazardSe;
    }
    public static List<Row> Km(List<Dataset.Subject> subjects, bool reverse) {
        List<int> times = EventTimes(subjects, reverse);
        List<Row> result = new();
        double survival = 1, greenwood = 0, hazard = 0, variance = 0;
        for (int i = 0; i < times.Count; i++) {
            int time = times[i], n = Risk(subjects, time), d = 0, censored = 0;
            foreach (Dataset.Subject s in subjects) {
                int eventFlag = reverse ? 1 - s.eventFlag : s.eventFlag;
                if (s.time == time && eventFlag == 1)
                    d++;
                if (eventFlag == 0 && s.time >= time && (i + 1 == times.Count || s.time < times[i + 1]))
                    censored++;
            }
            survival *= (double)(n - d) / n;
            hazard += (double)d / n;
            variance += (double)d / (n * n);
            Row r = new Row();
            r.time = time;
            r.risk = n;
            r.events = d;
            r.censored = censored;
            r.survival = survival;
            r.hazard = hazard;
            r.hazardSe = Math.Sqrt(variance);
            if (n == d) {
                greenwood = double.NaN;
                r.se = double.NaN;
            } else {
                greenwood += (double)d / (n * (n - d));
                r.se = survival * Math.Sqrt(greenwood);
                double log = Math.Log(survival), omega = Numerics.Z * Math.Sqrt(greenwood) / (-log);
                r.lower = Math.Exp(log * Math.Exp(omega));
                r.upper = Math.Exp(log * Math.Exp(-omega));
            }
            result.Add(r);
        }
        return result;
    }
    public static Row At(List<Row> rows, int time) {
        Row result = new Row();
        foreach (Row r in rows) {
            if (r.time > time)
                break;
            result = r;
        }
        return result;
    }
    public sealed class Life {
        public int start, end, risk, events, withdrawn, exposed2;
        public double q, survival, se, hazard;
    }
    public static List<Life> Life(List<Dataset.Subject> subjects, int width, int count) {
        List<Life> result = new();
        double survival = 1, greenwood = 0;
        for (int i = 0; i < count; i++) {
            Life r = new Life();
            r.start = i * width;
            r.end = (i + 1) * width;
            r.risk = Risk(subjects, r.start);
            foreach (Dataset.Subject s in subjects)
                if (s.time >= r.start && s.time < r.end) {
                    if (s.eventFlag == 1)
                        r.events++;
                    else
                        r.withdrawn++;
                }
            int f = 2 * r.risk - r.withdrawn;
            r.exposed2 = f;
            r.q = (double)(2 * r.events) / f;
            survival *= (double)(f - 2 * r.events) / f;
            greenwood += (double)(4 * r.events) / (f * (f - 2 * r.events));
            r.survival = survival;
            r.se = survival * Math.Sqrt(greenwood);
            r.hazard = (double)(2000 * r.events) / (width * (f - r.events));
            result.Add(r);
        }
        return result;
    }
}
