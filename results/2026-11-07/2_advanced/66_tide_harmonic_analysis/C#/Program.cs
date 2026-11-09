using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static List<Predict.Extremum>
    GetDateGroup(SortedDictionary<DateOnly, List<Predict.Extremum>> groups, DateOnly date) {
        if (!groups.TryGetValue(date, out var group)) {
            group = new();
            groups[date] = group;
        }
        return group;
    }
    public static string F(double? value, int places) { return Report.F(value.Value, places); }
    public static Records.Settings settings;
    public static List<Records.Constituent> constituents;
    public static readonly List<Result> results = new();
    public record Selection(List<Records.Constituent> selected, string[] status) {}
    public record Error(double amplitude, double phase, double snr) {}
    public record Day(DateOnly date, int highs, int lows, double? hhw, double? llw, double? range) {
    }
    public record Event(int first, int last, int peak, bool positive) {}
    public record DailyMean(DateOnly date, double level, int filled) {}
    public record MeanStats(double average, double slope, DailyMean maximum, DailyMean minimum) {}
    public record Validation(int split, int train, int test, int constituents, double rms,
                             double inSample, double skill) {}
    public sealed class Tides {
        public double form, spring, neap, mhhw, mhw, mlw, mllw, mtl, dtl, mn, gt, hat, lat, rise,
            fall, ratio, relative, above, below;
        public string type, dominance;
        public Predict.Extremum highest, lowest;
        public Day widest, narrowest;
    }
    public sealed class Result {
        public Records.Station station;
        public Cleaning.Record clean;
        public Selection selection;
        public HarmonicFit.Model model;
        public double[] residuals = new double[10001], hourly;
        public double ss, s2, rms, maxAbs, explained, lag1;
        public int dof, raw;
        public List<Error> errors = new();
        public List<Predict.Extremum> extrema;
        public List<Day> days = new();
        public List<Event> events = new();
        public List<DailyMean> means = new();
        public MeanStats meanStats;
        public Validation validation;
        public Tides tides;
    }
    public static int Integer(string name, int i) { return settings.Integer(name, i); }
    public static double Real(string name, int i) { return settings.Real(name, i); }
    public static string F(double value, int places) { return Report.F(value, places); }
    public static string Hour(int t) { return Records.Hour(settings, t); }
    public static string Minute(int m) { return Records.Minute(settings, m); }
    public static double Height(Result r, double t) { return Predict.Height(r.model, t); }
    public static Selection Select(int length) {
        List<Records.Constituent> selected = new();
        string[] status = new string[constituents.Count];
        for (int i = 0; i < constituents.Count; i++) {
            Records.Constituent c = constituents[i];
            if (c.speed * length < 360 * Real("rayleigh", 0)) {
                status[i] = "short";
                continue;
            }
            string conflict = null;
            foreach (Records.Constituent chosen in selected)
                if (Math.Abs(c.speed - chosen.speed) * length < 360 * Real("rayleigh", 0)) {
                    conflict = chosen.name;
                    break;
                }
            if (conflict != null)
                status[i] = "conflict:" + conflict;
            else {
                status[i] = "fitted";
                selected.Add(c);
            }
        }
        return new Selection(selected, status);
    }
    public static int Index(Result r, string name) {
        for (int k = 0; k < r.model.selected.Count; k++)
            if (r.model.selected[k].name.Equals(name))
                return k;
        throw new IllegalStateException();
    }
    public static HarmonicFit.Constant Constant(Result r, string name) {
        return r.model.constants[Index(r, name)];
    }
    public static void Analyze(Records.Station station) {
        Result r = new Result();
        r.station = station;
        r.clean = Cleaning.Prepare(station, Integer("flat_run", 0));
        Cleaning.Record c = r.clean;
        r.selection = Select(c.last - c.first);
        HarmonicFit.Model prefit = HarmonicFit.Fit(c.values, c.candidates, r.selection.selected);
        double[] preliminary = new double[10001];
        double preSs = 0;
        foreach (int t in c.candidates) {
            preliminary[t] = c.values[t] - Predict.Height(prefit, t);
            preSs += preliminary[t] * preliminary[t];
        }
        c.prefitRms = Math.Sqrt(preSs / c.candidates.Count);
        Cleaning.Spikes(c, preliminary, settings);
        r.model = HarmonicFit.Fit(c.values, c.times, r.selection.selected);
        int p = r.model.coefficients.Length, n = c.times.Count;
        r.dof = n - p;
        double mean = 0;
        foreach (int t in c.times) {
            mean += c.values[t];
            double residual = c.values[t] - Height(r, t);
            r.residuals[t] = residual;
            r.ss += residual * residual;
            r.maxAbs = Math.Max(r.maxAbs, Math.Abs(residual));
        }
        mean /= n;
        double variance = 0, lagProduct = 0, lagSquares = 0;
        foreach (int t in c.times) {
            double v = c.values[t] - mean;
            variance += v * v;
            if (t < 10000 && c.usable[t + 1]) {
                lagProduct += r.residuals[t] * r.residuals[t + 1];
                lagSquares += r.residuals[t] * r.residuals[t];
            }
        }
        r.s2 = r.ss / r.dof;
        r.rms = Math.Sqrt(r.ss / n);
        r.explained = 100 * (1 - r.ss / variance);
        r.lag1 = lagProduct / lagSquares;
        for (int k = 0; k < r.model.constants.Count; k++) {
            HarmonicFit.Constant item = r.model.constants[k];
            int ia = 2 * k + 1, ib = 2 * k + 2;
            double a = item.a, b = item.b, amp = item.amplitude,
                   va = r.s2 * r.model.inverse[ia][ia], vb = r.s2 * r.model.inverse[ib][ib],
                   cab = r.s2 * r.model.inverse[ia][ib];
            double ea = Math.Sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amp,
                   ep = Math.Sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amp * amp) * 180 /
                        HarmonicFit.PI,
                   ratio = amp / ea;
            r.errors.Add(new Error(ea, ep, ratio * ratio));
        }
        Prediction(r);
        Validate(r);
        Events(r);
        DailyMeans(r);
        r.tides = ComputeTides(r);
        results.Add(r);
    }
    public static void Prediction(Result r) {
        int count = Integer("predict", 2);
        r.hourly = Predict.Hours(r.model, settings.ts, count);
        r.extrema = Predict.Extrema(r.model, settings.ts, count, Integer("grid_minutes", 0));
        r.raw = r.extrema.Count;
        while (r.extrema.Count >= 2) {
            int chosen = 0;
            double difference = Math.Abs(r.extrema[0].height - r.extrema[1].height);
            for (int i = 1; i < r.extrema.Count - 1; i++) {
                double d = Math.Abs(r.extrema[i].height - r.extrema[i + 1].height);
                if (d < difference) {
                    difference = d;
                    chosen = i;
                }
            }
            if (difference >= Real("min_range", 0))
                break;
            r.extrema.RemoveAt(chosen + 1);
            r.extrema.RemoveAt(chosen);
        }
        SortedDictionary<DateOnly, List<Predict.Extremum>> byDate = new();
        foreach (Predict.Extremum e in r.extrema) {
            e.rounded = (int)Math.Floor(e.minute + 0.5);
            DateOnly date = Records.DateMinute(settings, e.rounded);
            GetDateGroup(byDate, date).Add(e);
        }
        foreach (List<Predict.Extremum> group in byDate.Values) {
            Predict.Extremum high = null, low = null;
            foreach (Predict.Extremum e in group)
                if (e.high) {
                    if (high == null || e.height > high.height)
                        high = e;
                } else if (low == null || e.height < low.height)
                    low = e;
            foreach (Predict.Extremum e in group)
                e.label = e.high ? (e == high ? "HHW" : "LHW") : (e == low ? "LLW" : "HLW");
        }
        for (int d = 0; d < count / 24; d++) {
            DateOnly date = Records.DateOf(settings.start).AddDays(d);
            List<Predict.Extremum> group =
                byDate.GetValueOrDefault(date, new List<Predict.Extremum>());
            int highs = 0, lows = 0;
            double? high = null, low = null;
            foreach (Predict.Extremum e in group)
                if (e.high) {
                    highs++;
                    if (high == null || e.height > high)
                        high = e.height;
                } else {
                    lows++;
                    if (low == null || e.height < low)
                        low = e.height;
                }
            r.days.Add(new Day(date, highs, lows, high, low,
                               high == null || low == null ? null : high - low));
        }
    }
    public static void Validate(Result r) {
        Cleaning.Record c = r.clean;
        int split = c.first + (c.last - c.first) / 2;
        List<int> train = new(), test = new();
        foreach (int t in c.times)
            (t <= split ? train : test).Add(t);
        Selection selection = Select(train[^1] - train[0]);
        HarmonicFit.Model model = HarmonicFit.Fit(c.values, train, selection.selected);
        double mean = 0;
        foreach (int t in test)
            mean += c.values[t];
        mean /= test.Count;
        double errors = 0, inSample = 0, variance = 0;
        foreach (int t in test) {
            double error = c.values[t] - Predict.Height(model, t), difference = c.values[t] - mean;
            errors += error * error;
            inSample += r.residuals[t] * r.residuals[t];
            variance += difference * difference;
        }
        r.validation = new Validation(split, train.Count, test.Count, selection.selected.Count,
                                      Math.Sqrt(errors / test.Count),
                                      Math.Sqrt(inSample / test.Count), 1 - errors / variance);
    }
    public static int EventSign(Result r, int t) {
        return !r.clean.usable[t]                   ? 0
               : r.residuals[t] > Real("surge", 0)  ? 1
               : r.residuals[t] < -Real("surge", 0) ? -1
                                                    : 0;
    }
    public static void Events(Result r) {
        int t = r.clean.first;
        while (t <= r.clean.last) {
            int sign = EventSign(r, t);
            if (sign == 0) {
                t++;
                continue;
            }
            int first = t, peak = t;
            while (t + 1 <= r.clean.last && EventSign(r, t + 1) == sign) {
                t++;
                if (sign * r.residuals[t] > sign * r.residuals[peak])
                    peak = t;
            }
            if (t - first + 1 >= Integer("surge", 1))
                r.events.Add(new Event(first, t, peak, sign > 0));
            t++;
        }
    }
    public static void DailyMeans(Result r) {
        int[] weights = { 0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1 };
        DateOnly first = Records.DateHour(settings, r.clean.first),
                 last = Records.DateHour(settings, r.clean.last);
        for (DateOnly date = first; date <= last; date = date.AddDays(1)) {
            int noon = Records.Noon(settings, date);
            if (noon - 19 < r.clean.first || noon + 19 > r.clean.last)
                continue;
            double sum = 0;
            int filled = 0;
            for (int j = -19; j <= 19; j++) {
                int t = noon + j;
                double value;
                if (r.clean.usable[t])
                    value = r.clean.values[t];
                else {
                    value = Height(r, t);
                    filled++;
                }
                sum += weights[Math.Abs(j)] * value;
            }
            r.means.Add(new DailyMean(date, sum / 30, filled));
        }
        double xm = 0, vm = 0;
        DailyMean maximum = r.means[0], minimum = maximum;
        DateOnly origin = maximum.date;
        foreach (DailyMean day in r.means) {
            xm += Records.Days(origin, day.date);
            vm += day.level;
            if (day.level > maximum.level)
                maximum = day;
            if (day.level < minimum.level)
                minimum = day;
        }
        xm /= r.means.Count;
        vm /= r.means.Count;
        double numerator = 0, denominator = 0;
        foreach (DailyMean day in r.means) {
            double x = Records.Days(origin, day.date) - xm, v = day.level - vm;
            numerator += x * v;
            denominator += x * x;
        }
        r.meanStats = new MeanStats(vm, 1000 * (numerator / denominator), maximum, minimum);
    }
    public static Tides ComputeTides(Result r) {
        Tides t = new Tides();
        double m2 = Constant(r, "M2").amplitude, s2 = Constant(r, "S2").amplitude,
               k1 = Constant(r, "K1").amplitude, o1 = Constant(r, "O1").amplitude;
        t.form = (k1 + o1) / (m2 + s2);
        t.type = t.form < 0.25  ? "semidiurnal"
                 : t.form < 1.5 ? "mixed_semidiurnal"
                 : t.form < 3   ? "mixed_diurnal"
                                : "diurnal";
        t.spring = 2 * (m2 + s2);
        t.neap = 2 * (m2 - s2);
        int nh = 0, nl = 0, nhh = 0, nll = 0;
        foreach (Predict.Extremum e in r.extrema)
            if (e.high) {
                t.mhw += e.height;
                nh++;
                if (t.highest == null || e.height > t.highest.height)
                    t.highest = e;
            } else {
                t.mlw += e.height;
                nl++;
                if (t.lowest == null || e.height < t.lowest.height)
                    t.lowest = e;
            }
        foreach (Day day in r.days) {
            if (day.hhw != null) {
                t.mhhw += day.hhw.Value;
                nhh++;
            }
            if (day.llw != null) {
                t.mllw += day.llw.Value;
                nll++;
            }
            if (day.range != null) {
                if (t.widest == null || day.range > t.widest.range)
                    t.widest = day;
                if (t.narrowest == null || day.range < t.narrowest.range)
                    t.narrowest = day;
            }
        }
        t.mhw /= nh;
        t.mlw /= nl;
        t.mhhw /= nhh;
        t.mllw /= nll;
        t.mtl = (t.mhw + t.mlw) / 2;
        t.dtl = (t.mhhw + t.mllw) / 2;
        t.mn = t.mhw - t.mlw;
        t.gt = t.mhhw - t.mllw;
        double amplitudes = 0;
        foreach (HarmonicFit.Constant c in r.model.constants)
            amplitudes += c.amplitude;
        t.hat = r.model.coefficients[0] + amplitudes;
        t.lat = r.model.coefficients[0] - amplitudes;
        int rise = 0, fall = 0;
        for (int i = 1; i < r.extrema.Count; i++) {
            Predict.Extremum a = r.extrema[i - 1], b = r.extrema[i];
            if (!a.high && b.high) {
                t.rise += b.rounded - a.rounded;
                rise++;
            }
            if (a.high && !b.high) {
                t.fall += b.rounded - a.rounded;
                fall++;
            }
        }
        t.rise /= rise;
        t.fall /= fall;
        t.ratio = Constant(r, "M4").amplitude / m2;
        t.relative = 2 * Constant(r, "M2").phase - Constant(r, "M4").phase;
        while (t.relative < 0)
            t.relative += 360;
        while (t.relative >= 360)
            t.relative -= 360;
        t.dominance = t.relative < 180 ? "flood" : "ebb";
        int above = 0, below = 0;
        foreach (double value in r.hourly) {
            if (value > t.mhhw)
                above++;
            if (value < t.mllw)
                below++;
        }
        t.above = 100.0 * above / r.hourly.Length;
        t.below = 100.0 * below / r.hourly.Length;
        return t;
    }
    public static List<string> CleaningLines() {
        List<string> lines = new();
        foreach (Result r in results) {
            Cleaning.Record c = r.clean;
            Dictionary<string, int> counts = new();
            for (int t = c.first; t <= c.last; t++)
                if (c.reasons[t] != null)
                    counts[c.reasons[t]] = counts.GetValueOrDefault(c.reasons[t]) + 1;
            lines.Add("station=" + r.station.code + " name=" + r.station.name);
            lines.Add("span start=" + Hour(c.first) + " end=" + Hour(c.last) +
                      " hours=" + (c.last - c.first + 1) + " record_length=" + (c.last - c.first));
            lines.Add("counts rows=" + r.station.rows + " numeric=" + c.numeric +
                      " na=" + counts.GetValueOrDefault("na", 0) +
                      " absent=" + counts.GetValueOrDefault("absent", 0) +
                      " flat=" + counts.GetValueOrDefault("flat", 0) + " spikes=" +
                      counts.GetValueOrDefault("spike", 0) + " usable=" + c.times.Count);
            foreach (Cleaning.Run run in c.runs)
                lines.Add("flat start=" + Hour(run.first) + " end=" + Hour(run.last) +
                          " value=" + F(run.value, 3) + " removed=" + (run.last - run.first));
            lines.Add("spike_test window=" + Integer("spike", 0) +
                      " candidates=" + c.candidates.Count + " tested=" + c.tested +
                      " prefit_rms=" + F(c.prefitRms, 4));
            foreach (Cleaning.Spike spike in c.spikes)
                lines.Add("spike time=" + Hour(spike.time) + " value=" + F(spike.value, 3) +
                          " residual=" + F(spike.residual, 4) + " median=" + F(spike.median, 4) +
                          " mad=" + F(spike.mad, 4) + " limit=" + F(spike.limit, 4));
            foreach (Cleaning.Gap gap in c.gaps)
                lines.Add("gap start=" + Hour(gap.first) + " end=" + Hour(gap.last) +
                          " hours=" + (gap.last - gap.first + 1) + " cause=" + gap.cause);
        }
        return lines;
    }
    public static List<string> ConstituentLines() {
        List<string> lines = new();
        lines.Add(
            "station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant");
        foreach (Result r in results) {
            int k = 0;
            for (int i = 0; i < constituents.Count; i++) {
                Records.Constituent c = constituents[i];
                string status = r.selection.status[i],
                       line = r.station.code + "," + c.name + "," + F(c.speed, 7) + "," + status;
                if (!status.Equals("fitted"))
                    line += ",,,,,,";
                else {
                    HarmonicFit.Constant v = r.model.constants[k];
                    Error e = r.errors[k++];
                    line += "," + F(v.amplitude, 4) + "," + F(v.phase, 2) + "," +
                            F(e.amplitude, 4) + "," + F(e.phase, 2) + "," + F(e.snr, 1) + "," +
                            (e.snr >= Real("snr_min", 0) ? "yes" : "no");
                }
                lines.Add(line);
            }
        }
        return lines;
    }
    public static List<string> PredictionLines() {
        List<string> lines = new();
        string header = "time";
        foreach (Result r in results)
            header += "," + r.station.code;
        lines.Add(header);
        for (int i = 0; i <= Integer("predict", 2); i++) {
            string line = Hour(settings.ts + i);
            foreach (Result r in results)
                line += "," + F(r.hourly[i], 3);
            lines.Add(line);
        }
        return lines;
    }
    public static List<string> ExtremeLines() {
        List<string> lines = new();
        foreach (Result r in results) {
            lines.Add("station=" + r.station.code + " extremes=" + r.extrema.Count +
                      " raw=" + r.raw + " removed=" + (r.raw - r.extrema.Count));
            Predict.Extremum previous = null;
            foreach (Predict.Extremum e in r.extrema) {
                lines.Add(Minute(e.rounded) + " " + e.label + " " + F(e.height, 3) + " change=" +
                          (previous == null ? "none" : F(e.height - previous.height, 3)));
                previous = e;
            }
            foreach (Day day in r.days)
                lines.Add("day date=" + Records.DateText(day.date) + " high_waters=" + day.highs +
                          " low_waters=" + day.lows + " hhw=" + Report.Optional(day.hhw, 3) +
                          " llw=" + Report.Optional(day.llw, 3) +
                          " range=" + Report.Optional(day.range, 3));
        }
        return lines;
    }
    public static List<string> StationSummary(Result r) {
        Cleaning.Record c = r.clean;
        Tides t = r.tides;
        List<string> lines = new();
        lines.Add("[station " + r.station.code + "] " + r.station.name);
        lines.Add("record first=" + Hour(c.first) + " last=" + Hour(c.last) +
                  " length=" + (c.last - c.first) + " usable=" + c.times.Count);
        lines.Add("fit constituents=" + r.model.selected.Count +
                  " unknowns=" + r.model.coefficients.Length + " dof=" + r.dof +
                  " mean_level=" + F(r.model.coefficients[0], 4));
        lines.Add("residual rms=" + F(r.rms, 4) + " max_abs=" + F(r.maxAbs, 4) +
                  " explained_percent=" + F(r.explained, 4) +
                  " lag1_autocorrelation=" + F(r.lag1, 4));
        List<int> top = new(c.times);
        top.Sort((a, b) => {
            int order = (Math.Abs(r.residuals[b])).CompareTo(Math.Abs(r.residuals[a]));
            return order != 0 ? order : (a).CompareTo(b);
        });
        for (int i = 0; i < Integer("top_residuals", 0); i++) {
            int time = top[i];
            lines.Add("top_residual rank=" + (i + 1) + " time=" + Hour(time) +
                      " observed=" + F(c.values[time], 3) + " fitted=" + F(Height(r, time), 4) +
                      " residual=" + F(r.residuals[time], 4));
        }
        Validation v = r.validation;
        lines.Add("validation split=" + Hour(v.split) + " train=" + v.train + " test=" + v.test +
                  " constituents=" + v.constituents + " rms=" + F(v.rms, 4) +
                  " in_sample_rms=" + F(v.inSample, 4) + " skill=" + F(v.skill, 4));
        lines.Add("form_number=" + F(t.form, 4) + " type=" + t.type);
        lines.Add("ranges spring=" + F(t.spring, 3) + " neap=" + F(t.neap, 3) +
                  " mn=" + F(t.mn, 3) + " gt=" + F(t.gt, 3));
        lines.Add("asymmetry rise_minutes=" + F(t.rise, 1) + " fall_minutes=" + F(t.fall, 1) +
                  " m4_m2_ratio=" + F(t.ratio, 4) + " relative_phase=" + F(t.relative, 2) +
                  " dominance=" + t.dominance);
        lines.Add("datums mhhw=" + F(t.mhhw, 3) + " mhw=" + F(t.mhw, 3) + " mtl=" + F(t.mtl, 3) +
                  " dtl=" + F(t.dtl, 3) + " mlw=" + F(t.mlw, 3) + " mllw=" + F(t.mllw, 3));
        lines.Add("bounds hat=" + F(t.hat, 3) + " lat=" + F(t.lat, 3));
        int nh = 0, nl = 0;
        foreach (Predict.Extremum e in r.extrema)
            if (e.high)
                nh++;
            else
                nl++;
        lines.Add("window high_waters=" + nh + " low_waters=" + nl + " highest=" +
                  F(t.highest.height, 3) + " highest_time=" + Minute(t.highest.rounded) +
                  " lowest=" + F(t.lowest.height, 3) + " lowest_time=" + Minute(t.lowest.rounded));
        lines.Add("daily_range widest=" + F(t.widest.range, 3) + " widest_date=" +
                  Records.DateText(t.widest.date) + " narrowest=" + F(t.narrowest.range, 3) +
                  " narrowest_date=" + Records.DateText(t.narrowest.date));
        lines.Add("exceedance above_mhhw=" + F(t.above, 2) + " below_mllw=" + F(t.below, 2));
        double dw = r.model.selected[Index(r, "S2")].speed - r.model.selected[Index(r, "M2")].speed,
               dg = Constant(r, "S2").phase - Constant(r, "M2").phase;
        double q0 = (settings.ts * dw - dg) / 180,
               q1 = ((settings.ts + Integer("predict", 2)) * dw - dg) / 180;
        int first = (int)Math.Floor(Math.Min(q0, q1)) - 1,
            last = (int)Math.Ceiling(Math.Max(q0, q1)) + 1;
        for (int q = first; q <= last; q++) {
            double time = (dg + 180 * q) / dw;
            if (time >= settings.ts && time <= settings.ts + Integer("predict", 2))
                lines.Add((q % 2 == 0 ? "spring" : "neap") +
                          " time=" + Minute((int)Math.Floor(time * 60 + 0.5)));
        }
        lines.Add("surges count=" + r.events.Count + " threshold=" + F(Real("surge", 0), 3) +
                  " min_hours=" + Integer("surge", 1));
        foreach (Event eventInfo in r.events)
            lines.Add("surge type=" + (eventInfo.positive ? "positive" : "negative") +
                      " start=" + Hour(eventInfo.first) + " end=" + Hour(eventInfo.last) +
                      " hours=" + (eventInfo.last - eventInfo.first + 1) + " peak=" +
                      F(r.residuals[eventInfo.peak], 4) + " peak_time=" + Hour(eventInfo.peak));
        MeanStats m = r.meanStats;
        lines.Add("daily_mean days=" + r.means.Count + " average=" + F(m.average, 4) +
                  " slope_mm_per_day=" + F(m.slope, 3) + " max=" + F(m.maximum.level, 4) +
                  " max_date=" + Records.DateText(m.maximum.date) + " min=" +
                  F(m.minimum.level, 4) + " min_date=" + Records.DateText(m.minimum.date));
        foreach (DailyMean day in r.means)
            lines.Add("daily_mean date=" + Records.DateText(day.date) +
                      " level=" + F(day.level, 4) + " filled=" + day.filled);
        return lines;
    }
    public static double Lag(Result station, Result reference, bool high) {
        double sum = 0;
        int count = 0;
        foreach (Predict.Extremum e in station.extrema)
            if (e.high == high) {
                int distance = int.MaxValue, chosen = 0;
                foreach (Predict.Extremum other in reference.extrema)
                    if (other.high == high) {
                        int d = Math.Abs(e.rounded - other.rounded);
                        if (d < distance || d == distance && other.rounded < chosen) {
                            distance = d;
                            chosen = other.rounded;
                        }
                    }
                sum += e.rounded - chosen;
                count++;
            }
        return sum / count;
    }
    public record Correlation(double value, int count) {}
    public static Correlation ComputeCorrelation(Result a, Result b, int lag) {
        double mx = 0, my = 0;
        int count = 0;
        foreach (int t in a.clean.times) {
            int u = t + lag;
            if (u >= 0 && u <= 10000 && b.clean.usable[u]) {
                mx += a.residuals[t];
                my += b.residuals[u];
                count++;
            }
        }
        mx /= count;
        my /= count;
        double sxy = 0, sxx = 0, syy = 0;
        foreach (int t in a.clean.times) {
            int u = t + lag;
            if (u >= 0 && u <= 10000 && b.clean.usable[u]) {
                double x = a.residuals[t] - mx, y = b.residuals[u] - my;
                sxy += x * y;
                sxx += x * x;
                syy += y * y;
            }
        }
        return new Correlation(sxy / Math.Sqrt(sxx * syy), count);
    }
    public static List<string> Plot(Result r) {
        int width = Integer("plot", 1), top = Integer("plot", 2), bottom = Integer("plot", 3),
            step = Integer("plot", 4), rows = (top - bottom) / step + 1;
        char[][] cells = new char [rows][width];
        foreach (char[] row in cells)
            Array.Fill(row, ' ');
        int zero = (int)Math.Floor((top - 100 * r.model.coefficients[0]) / step + 0.5);
        if (zero >= 0 && zero < rows)
            Array.Fill(cells[zero], '-');
        char[] marks = new char[width];
        foreach (Predict.Extremum e in r.extrema) {
            int column = (e.rounded - 60 * settings.ts + 30) / 60;
            if (column >= 0 && column < width)
                marks[column] = e.high ? 'H' : 'L';
        }
        for (int column = 0; column < width; column++) {
            int row = (int)Math.Floor((top - 100 * r.hourly[column]) / step + 0.5);
            if (row < 0)
                cells[0][column] = '^';
            else if (row >= rows)
                cells[rows - 1][column] = 'v';
            else
                cells[row][column] = marks[column] == 0 ? '*' : marks[column];
        }
        string[] labels = new string[rows];
        for (int row = 0; row < rows; row++)
            labels[row] = F((top - row * step) / 100.0, 2);
        return Report.Plot(cells, labels);
    }
    public static List<string> Summary() {
        List<string> lines = new();
        Result reference = null, plotted = null;
        foreach (Result r in results) {
            lines.AddRange(StationSummary(r));
            if (r.station.code.Equals(settings.Text("reference", 0)))
                reference = r;
            if (r.station.code.Equals(settings.Text("plot", 0)))
                plotted = r;
        }
        lines.Add("[comparison] reference=" + reference.station.code);
        foreach (Result r in results)
            if (r != reference) {
                lines.Add(r.station.code + " tide hw_lag_min=" + F(Lag(r, reference, true), 1) +
                          " lw_lag_min=" + F(Lag(r, reference, false), 1) +
                          " range_ratio=" + F(r.tides.gt / reference.tides.gt, 4) +
                          " mtl_diff=" + F(r.tides.mtl - reference.tides.mtl, 3));
                foreach (string name in new string[] { "M2", "S2", "K1", "O1" }) {
                    HarmonicFit.Constant own = Constant(r, name),
                                         referenceConstant = Constant(reference, name);
                    double difference = own.phase - referenceConstant.phase;
                    if (difference > 180)
                        difference -= 360;
                    if (difference <= -180)
                        difference += 360;
                    double timeLag = difference / r.model.selected[Index(r, name)].speed * 60;
                    lines.Add(r.station.code + " " + name + " amplitude_ratio=" +
                              F(own.amplitude / referenceConstant.amplitude, 4) +
                              " phase_diff=" + F(difference, 2) + " time_lag_min=" + F(timeLag, 1));
                }
            }
        int limit = Integer("correlation_lag", 0);
        lines.Add("[correlation] max_lag=" + limit);
        for (int i = 0; i < results.Count; i++)
            for (int j = i + 1; j < results.Count; j++) {
                Result a = results[i], b = results[j];
                Correlation best = null, zero = null;
                int bestLag = 0;
                for (int lag = -limit; lag <= limit; lag++) {
                    Correlation value = ComputeCorrelation(a, b, lag);
                    if (lag == 0)
                        zero = value;
                    if (best == null || value.value > best.value ||
                        value.value == best.value &&
                            (Math.Abs(lag) < Math.Abs(bestLag) ||
                             Math.Abs(lag) == Math.Abs(bestLag) && lag < bestLag)) {
                        best = value;
                        bestLag = lag;
                    }
                }
                lines.Add(a.station.code + "-" + b.station.code + " lag0=" + F(zero.value, 4) +
                          " best_lag=" + bestLag + " best=" + F(best.value, 4) +
                          " pairs=" + best.count);
            }
        lines.Add("[plot] station=" + plotted.station.code + " start=" + Hour(settings.ts) +
                  " hours=" + Integer("plot", 1) + " step_cm=" + Integer("plot", 4));
        lines.AddRange(Plot(plotted));
        return lines;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Records.Data data = Records.Read();
        settings = data.settings;
        constituents = data.constituents;
        foreach (Records.Station station in data.stations)
            Analyze(station);
        Report.Write("cleaning.txt", CleaningLines());
        Report.Write("constituents.csv", ConstituentLines());
        Report.Write("predictions.csv", PredictionLines());
        Report.Write("extremes.txt", ExtremeLines());
        Report.Write("summary.txt", Summary());
    }
}
