import java.io.IOException;
import java.util.*;

public final class Main {
    static final List<String> LABELS = List.of("N", "V", "A"),
                              CLASSES = List.of("qrs", "searchback", "twave", "refractory", "noise");
    static final class Detection {
        List<Detector.Peak> peaks, registered = new ArrayList<>();
        List<Integer> intervals = new ArrayList<>();
        Map<String, Integer> params;
        long[] initial, levels;
        int ra1 = 200, ra2 = 200;
        Detection(List<Detector.Peak> peaks, Filters.Signals f, Map<String, Integer> params) {
            this.peaks = peaks;
            this.params = params;
            initial = Detector.levels(f);
            levels = initial.clone();
        }
        long[] thresholds() {
            long i = levels[1] + Report.div(levels[0] - levels[1], 4),
                 f = levels[3] + Report.div(levels[2] - levels[3], 4);
            return new long[] {i, f, Report.div(i, 2), Report.div(f, 2)};
        }
        void register(Detector.Peak p) {
            if (!registered.isEmpty()) {
                int elapsed = p.time - registered.getLast().time;
                intervals.add(elapsed);
                if (intervals.size() > 8)
                    intervals.remove(0);
                int total = 0;
                for (int i : intervals)
                    total += i;
                ra1 = total / intervals.size();
                if (92L * ra1 <= 100L * elapsed && 100L * elapsed <= 116L * ra1)
                    ra2 = ra1;
            }
            registered.add(p);
        }
        void update(Detector.Peak p, int category) {
            int offset = category == 1 ? 1 : 0, weight = category == 2 ? 3 : 7, denominator = weight + 1;
            levels[offset] = Report.div(p.peakI + weight * levels[offset], denominator);
            levels[offset + 2] = Report.div(p.peakF + weight * levels[offset + 2], denominator);
        }
        void searchback(int time) {
            while (true) {
                int last = registered.isEmpty() ? 0 : registered.getLast().time;
                if (time - last <= (long)ra2 * params.get("searchback_percent") / 100)
                    return;
                long[] t = thresholds();
                Detector.Peak chosen = null;
                for (Detector.Peak p : peaks)
                    if (p.kind.equals("noise") && p.time > last && p.time < time && p.peakI > t[2] &&
                        p.peakF > t[3] && (chosen == null || p.peakI > chosen.peakI))
                        chosen = p;
                if (chosen == null)
                    return;
                update(chosen, 2);
                chosen.kind = "searchback";
                register(chosen);
            }
        }
        void run(int n) {
            for (Detector.Peak p : peaks) {
                searchback(p.time);
                long[] t = thresholds();
                p.thrI = t[0];
                p.thrF = t[1];
                Detector.Peak last = registered.isEmpty() ? null : registered.getLast();
                if (last != null && p.time - last.time < params.get("refractory_ms") / 5) {
                    p.kind = "refractory";
                    continue;
                }
                if (p.peakI > t[0] && p.peakF > t[1]) {
                    if (last != null && p.time - last.time < params.get("twave_ms") / 5 &&
                        2 * p.slope < last.slope) {
                        p.kind = "twave";
                        update(p, 1);
                    } else {
                        p.kind = "qrs";
                        update(p, 0);
                        register(p);
                    }
                } else {
                    p.kind = "noise";
                    update(p, 1);
                }
            }
            searchback(n);
        }
    }
    static final class Beat {
        int number, sample, width;
        long rr, offset;
        String label = "N", method;
        SignalIo.Annotation annotation;
    }
    static List<Beat> beats(Detection detection, Filters.Signals f, Map<String, Integer> params) {
        List<Beat> result = new ArrayList<>();
        for (Detector.Peak p : detection.registered) {
            Beat b = new Beat();
            b.number = result.size() + 1;
            b.sample = Math.max(0, p.r - 21);
            b.rr = result.isEmpty() ? 0 : 5L * (b.sample - result.getLast().sample);
            b.width = Detector.width(f.band, p.r);
            b.method = p.kind.equals("qrs") ? "threshold" : "searchback";
            if (b.number >= 10) {
                long previous = 0;
                for (int j = b.number - 9; j < b.number - 1; j++)
                    previous += result.get(j).rr;
                if (800 * b.rr < (long)params.get("premature_percent") * previous)
                    b.label = b.width > params.get("qrs_width_ms") ? "V" : "A";
            }
            result.add(b);
        }
        return result;
    }
    static void match(List<Beat> beats, List<SignalIo.Annotation> references, int tolerance) {
        for (Beat b : beats) {
            SignalIo.Annotation chosen = null;
            int distance = Integer.MAX_VALUE;
            for (SignalIo.Annotation r : references)
                if (r.beat == null) {
                    int d = Math.abs(r.sample - b.sample);
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
    record Row(int sample, int order, String text) {}
    static List<String> ordered(List<Row> rows) {
        rows.sort(Comparator.comparingInt(Row::sample).thenComparingInt(Row::order));
        List<String> result = new ArrayList<>();
        for (Row r : rows)
            result.add(r.text);
        return result;
    }
    static String ref(Beat b) {
        return b.annotation == null ? "-" : b.annotation.label;
    }
    static void lists(List<Beat> beats, List<SignalIo.Annotation> refs, List<Detector.Peak> peaks, long[] x,
                      Filters.Signals f, Map<String, Integer> params) throws IOException {
        List<String> output = new ArrayList<>(
            List.of("beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label"));
        for (Beat b : beats)
            output.add(b.number + "," + b.sample + "," + (5 * b.sample) + "," +
                       (b.number == 1 ? "-" : Long.toString(b.rr)) + "," +
                       (b.number == 1 ? "-" : Report.two(Report.rdiv(6000000, b.rr))) + "," + b.width + "," +
                       b.label + "," + b.method + "," +
                       (b.annotation == null ? "-" : Integer.toString(b.annotation.sample)) + "," + ref(b));
        SignalIo.write("beats.csv", output);
        output = new ArrayList<>(List.of("peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class"));
        for (int i = 0; i < peaks.size(); i++) {
            Detector.Peak p = peaks.get(i);
            output.add((i + 1) + "," + p.time + "," + p.r + "," + p.peakI + "," + p.peakF + "," + p.slope +
                       "," + p.thrI + "," + p.thrF + "," + p.kind);
        }
        SignalIo.write("peaks.csv", output);
        List<Row> rows = new ArrayList<>();
        for (SignalIo.Annotation r : refs) {
            Beat b = r.beat;
            String text = b == null
                              ? r.sample + "," + r.label + ",-,-,-,-,FN,-"
                              : r.sample + "," + r.label + "," + b.number + "," + b.sample + "," + b.label +
                                    "," + b.offset + ",TP," + (b.label.equals(r.label) ? "yes" : "no");
            rows.add(new Row(r.sample, 0, text));
        }
        for (Beat b : beats)
            if (b.annotation == null)
                rows.add(
                    new Row(b.sample, 1, "-,-," + b.number + "," + b.sample + "," + b.label + ",-,FP,-"));
        output = new ArrayList<>(
            List.of("ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree"));
        output.addAll(ordered(rows));
        SignalIo.write("matching.csv", output);
        output = new ArrayList<>(List.of("sample,ecg,lowpass,bandpass,derivative,squared,integrated"));
        for (int i = 0; i < params.get("excerpt_ms") / 5; i++)
            output.add(i + "," + x[i] + "," + f.low[i] + "," + f.band[i] + "," + f.derivative[i] + "," +
                       f.squared[i] + "," + f.integrated[i]);
        SignalIo.write("signals_excerpt.csv", output);
    }
    static final class Segment {
        int start, end, refs, tp, fp, fn, noise, beats;
        List<Long> rr = new ArrayList<>();
    }
    static List<Segment> segments(List<Beat> beats, List<SignalIo.Annotation> refs, List<Detector.Peak> peaks,
                                  int n, int size) {
        List<Segment> result = new ArrayList<>();
        for (int start = 0; start < n; start += size) {
            Segment s = new Segment();
            int end = Math.min(n, start + size);
            s.start = 5 * start;
            s.end = 5 * end;
            for (SignalIo.Annotation r : refs)
                if (r.sample >= start && r.sample < end) {
                    s.refs++;
                    if (r.beat != null)
                        s.tp++;
                }
            s.fn = s.refs - s.tp;
            for (Beat b : beats)
                if (b.sample >= start && b.sample < end) {
                    s.beats++;
                    if (b.annotation == null)
                        s.fp++;
                    if (b.number > 1)
                        s.rr.add(b.rr);
                }
            for (Detector.Peak p : peaks)
                if (p.kind.equals("noise") && p.time >= start && p.time < end)
                    s.noise++;
            result.add(s);
        }
        return result;
    }
    static String segmentRange(Segment s) {
        return Report.pad(Integer.toString(s.start), 6) + "-" + Report.pad(Integer.toString(s.end), 6);
    }
    static int labelIndex(String label) {
        return LABELS.indexOf(label);
    }
    static String levelLine(String heading, long[] l) {
        return heading + " spki=" + l[0] + " npki=" + l[1] + " spkf=" + l[2] + " npkf=" + l[3];
    }
    static void performance(Detection d, List<Beat> beats, List<SignalIo.Annotation> refs,
                            List<Segment> segments, int n, Map<String, Integer> params) throws IOException {
        int[] rc = new int[3], bc = new int[3], miss = new int[3], extra = new int[3];
        int[][] confusion = new int[3][3];
        int tp = 0;
        long offset = 0, absolute = 0, maxAbs = 0;
        int[] method = new int[2], methodTp = new int[2];
        Map<String, Integer> pc = new HashMap<>();
        for (Detector.Peak p : d.peaks)
            pc.put(p.kind, pc.getOrDefault(p.kind, 0) + 1);
        for (SignalIo.Annotation r : refs) {
            int i = labelIndex(r.label);
            rc[i]++;
            if (r.beat == null)
                miss[i]++;
            else
                confusion[i][labelIndex(r.beat.label)]++;
        }
        for (Beat b : beats) {
            int i = labelIndex(b.label), m = b.method.equals("threshold") ? 0 : 1;
            bc[i]++;
            method[m]++;
            if (b.annotation == null)
                extra[i]++;
            else {
                tp++;
                methodTp[m]++;
                offset += b.offset;
                absolute += Math.abs(b.offset);
                maxAbs = Math.max(maxAbs, Math.abs(b.offset));
            }
        }
        int fp = beats.size() - tp, fn = refs.size() - tp;
        String peakLine = "peaks " + d.peaks.size();
        for (String c : CLASSES)
            peakLine += " " + c + "=" + pc.getOrDefault(c, 0);
        long[] t = d.thresholds();
        List<String> output = new ArrayList<>(List.of(
            "DETECTOR", "samples " + n, "duration_ms " + (5 * n), peakLine,
            levelLine("initial_levels", d.initial), levelLine("final_levels", d.levels),
            "final_thresholds thr_i=" + t[0] + " thr_f=" + t[1],
            "final_rr_averages rravg1_ms=" + (5 * d.ra1) + " rravg2_ms=" + (5 * d.ra2), "MATCHING",
            "tolerance_ms " + params.get("match_ms"),
            "references " + refs.size() + " N=" + rc[0] + " V=" + rc[1] + " A=" + rc[2],
            "detections " + beats.size() + " N=" + bc[0] + " V=" + bc[1] + " A=" + bc[2],
            "true_positives " + tp, "false_positives " + fp, "false_negatives " + fn,
            "sensitivity " + Report.ratio(tp, tp + fn), "positive_predictivity " + Report.ratio(tp, tp + fp),
            "detection_error_rate " + Report.ratio(fp + fn, refs.size()),
            "by_method threshold=" + methodTp[0] + "/" + method[0] + " searchback=" + methodTp[1] + "/" +
                method[1],
            tp == 0 ? "offset_ms none"
                    : "offset_ms mean=" + Report.two(Report.rdiv(100 * offset, tp)) +
                          " mean_abs=" + Report.two(Report.rdiv(100 * absolute, tp)) + " max_abs=" + maxAbs,
            "CONFUSION", "ref  " + Report.pad("N", 6) + Report.pad("V", 6) + Report.pad("A", 6) + "  miss"));
        for (int i = 0; i < 3; i++) {
            String line = LABELS.get(i) + "    ";
            for (int j = 0; j < 3; j++)
                line += Report.pad(Integer.toString(confusion[i][j]), 6);
            output.add(line + Report.pad(Integer.toString(miss[i]), 6));
        }
        String line = "extra";
        for (int i : extra)
            line += Report.pad(Integer.toString(i), 6);
        output.add(line);
        output.addAll(
            List.of("veb_sensitivity " + Report.ratio(confusion[1][1], rc[1]),
                    "veb_positive_predictivity " + Report.ratio(confusion[1][1], bc[1]),
                    "sveb_sensitivity " + Report.ratio(confusion[2][2], rc[2]),
                    "sveb_positive_predictivity " + Report.ratio(confusion[2][2], bc[2]),
                    "SEGMENTS segment_ms=" + params.get("segment_ms") + " segments=" + segments.size()));
        for (Segment s : segments)
            output.add(segmentRange(s) + " refs=" + s.refs + " tp=" + s.tp + " fp=" + s.fp + " fn=" + s.fn +
                       " noise_peaks=" + s.noise);
        output.add("ERRORS count=" + (fp + fn));
        List<Row> errors = new ArrayList<>();
        for (Beat b : beats)
            if (b.annotation == null)
                errors.add(new Row(b.sample, 0,
                                   "false_positive beat=" + b.number + " sample=" + b.sample +
                                       " time_ms=" + (5 * b.sample) + " label=" + b.label));
        for (SignalIo.Annotation r : refs)
            if (r.beat == null)
                errors.add(new Row(r.sample, 1,
                                   "false_negative sample=" + r.sample + " time_ms=" + (5 * r.sample) +
                                       " label=" + r.label));
        output.addAll(ordered(errors));
        SignalIo.write("performance.txt", output);
    }
    static List<String> runs(List<Beat> beats) {
        List<String> result = new ArrayList<>();
        int i = 0;
        while (i < beats.size()) {
            Beat b = beats.get(i);
            if (b.label.equals("N")) {
                i++;
                continue;
            }
            int end = i;
            while (end + 1 < beats.size() && beats.get(end + 1).label.equals(b.label))
                end++;
            int length = end - i + 1;
            result.add(b.label + " " +
                       (length == 1   ? "isolated"
                        : length == 2 ? "couplet"
                                      : "run") +
                       " beats=" + b.number + "-" + beats.get(end).number + " length=" + length +
                       " start_ms=" + (5 * b.sample));
            i = end + 1;
        }
        return result;
    }
    static List<String> events(List<Beat> beats, Map<String, Integer> params) {
        List<String> result = new ArrayList<>();
        for (int i = 1; i < beats.size(); i++) {
            Beat b = beats.get(i);
            if (b.rr > params.get("pause_ms"))
                result.add("pause beats=" + i + "-" + (i + 1) + " rr_ms=" + b.rr +
                           " start_ms=" + (5 * beats.get(i - 1).sample));
        }
        for (String kind : List.of("bradycardia", "tachycardia")) {
            List<Integer> selected = new ArrayList<>();
            for (int i = 1; i < beats.size(); i++)
                if (kind.equals("bradycardia") ? beats.get(i).rr > params.get("brady_ms")
                                               : beats.get(i).rr < params.get("tachy_ms"))
                    selected.add(i);
            for (int[] range : Hrv.ranges(selected)) {
                int a = range[0], b = range[1], count = b - a + 1;
                if (count < 3)
                    continue;
                long sum = 0;
                for (int j = a; j <= b; j++)
                    sum += beats.get(j).rr;
                result.add(kind + " beats=" + a + "-" + (b + 1) + " intervals=" + count +
                           " mean_hr=" + Report.two(Report.rdiv(6000000L * count, sum)) +
                           " start_ms=" + (5 * beats.get(a - 1).sample));
            }
        }
        List<Integer> ventricular = new ArrayList<>();
        for (int i = 0; i < beats.size(); i++)
            if (beats.get(i).label.equals("V"))
                ventricular.add(i);
        for (int gap : List.of(2, 3)) {
            List<Integer> chain = new ArrayList<>();
            for (int index = 0; index <= ventricular.size(); index++) {
                int v = index == ventricular.size() ? -1 : ventricular.get(index);
                boolean linked = !chain.isEmpty() && v == chain.getLast() + gap;
                if (linked)
                    for (int j = chain.getLast() + 1; j < v; j++)
                        if (!beats.get(j).label.equals("N"))
                            linked = false;
                if (!linked) {
                    if (chain.size() >= 3) {
                        int first = chain.getFirst(), last = chain.getLast();
                        result.add((gap == 2 ? "bigeminy" : "trigeminy") + " beats=" + (first + 1) + "-" +
                                   (last + 1) + " cycles=" + chain.size() +
                                   " start_ms=" + (5 * beats.get(first).sample));
                    }
                    chain.clear();
                }
                if (v != -1)
                    chain.add(v);
            }
        }
        return result;
    }
    static void hrv(List<Beat> beats, List<Segment> segments, Map<String, Integer> params)
        throws IOException {
        Hrv.Rr rr = Hrv.rr(beats);
        Hrv.Nn nn = Hrv.nn(beats);
        List<String> output = new ArrayList<>(List.of(
            "RR", "beats " + beats.size(), "intervals " + rr.count, "mean_rr_ms " + Report.maybe(rr.mean),
            rr.count == 0 ? "min_rr_ms none" : "min_rr_ms " + rr.shortest + " beat=" + rr.shortBeat,
            rr.count == 0 ? "max_rr_ms none" : "max_rr_ms " + rr.longest + " beat=" + rr.longBeat,
            "mean_hr_bpm " + Report.maybe(rr.hr), "NN", "intervals " + nn.e,
            "mean_nn_ms " + Report.maybe(nn.mean), "sdnn_ms " + Report.maybe(nn.sdnn), "differences " + nn.k,
            "rmssd_ms " + Report.maybe(nn.rmssd), "sdsd_ms " + Report.maybe(nn.sdsd), "nn50 " + nn.nn50,
            nn.k == 0 ? "pnn50 none" : "pnn50 " + Report.two(nn.pnn50) + "%",
            "sd1_ms " + Report.maybe(nn.sd1), "sd2_ms " + Report.maybe(nn.sd2),
            "HISTOGRAM bin_ms=7.8125 bins=" + nn.histogram.size() + " max=" + nn.maximum));
        for (var e : nn.histogram.entrySet())
            output.add(Report.pad(Report.four(78125 * e.getKey()), 10) + " " +
                       Report.pad(Report.four(78125 * (e.getKey() + 1)), 10) + " " +
                       Report.pad(e.getValue().toString(), 3) + " |"
                       + "#".repeat(e.getValue()));
        output.add(nn.e == 0 ? "triangular_index none"
                             : "triangular_index " + Report.fraction(nn.e, nn.maximum) + " " +
                                   Report.two(Report.rdiv(100L * nn.e, nn.maximum)));
        int v = 0, a = 0;
        for (Beat b : beats) {
            if (b.label.equals("V"))
                v++;
            if (b.label.equals("A"))
                a++;
        }
        output.add("PREMATURE count=" + (v + a) + " V=" + v + " A=" + a);
        for (int i = 0; i < beats.size(); i++) {
            Beat b = beats.get(i);
            if (b.label.equals("N"))
                continue;
            long sum = 0;
            for (int j = i - 8; j < i; j++)
                sum += beats.get(j).rr;
            String compensation = "-", next = "-";
            if (i + 1 < beats.size()) {
                long nextRr = beats.get(i + 1).rr, total = b.rr + nextRr;
                next = Long.toString(nextRr);
                compensation = 10 * Math.abs(4 * total - sum) <= sum ? "full"
                               : 4 * total < sum                     ? "partial"
                                                                     : "long";
            }
            output.add("beat=" + b.number + " sample=" + b.sample + " label=" + b.label + " rr_ms=" + b.rr +
                       " next_rr_ms=" + next + " mean_ms=" + Report.two(Report.rdiv(100 * sum, 8)) +
                       " prematurity=" + Report.two(Report.rdiv(80000 * b.rr, sum)) +
                       "% compensation=" + compensation + " width_ms=" + b.width + " ref=" + ref(b));
        }
        List<String> runs = runs(beats), events = events(beats, params);
        output.add("RUNS count=" + runs.size());
        output.addAll(runs);
        output.add("EVENTS count=" + events.size());
        output.addAll(events);
        output.add("TREND segment_ms=" + params.get("segment_ms") + " segments=" + segments.size());
        for (Segment s : segments) {
            String prefix = segmentRange(s) + " beats=" + s.beats;
            if (s.rr.isEmpty())
                output.add(prefix + " mean_hr=none min_hr=none max_hr=none |");
            else {
                long h = Hrv.heartRate(s.rr), minimum = Collections.min(s.rr),
                     maximum = Collections.max(s.rr);
                output.add(prefix + " mean_hr=" + Report.two(h) +
                           " min_hr=" + Report.two(Report.rdiv(6000000, maximum)) +
                           " max_hr=" + Report.two(Report.rdiv(6000000, minimum)) + " |"
                           + "#".repeat((int)Report.rdiv(h, 500)));
            }
        }
        SignalIo.write("hrv.txt", output);
    }
    static int scale(long value, long top, long bottom, int rows) {
        return top == bottom ? 0 : (int)Report.rdiv((top - value) * (rows - 1), top - bottom);
    }
    static List<String> waveform(long[] upper, long[] lower, int rows) {
        long top = Long.MIN_VALUE, bottom = Long.MAX_VALUE;
        for (long v : upper)
            top = Math.max(top, v);
        for (long v : lower)
            bottom = Math.min(bottom, v);
        int zero = bottom <= 0 && top >= 0 ? scale(0, top, bottom, rows) : -1;
        List<String> output = new ArrayList<>();
        for (int row = 0; row < rows; row++) {
            String label = row == 0          ? Long.toString(top)
                           : row == rows - 1 ? Long.toString(bottom)
                           : row == zero     ? "0"
                                             : "";
            StringBuilder line = new StringBuilder(Report.pad(label, 6) + " |");
            for (int i = 0; i < upper.length; i++)
                line.append(scale(upper[i], top, bottom, rows) <= row &&
                                    row <= scale(lower[i], top, bottom, rows)
                                ? '#'
                            : row == zero ? '-'
                                          : ' ');
            output.add(line + "|");
        }
        return output;
    }
    static String axis(int columns, int period, int offset) {
        StringBuilder line = new StringBuilder("       +");
        for (int i = 0; i < columns; i++)
            line.append((i + offset) % period == 0 ? '+' : '-');
        return line + "+";
    }
    static String labelRow(String heading, SortedMap<Integer, String> labels) {
        StringBuilder line = new StringBuilder(Report.pad(heading, 6) + "  ");
        for (var e : labels.entrySet()) {
            while (line.length() < 8 + e.getKey())
                line.append(' ');
            line.append(e.getValue());
        }
        return line.toString();
    }
    static void charts(List<Beat> beats, long[] x, Map<String, Integer> params) throws IOException {
        List<String> output = new ArrayList<>();
        List<Long> rr = new ArrayList<>();
        for (Beat b : beats)
            if (b.number > 1)
                rr.add(b.rr);
        int rows = params.get("chart_rows");
        if (rr.isEmpty())
            output.addAll(List.of("TACHOGRAM intervals=0", "POINCARE points=0"));
        else {
            long lo = Collections.min(rr), hi = Collections.max(rr);
            output.add("TACHOGRAM intervals=" + rr.size() + " min_ms=" + lo + " max_ms=" + hi +
                       " rows=" + rows);
            for (int r = 0; r < rows; r++) {
                StringBuilder line = new StringBuilder(Report.pad(r == 0          ? Long.toString(hi)
                                                                  : r == rows - 1 ? Long.toString(lo)
                                                                                  : "",
                                                                  6) +
                                                       " |");
                for (long value : rr)
                    line.append(scale(value, hi, lo, rows) == r ? '*' : ' ');
                output.add(line + "|");
            }
            output.add(axis(rr.size(), 10, 2));
            SortedMap<Integer, String> labels = new TreeMap<>();
            for (int j = 0; j < rr.size(); j++)
                if ((j + 2) % 10 == 0)
                    labels.put(j, Integer.toString(j + 2));
            output.add(labelRow("beat", labels));
            StringBuilder line = new StringBuilder(" label |");
            for (int i = 1; i < beats.size(); i++)
                line.append(beats.get(i).label);
            output.add(line + "|");
            int size = params.get("poincare_size");
            int[][] cells = new int[size][size];
            for (int j = 0; j + 1 < rr.size(); j++) {
                int col = hi == lo ? 0 : (int)Report.rdiv((rr.get(j) - lo) * (size - 1), hi - lo),
                    row = scale(rr.get(j + 1), hi, lo, size);
                cells[row][col]++;
            }
            output.add("POINCARE points=" + (rr.size() - 1) + " size=" + size + " min_ms=" + lo +
                       " max_ms=" + hi);
            for (int r = 0; r < size; r++) {
                line = new StringBuilder(Report.pad(r == 0          ? Long.toString(hi)
                                                    : r == size - 1 ? Long.toString(lo)
                                                                    : "",
                                                    6) +
                                         " |");
                for (int c : cells[r])
                    line.append(c == 0 ? '.' : c < 10 ? (char)('0' + c) : '#');
                output.add(line + "|");
            }
            output.add("       +"
                       + "-".repeat(size) + "+");
            String low = Long.toString(lo), high = Long.toString(hi);
            output.add("        " + low + " ".repeat(size - low.length() - high.length()) + high);
        }
        for (String label : LABELS) {
            List<Beat> chosen = new ArrayList<>();
            for (Beat b : beats)
                if (b.label.equals(label) && b.sample >= 60 && b.sample <= x.length - 100)
                    chosen.add(b);
            if (chosen.isEmpty()) {
                output.add("TEMPLATE " + label + " beats=0");
                continue;
            }
            long[] template = new long[160];
            for (Beat b : chosen) {
                long baseline = 0;
                for (int j = -60; j < -50; j++)
                    baseline += x[b.sample + j];
                for (int j = -60; j < 100; j++)
                    template[j + 60] += 10 * x[b.sample + j] - baseline;
            }
            int max = 0, min = 0;
            for (int j = 0; j < 160; j++) {
                template[j] = Report.rdiv(template[j], 10L * chosen.size());
                if (template[j] > template[max])
                    max = j;
                if (template[j] < template[min])
                    min = j;
            }
            output.add("TEMPLATE " + label + " beats=" + chosen.size() + " max_uv=" + template[max] +
                       " max_ms=" + (5 * (max - 60)) + " min_uv=" + template[min] +
                       " min_ms=" + (5 * (min - 60)) + " rows=" + rows);
            long[] upper = new long[80], lower = new long[80];
            for (int i = 0; i < 80; i++) {
                upper[i] = Math.max(template[2 * i], template[2 * i + 1]);
                lower[i] = Math.min(template[2 * i], template[2 * i + 1]);
            }
            output.addAll(waveform(upper, lower, rows));
            output.add(axis(80, 10, 0));
            SortedMap<Integer, String> labels = new TreeMap<>();
            for (int i = 0; i < 80; i += 10)
                labels.put(i, Integer.toString(10 * i - 300));
            output.add(labelRow("ms", labels));
        }
        SignalIo.write("charts.txt", output);
    }
    static void rhythm(List<Beat> beats, List<SignalIo.Annotation> refs, long[] x, Map<String, Integer> p)
        throws IOException {
        int start = p.get("strip_start_ms") / 5, length = p.get("strip_ms") / 5, columns = length / 10,
            rows = p.get("strip_rows");
        long[] upper = new long[columns], lower = new long[columns];
        Arrays.fill(upper, Long.MIN_VALUE);
        Arrays.fill(lower, Long.MAX_VALUE);
        long top = Long.MIN_VALUE, bottom = Long.MAX_VALUE;
        for (int i = 0; i < length; i++) {
            long v = x[start + i];
            int c = i / 10;
            upper[c] = Math.max(upper[c], v);
            lower[c] = Math.min(lower[c], v);
            top = Math.max(top, v);
            bottom = Math.min(bottom, v);
        }
        List<String> output =
            new ArrayList<>(List.of("RHYTHM start_ms=" + p.get("strip_start_ms") + " end_ms=" +
                                    (p.get("strip_start_ms") + p.get("strip_ms")) + " columns=" + columns +
                                    " rows=" + rows + " max_uv=" + top + " min_uv=" + bottom));
        output.addAll(waveform(upper, lower, rows));
        output.add(axis(columns, 20, 0));
        SortedMap<Integer, String> labels = new TreeMap<>();
        for (int i = 0; i < columns; i += 20)
            labels.put(i, Integer.toString((p.get("strip_start_ms") + 50 * i) / 1000));
        output.add(labelRow("s", labels));
        char[] detected = new char[columns], reference = new char[columns];
        Arrays.fill(detected, ' ');
        Arrays.fill(reference, ' ');
        for (Beat b : beats)
            if (b.sample >= start && b.sample < start + length)
                detected[(b.sample - start) / 10] = b.label.charAt(0);
        for (SignalIo.Annotation r : refs)
            if (r.sample >= start && r.sample < start + length)
                reference[(r.sample - start) / 10] = r.label.charAt(0);
        output.add(" beats |" + new String(detected) + "|");
        output.add("  refs |" + new String(reference) + "|");
        SignalIo.write("rhythm_strip.txt", output);
    }
    public static void main(String[] args) throws IOException {
        long[] x = SignalIo.ecg();
        List<SignalIo.Annotation> refs = SignalIo.annotations();
        Map<String, Integer> p = SignalIo.parameters();
        Filters.Signals f = Filters.apply(x);
        List<Detector.Peak> peaks = Detector.peaks(f);
        Detection d = new Detection(peaks, f, p);
        d.run(x.length);
        List<Beat> beats = beats(d, f, p);
        match(beats, refs, p.get("match_ms") / 5);
        List<Segment> segments = segments(beats, refs, peaks, x.length, p.get("segment_ms") / 5);
        lists(beats, refs, peaks, x, f, p);
        performance(d, beats, refs, segments, x.length, p);
        hrv(beats, segments, p);
        charts(beats, x, p);
        rhythm(beats, refs, x, p);
    }
}
