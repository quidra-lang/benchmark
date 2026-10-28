using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly List<string> LABELS = ["N", "V", "A"],
                                        CLASSES = ["qrs", "searchback", "twave", "refractory", "noise"];
    public sealed class Detection {
        public List<Detector.Peak> peaks, registered = new();
        public List<int> intervals = new();
        public Dictionary<string, int> settings;
        public long[] initial, levels;
        public int ra1 = 200, ra2 = 200;
        public Detection(List<Detector.Peak> peaks, Filters.Signals f, Dictionary<string, int> settings) {
            this.peaks = peaks;
            this.settings = settings;
            initial = Detector.Levels(f);
            levels = initial.ToArray();
        }
        public long[] Thresholds() {
            long i = levels[1] + Report.Div(levels[0] - levels[1], 4),
                 f = levels[3] + Report.Div(levels[2] - levels[3], 4);
            return new long[] { i, f, Report.Div(i, 2), Report.Div(f, 2) };
        }
        public void Register(Detector.Peak p) {
            if (registered.Count != 0) {
                int elapsed = p.time - registered[^1].time;
                intervals.Add(elapsed);
                if (intervals.Count > 8)
                    intervals.RemoveAt(0);
                int total = 0;
                foreach (int i in intervals)
                    total += i;
                ra1 = total / intervals.Count;
                if (92L * ra1 <= 100L * elapsed && 100L * elapsed <= 116L * ra1)
                    ra2 = ra1;
            }
            registered.Add(p);
        }
        public void Update(Detector.Peak p, int category) {
            int offset = category == 1 ? 1 : 0, weight = category == 2 ? 3 : 7, denominator = weight + 1;
            levels[offset] = Report.Div(p.peakI + weight * levels[offset], denominator);
            levels[offset + 2] = Report.Div(p.peakF + weight * levels[offset + 2], denominator);
        }
        public void Searchback(int time) {
            while (true) {
                int last = registered.Count == 0 ? 0 : registered[^1].time;
                if (time - last <= (long)ra2 * settings["searchback_percent"] / 100)
                    return;
                long[] t = Thresholds();
                Detector.Peak chosen = null;
                foreach (Detector.Peak p in peaks)
                    if (p.kind.Equals("noise") && p.time > last && p.time < time && p.peakI > t[2] &&
                        p.peakF > t[3] && (chosen == null || p.peakI > chosen.peakI))
                        chosen = p;
                if (chosen == null)
                    return;
                Update(chosen, 2);
                chosen.kind = "searchback";
                Register(chosen);
            }
        }
        public void Run(int n) {
            foreach (Detector.Peak p in peaks) {
                Searchback(p.time);
                long[] t = Thresholds();
                p.thrI = t[0];
                p.thrF = t[1];
                Detector.Peak last = registered.Count == 0 ? null : registered[^1];
                if (last != null && p.time - last.time < settings["refractory_ms"] / 5) {
                    p.kind = "refractory";
                    continue;
                }
                if (p.peakI > t[0] && p.peakF > t[1]) {
                    if (last != null && p.time - last.time < settings["twave_ms"] / 5 &&
                        2 * p.slope < last.slope) {
                        p.kind = "twave";
                        Update(p, 1);
                    } else {
                        p.kind = "qrs";
                        Update(p, 0);
                        Register(p);
                    }
                } else {
                    p.kind = "noise";
                    Update(p, 1);
                }
            }
            Searchback(n);
        }
    }
    public sealed class Beat {
        public int number, sample, width;
        public long rr, offset;
        public string label = "N", method;
        public SignalIo.Annotation annotation;
    }
    public static List<Beat> Beats(Detection detection, Filters.Signals f, Dictionary<string, int> settings) {
        List<Beat> result = new();
        foreach (Detector.Peak p in detection.registered) {
            Beat b = new Beat();
            b.number = result.Count + 1;
            b.sample = Math.Max(0, p.r - 21);
            b.rr = result.Count == 0 ? 0 : 5L * (b.sample - result[^1].sample);
            b.width = Detector.Width(f.band, p.r);
            b.method = p.kind.Equals("qrs") ? "threshold" : "searchback";
            if (b.number >= 10) {
                long previous = 0;
                for (int j = b.number - 9; j < b.number - 1; j++)
                    previous += result[j].rr;
                if (800 * b.rr < (long)settings["premature_percent"] * previous)
                    b.label = b.width > settings["qrs_width_ms"] ? "V" : "A";
            }
            result.Add(b);
        }
        return result;
    }
    public static void Match(List<Beat> beats, List<SignalIo.Annotation> references, int tolerance) {
        foreach (Beat b in beats) {
            SignalIo.Annotation chosen = null;
            int distance = int.MaxValue;
            foreach (SignalIo.Annotation r in references)
                if (r.beat == null) {
                    int d = Math.Abs(r.sample - b.sample);
                    if (d <= tolerance && d < distance) {
                        distance = d;
                        chosen = r;
                    }
                }
            if (chosen != null) {
                chosen.beat = b;
                b.annotation = chosen;
                b.offset = 5L * (b.sample - chosen.sample);
            }
        }
    }
    public record Row(int sample, int order, string text) {
    }
    public static List<string> Ordered(List<Row> rows) {
        rows.Sort(Comparer<Row>.Create((a, b) => a.sample != b.sample ? a.sample.CompareTo(b.sample)
                                                                      : a.order.CompareTo(b.order)));
        List<string> result = new();
        foreach (Row r in rows)
            result.Add(r.text);
        return result;
    }
    public static string Ref(Beat b) {
        return b.annotation == null ? "-" : b.annotation.label;
    }
    public static void Lists(List<Beat> beats, List<SignalIo.Annotation> refs, List<Detector.Peak> peaks,
                             long[] x, Filters.Signals f, Dictionary<string, int> settings) {
        List<string> output =
            new(["beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"]);
        foreach (Beat b in beats)
            output.Add(b.number + "," + b.sample + "," + (5 * b.sample) + "," +
                       (b.number == 1 ? "-" : Convert.ToString(b.rr)) + "," +
                       (b.number == 1 ? "-" : Report.Two(Report.Rdiv(6000000, b.rr))) + "," + b.width + "," +
                       b.label + "," + b.method + "," +
                       (b.annotation == null ? "-" : Convert.ToString(b.annotation.sample)) + "," + Ref(b));
        SignalIo.Write("beats.csv", output);
        output = new(["peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"]);
        for (int i = 0; i < peaks.Count; i++) {
            Detector.Peak p = peaks[i];
            output.Add((i + 1) + "," + p.time + "," + p.r + "," + p.peakI + "," + p.peakF + "," + p.slope +
                       "," + p.thrI + "," + p.thrF + "," + p.kind);
        }
        SignalIo.Write("peaks.csv", output);
        List<Row> rows = new();
        foreach (SignalIo.Annotation r in refs) {
            Beat b = r.beat;
            string text = b == null
                              ? r.sample + "," + r.label + ",-,-,-,-,FN,-"
                              : r.sample + "," + r.label + "," + b.number + "," + b.sample + "," + b.label +
                                    "," + b.offset + ",TP," + (b.label.Equals(r.label) ? "yes" : "no");
            rows.Add(new Row(r.sample, 0, text));
        }
        foreach (Beat b in beats)
            if (b.annotation == null)
                rows.Add(
                    new Row(b.sample, 1, "-,-," + b.number + "," + b.sample + "," + b.label + ",-,FP,-"));
        output = new(["ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"]);
        output.AddRange(Ordered(rows));
        SignalIo.Write("matching.csv", output);
        output = new(["sample,ecg,lowpass,bandpass,derivative,squared,integrated"]);
        for (int i = 0; i < settings["excerpt_ms"] / 5; i++)
            output.Add(i + "," + x[i] + "," + f.low[i] + "," + f.band[i] + "," + f.derivative[i] + "," +
                       f.squared[i] + "," + f.integrated[i]);
        SignalIo.Write("signals_excerpt.csv", output);
    }
    public sealed class Segment {
        public int start, end, refs, tp, fp, fn, noise, beats;
        public List<long> rr = new();
    }
    public static List<Segment> Segments(List<Beat> beats, List<SignalIo.Annotation> refs,
                                         List<Detector.Peak> peaks, int n, int size) {
        List<Segment> result = new();
        for (int start = 0; start < n; start += size) {
            Segment s = new Segment();
            int end = Math.Min(n, start + size);
            s.start = 5 * start;
            s.end = 5 * end;
            foreach (SignalIo.Annotation r in refs)
                if (r.sample >= start && r.sample < end) {
                    s.refs++;
                    if (r.beat != null)
                        s.tp++;
                }
            s.fn = s.refs - s.tp;
            foreach (Beat b in beats)
                if (b.sample >= start && b.sample < end) {
                    s.beats++;
                    if (b.annotation == null)
                        s.fp++;
                    if (b.number > 1)
                        s.rr.Add(b.rr);
                }
            foreach (Detector.Peak p in peaks)
                if (p.kind.Equals("noise") && p.time >= start && p.time < end)
                    s.noise++;
            result.Add(s);
        }
        return result;
    }
    public static string SegmentRange(Segment s) {
        return Report.Pad(Convert.ToString(s.start), 6) + "-" + Report.Pad(Convert.ToString(s.end), 6);
    }
    public static int LabelIndex(string label) {
        return LABELS.IndexOf(label);
    }
    public static string LevelLine(string heading, long[] l) {
        return heading + " spki=" + l[0] + " npki=" + l[1] + " spkf=" + l[2] + " npkf=" + l[3];
    }
    public static void Performance(Detection d, List<Beat> beats, List<SignalIo.Annotation> refs,
                                   List<Segment> segments, int n, Dictionary<string, int> settings) {
        int[] rc = new int[3], bc = new int[3], miss = new int[3], extra = new int[3];
        int[][] confusion = Enumerable.Range(0, 3)
                                .Select(
                                    _ => new int[3])
                                .ToArray();
        int tp = 0;
        long offset = 0, absolute = 0, maxAbs = 0;
        int[] method = new int[2], methodTp = new int[2];
        Dictionary<string, int> pc = new();
        foreach (Detector.Peak p in d.peaks)
            pc[p.kind] = pc.GetValueOrDefault(p.kind, 0) + 1;
        foreach (SignalIo.Annotation r in refs) {
            int i = LabelIndex(r.label);
            rc[i]++;
            if (r.beat == null)
                miss[i]++;
            else
                confusion[i][LabelIndex(r.beat.label)]++;
        }
        foreach (Beat b in beats) {
            int i = LabelIndex(b.label), m = b.method.Equals("threshold") ? 0 : 1;
            bc[i]++;
            method[m]++;
            if (b.annotation == null)
                extra[i]++;
            else {
                tp++;
                methodTp[m]++;
                offset += b.offset;
                absolute += Math.Abs(b.offset);
                maxAbs = Math.Max(maxAbs, Math.Abs(b.offset));
            }
        }
        int fp = beats.Count - tp, fn = refs.Count - tp;
        string peakLine = "peaks " + d.peaks.Count;
        foreach (string c in CLASSES)
            peakLine += " " + c + "=" + pc.GetValueOrDefault(c, 0);
        long[] t = d.Thresholds();
        List<string> output = new([
            "DETECTOR",
            "samples " + n,
            "duration_ms " + (5 * n),
            peakLine,
            LevelLine("initial_levels", d.initial),
            LevelLine("final_levels", d.levels),
            "final_thresholds thr_i=" + t[0] + " thr_f=" + t[1],
            "final_rr_averages rravg1_ms=" + (5 * d.ra1) + " rravg2_ms=" + (5 * d.ra2),
            "MATCHING",
            "tolerance_ms " + settings["match_ms"],
            "references " + refs.Count + " N=" + rc[0] + " V=" + rc[1] + " A=" + rc[2],
            "detections " + beats.Count + " N=" + bc[0] + " V=" + bc[1] + " A=" + bc[2],
            "true_positives " + tp,
            "false_positives " + fp,
            "false_negatives " + fn,
            "sensitivity " + Report.Ratio(tp, tp + fn),
            "positive_predictivity " + Report.Ratio(tp, tp + fp),
            "detection_error_rate " + Report.Ratio(fp + fn, refs.Count),
            "by_method threshold=" + methodTp[0] + "/" + method[0] + " searchback=" + methodTp[1] + "/" +
                method[1],
            tp == 0 ? "offset_ms none"
                    : "offset_ms mean=" + Report.Two(Report.Rdiv(100 * offset, tp)) +
                          " mean_abs=" + Report.Two(Report.Rdiv(100 * absolute, tp)) + " max_abs=" + maxAbs,
            "CONFUSION",
            "ref  " + Report.Pad("N", 6) + Report.Pad("V", 6) + Report.Pad("A", 6) + "  miss"
        ]);
        for (int i = 0; i < 3; i++) {
            string line = LABELS[i] + "    ";
            for (int j = 0; j < 3; j++)
                line += Report.Pad(Convert.ToString(confusion[i][j]), 6);
            output.Add(line + Report.Pad(Convert.ToString(miss[i]), 6));
        }
        string line = "extra";
        foreach (int i in extra)
            line += Report.Pad(Convert.ToString(i), 6);
        output.Add(line);
        output.AddRange(["veb_sensitivity " + Report.Ratio(confusion[1][1], rc[1]),
                         "veb_positive_predictivity " + Report.Ratio(confusion[1][1], bc[1]),
                         "sveb_sensitivity " + Report.Ratio(confusion[2][2], rc[2]),
                         "sveb_positive_predictivity " + Report.Ratio(confusion[2][2], bc[2]),
                         "SEGMENTS segment_ms=" + settings ["segment_ms"] + " segments=" + segments.Count]);
        foreach (Segment s in segments)
            output.Add(SegmentRange(s) + " refs=" + s.refs + " tp=" + s.tp + " fp=" + s.fp + " fn=" + s.fn +
                       " noise_peaks=" + s.noise);
        output.Add("ERRORS count=" + (fp + fn));
        List<Row> errors = new();
        foreach (Beat b in beats)
            if (b.annotation == null)
                errors.Add(new Row(b.sample, 0,
                                   "false_positive beat=" + b.number + " sample=" + b.sample +
                                       " time_ms=" + (5 * b.sample) + " label=" + b.label));
        foreach (SignalIo.Annotation r in refs)
            if (r.beat == null)
                errors.Add(new Row(r.sample, 1,
                                   "false_negative sample=" + r.sample + " time_ms=" + (5 * r.sample) +
                                       " label=" + r.label));
        output.AddRange(Ordered(errors));
        SignalIo.Write("performance.txt", output);
    }
    public static List<string> Runs(List<Beat> beats) {
        List<string> result = new();
        int i = 0;
        while (i < beats.Count) {
            Beat b = beats[i];
            if (b.label.Equals("N")) {
                i++;
                continue;
            }
            int end = i;
            while (end + 1 < beats.Count && beats[end + 1].label.Equals(b.label))
                end++;
            int length = end - i + 1;
            result.Add(b.label + " " +
                       (length == 1   ? "isolated"
                        : length == 2 ? "couplet"
                                      : "run") +
                       " beats=" + b.number + "-" + beats[end].number + " length=" + length +
                       " start_ms=" + (5 * b.sample));
            i = end + 1;
        }
        return result;
    }
    public static List<string> Events(List<Beat> beats, Dictionary<string, int> settings) {
        List<string> result = new();
        for (int i = 1; i < beats.Count; i++) {
            Beat b = beats[i];
            if (b.rr > settings["pause_ms"])
                result.Add("pause beats=" + i + "-" + (i + 1) + " rr_ms=" + b.rr +
                           " start_ms=" + (5 * beats[i - 1].sample));
        }
        foreach (string kind in new string[] { "bradycardia", "tachycardia" }) {
            List<int> selected = new();
            for (int i = 1; i < beats.Count; i++)
                if (kind.Equals("bradycardia") ? beats[i].rr > settings["brady_ms"]
                                               : beats[i].rr < settings["tachy_ms"])
                    selected.Add(i);
            foreach (int[] range in Hrv.Ranges(selected)) {
                int a = range[0], b = range[1], count = b - a + 1;
                if (count < 3)
                    continue;
                long sum = 0;
                for (int j = a; j <= b; j++)
                    sum += beats[j].rr;
                result.Add(kind + " beats=" + a + "-" + (b + 1) + " intervals=" + count +
                           " mean_hr=" + Report.Two(Report.Rdiv(6000000L * count, sum)) +
                           " start_ms=" + (5 * beats[a - 1].sample));
            }
        }
        List<int> ventricular = new();
        for (int i = 0; i < beats.Count; i++)
            if (beats[i].label.Equals("V"))
                ventricular.Add(i);
        foreach (int gap in new int[] { 2, 3 }) {
            List<int> chain = new();
            for (int index = 0; index <= ventricular.Count; index++) {
                int v = index == ventricular.Count ? -1 : ventricular[index];
                bool linked = chain.Count != 0 && v == chain[^1] + gap;
                if (linked)
                    for (int j = chain[^1] + 1; j < v; j++)
                        if (!beats[j].label.Equals("N"))
                            linked = false;
                if (!linked) {
                    if (chain.Count >= 3) {
                        int first = chain[0], last = chain[^1];
                        result.Add((gap == 2 ? "bigeminy" : "trigeminy") + " beats=" + (first + 1) + "-" +
                                   (last + 1) + " cycles=" + chain.Count +
                                   " start_ms=" + (5 * beats[first].sample));
                    }
                    chain.Clear();
                }
                if (v != -1)
                    chain.Add(v);
            }
        }
        return result;
    }
    public static void WriteHrv(List<Beat> beats, List<Segment> segments,
                                Dictionary<string, int> settings) public {
        Hrv.Rr rr = Hrv.CalculateRr(beats);
        Hrv.Nn nn = Hrv.CalculateNn(beats);
        List<string> output = new([
            "RR", "beats " + beats.Count, "intervals " + rr.count, "mean_rr_ms " + Report.Maybe(rr.mean),
            rr.count == 0 ? "min_rr_ms none" : "min_rr_ms " + rr.shortest + " beat=" + rr.shortBeat,
            rr.count == 0 ? "max_rr_ms none" : "max_rr_ms " + rr.longest + " beat=" + rr.longBeat,
            "mean_hr_bpm " + Report.Maybe(rr.hr), "NN", "intervals " + nn.e,
            "mean_nn_ms " + Report.Maybe(nn.mean), "sdnn_ms " + Report.Maybe(nn.sdnn), "differences " + nn.k,
            "rmssd_ms " + Report.Maybe(nn.rmssd), "sdsd_ms " + Report.Maybe(nn.sdsd), "nn50 " + nn.nn50,
            nn.k == 0 ? "pnn50 none" : "pnn50 " + Report.Two(nn.pnn50) + "%",
            "sd1_ms " + Report.Maybe(nn.sd1), "sd2_ms " + Report.Maybe(nn.sd2),
            "HISTOGRAM bin_ms=7.8125 bins=" + nn.histogram.Count + " max=" + nn.maximum
        ]);
        foreach (var e in nn.histogram)
            output.Add(Report.Pad(Report.Four(78125 * e.Key), 10) + " " +
                       Report.Pad(Report.Four(78125 * (e.Key + 1)), 10) + " " +
                       Report.Pad(e.Value.ToString(), 3) + " |" + "#".Repeat(e.Value));
        output.Add(nn.e == 0 ? "triangular_index none"
                             : "triangular_index " + Report.Fraction(nn.e, nn.maximum) + " " +
                                   Report.Two(Report.Rdiv(100L * nn.e, nn.maximum)));
        int v = 0, a = 0;
        foreach (Beat b in beats) {
            if (b.label.Equals("V"))
                v++;
            if (b.label.Equals("A"))
                a++;
        }
        output.Add("PREMATURE count=" + (v + a) + " V=" + v + " A=" + a);
        for (int i = 0; i < beats.Count; i++) {
            Beat b = beats[i];
            if (b.label.Equals("N"))
                continue;
            long sum = 0;
            for (int j = i - 8; j < i; j++)
                sum += beats[j].rr;
            string compensation = "-", next = "-";
            if (i + 1 < beats.Count) {
                long nextRr = beats[i + 1].rr, total = b.rr + nextRr;
                next = Convert.ToString(nextRr);
                compensation = 10 * Math.Abs(4 * total - sum) <= sum ? "full"
                               : 4 * total < sum                     ? "partial"
                                                                     : "long";
            }
            output.Add("beat=" + b.number + " sample=" + b.sample + " label=" + b.label + " rr_ms=" + b.rr +
                       " next_rr_ms=" + next + " mean_ms=" + Report.Two(Report.Rdiv(100 * sum, 8)) +
                       " prematurity=" + Report.Two(Report.Rdiv(80000 * b.rr, sum)) +
                       "% compensation=" + compensation + " width_ms=" + b.width + " ref=" + Ref(b));
        }
        List<string> runs = Runs(beats), events = Events(beats, settings);
        output.Add("RUNS count=" + runs.Count);
        output.AddRange(runs);
        output.Add("EVENTS count=" + events.Count);
        output.AddRange(events);
        output.Add("TREND segment_ms=" + settings["segment_ms"] + " segments=" + segments.Count);
        foreach (Segment s in segments) {
            string prefix = SegmentRange(s) + " beats=" + s.beats;
            if (s.rr.Count == 0)
                output.Add(prefix + " mean_hr=none min_hr=none max_hr=none |");
            else {
                long h = Hrv.HeartRate(s.rr), minimum = s.rr.Min(), maximum = s.rr.Max();
                output.Add(prefix + " mean_hr=" + Report.Two(h) +
                           " min_hr=" + Report.Two(Report.Rdiv(6000000, maximum)) +
                           " max_hr=" + Report.Two(Report.Rdiv(6000000, minimum)) + " |" +
                           "#".Repeat((int)Report.Rdiv(h, 500)));
            }
        }
        SignalIo.Write("hrv.txt", output);
    }
    public static int Scale(long value, long top, long bottom, int rows) {
        return top == bottom ? 0 : (int)Report.Rdiv((top - value) * (rows - 1), top - bottom);
    }
    public static List<string> Waveform(long[] upper, long[] lower, int rows) {
        long top = long.MinValue, bottom = long.MaxValue;
        foreach (long v in upper)
            top = Math.Max(top, v);
        foreach (long v in lower)
            bottom = Math.Min(bottom, v);
        int zero = bottom <= 0 && top >= 0 ? Scale(0, top, bottom, rows) : -1;
        List<string> output = new();
        for (int row = 0; row < rows; row++) {
            string label = row == 0          ? Convert.ToString(top)
                           : row == rows - 1 ? Convert.ToString(bottom)
                           : row == zero     ? "0"
                                             : "";
            StringBuilder line = new StringBuilder(Report.Pad(label, 6) + " |");
            for (int i = 0; i < upper.Length; i++)
                line.Append(Scale(upper[i], top, bottom, rows) <= row &&
                                    row <= Scale(lower[i], top, bottom, rows)
                                ? '#'
                            : row == zero ? '-'
                                          : ' ');
            output.Add(line + "|");
        }
        return output;
    }
    public static string Axis(int columns, int period, int offset) {
        StringBuilder line = new StringBuilder("       +");
        for (int i = 0; i < columns; i++)
            line.Append((i + offset) % period == 0 ? '+' : '-');
        return line + "+";
    }
    public static string LabelRow(string heading, SortedDictionary<int, string> labels) {
        StringBuilder line = new StringBuilder(Report.Pad(heading, 6) + "  ");
        foreach (var e in labels) {
            while (line.Length < 8 + e.Key)
                line.Append(' ');
            line.Append(e.Value);
        }
        return line.ToString();
    }
    public static void Charts(List<Beat> beats, long[] x, Dictionary<string, int> settings) {
        List<string> output = new();
        List<long> rr = new();
        foreach (Beat b in beats)
            if (b.number > 1)
                rr.Add(b.rr);
        int rows = settings["chart_rows"];
        if (rr.Count == 0)
            output.AddRange(["TACHOGRAM intervals=0", "POINCARE points=0"]);
        else {
            long lo = rr.Min(), hi = rr.Max();
            output.Add("TACHOGRAM intervals=" + rr.Count + " min_ms=" + lo + " max_ms=" + hi +
                       " rows=" + rows);
            for (int r = 0; r < rows; r++) {
                StringBuilder line = new StringBuilder(Report.Pad(r == 0          ? Convert.ToString(hi)
                                                                  : r == rows - 1 ? Convert.ToString(lo)
                                                                                  : "",
                                                                  6) +
                                                       " |");
                foreach (long value in rr)
                    line.Append(Scale(value, hi, lo, rows) == r ? '*' : ' ');
                output.Add(line + "|");
            }
            output.Add(Axis(rr.Count, 10, 2));
            SortedDictionary<int, string> labels = new();
            for (int j = 0; j < rr.Count; j++)
                if ((j + 2) % 10 == 0)
                    labels[j] = Convert.ToString(j + 2);
            output.Add(LabelRow("beat", labels));
            StringBuilder line = new StringBuilder(" label |");
            for (int i = 1; i < beats.Count; i++)
                line.Append(beats[i].label);
            output.Add(line + "|");
            int size = settings["poincare_size"];
            int[][] cells = Enumerable.Range(0, size)
                                .Select(
                                    _ => new int[size])
                                .ToArray();
            for (int j = 0; j + 1 < rr.Count; j++) {
                int col = hi == lo ? 0 : (int)Report.Rdiv((rr[j] - lo) * (size - 1), hi - lo),
                    row = Scale(rr[j + 1], hi, lo, size);
                cells[row][col]++;
            }
            output.Add("POINCARE points=" + (rr.Count - 1) + " size=" + size + " min_ms=" + lo +
                       " max_ms=" + hi);
            for (int r = 0; r < size; r++) {
                line = new StringBuilder(Report.Pad(r == 0          ? Convert.ToString(hi)
                                                    : r == size - 1 ? Convert.ToString(lo)
                                                                    : "",
                                                    6) +
                                         " |");
                foreach (int c in cells[r])
                    line.Append(c == 0 ? '.' : c < 10 ? (char)('0' + c) : '#');
                output.Add(line + "|");
            }
            output.Add("       +" + "-".Repeat(size) + "+");
            string low = Convert.ToString(lo), high = Convert.ToString(hi);
            output.Add("        " + low + " ".Repeat(size - low.Length - high.Length) + high);
        }
        foreach (string label in LABELS) {
            List<Beat> chosen = new();
            foreach (Beat b in beats)
                if (b.label.Equals(label) && b.sample >= 60 && b.sample <= x.Length - 100)
                    chosen.Add(b);
            if (chosen.Count == 0) {
                output.Add("TEMPLATE " + label + " beats=0");
                continue;
            }
            long[] template = new long[160];
            foreach (Beat b in chosen) {
                long baseline = 0;
                for (int j = -60; j < -50; j++)
                    baseline += x[b.sample + j];
                for (int j = -60; j < 100; j++)
                    template[j + 60] += 10 * x[b.sample + j] - baseline;
            }
            int max = 0, min = 0;
            for (int j = 0; j < 160; j++) {
                template[j] = Report.Rdiv(template[j], 10L * chosen.Count);
                if (template[j] > template[max])
                    max = j;
                if (template[j] < template[min])
                    min = j;
            }
            output.Add("TEMPLATE " + label + " beats=" + chosen.Count + " max_uv=" + template[max] +
                       " max_ms=" + (5 * (max - 60)) + " min_uv=" + template[min] +
                       " min_ms=" + (5 * (min - 60)) + " rows=" + rows);
            long[] upper = new long[80], lower = new long[80];
            for (int i = 0; i < 80; i++) {
                upper[i] = Math.Max(template[2 * i], template[2 * i + 1]);
                lower[i] = Math.Min(template[2 * i], template[2 * i + 1]);
            }
            output.AddRange(Waveform(upper, lower, rows));
            output.Add(Axis(80, 10, 0));
            SortedDictionary<int, string> labels = new();
            for (int i = 0; i < 80; i += 10)
                labels[i] = Convert.ToString(10 * i - 300);
            output.Add(LabelRow("ms", labels));
        }
        SignalIo.Write("charts.txt", output);
    }
    public static void Rhythm(List<Beat> beats, List<SignalIo.Annotation> refs, long[] x,
                              Dictionary<string, int> p) public {
        int start = p["strip_start_ms"] / 5, length = p["strip_ms"] / 5, columns = length / 10,
            rows = p["strip_rows"];
        long[] upper = new long[columns], lower = new long[columns];
        Array.Fill(upper, long.MinValue);
        Array.Fill(lower, long.MaxValue);
        long top = long.MinValue, bottom = long.MaxValue;
        for (int i = 0; i < length; i++) {
            long v = x[start + i];
            int c = i / 10;
            upper[c] = Math.Max(upper[c], v);
            lower[c] = Math.Min(lower[c], v);
            top = Math.Max(top, v);
            bottom = Math.Min(bottom, v);
        }
        List<string> output = new(
            ["RHYTHM start_ms=" + p["strip_start_ms"] + " end_ms=" + (p["strip_start_ms"] + p["strip_ms"]) +
             " columns=" + columns + " rows=" + rows + " max_uv=" + top + " min_uv=" + bottom]);
        output.AddRange(Waveform(upper, lower, rows));
        output.Add(Axis(columns, 20, 0));
        SortedDictionary<int, string> labels = new();
        for (int i = 0; i < columns; i += 20)
            labels[i] = Convert.ToString((p["strip_start_ms"] + 50 * i) / 1000);
        output.Add(LabelRow("s", labels));
        char[] detected = new char[columns], reference = new char[columns];
        Array.Fill(detected, ' ');
        Array.Fill(reference, ' ');
        foreach (Beat b in beats)
            if (b.sample >= start && b.sample < start + length)
                detected[(b.sample - start) / 10] = b.label[0];
        foreach (SignalIo.Annotation r in refs)
            if (r.sample >= start && r.sample < start + length)
                reference[(r.sample - start) / 10] = r.label[0];
        output.Add(" beats |" + new string(detected) + "|");
        output.Add("  refs |" + new string(reference) + "|");
        SignalIo.Write("rhythm_strip.txt", output);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        long[] x = SignalIo.Ecg();
        List<SignalIo.Annotation> refs = SignalIo.Annotations();
        Dictionary<string, int> p = SignalIo.Parameters();
        Filters.Signals f = Filters.Apply(x);
        List<Detector.Peak> peaks = Detector.Peaks(f);
        Detection d = new Detection(peaks, f, p);
        d.Run(x.Length);
        List<Beat> beats = Beats(d, f, p);
        Match(beats, refs, p["match_ms"] / 5);
        List<Segment> segments = Segments(beats, refs, peaks, x.Length, p["segment_ms"] / 5);
        Lists(beats, refs, peaks, x, f, p);
        Performance(d, beats, refs, segments, x.Length, p);
        WriteHrv(beats, segments, p);
        Charts(beats, x, p);
        Rhythm(beats, refs, x, p);
    }
}
