import java.time.*;
import java.time.temporal.*;
import java.util.*;
public final class Main {
    static Records.Settings settings;
    static List<Records.Constituent> constituents;
    static final List<Result> results = new ArrayList<>();
    record Selection(List<Records.Constituent> selected, String[] status) {}
    record Error(double amplitude, double phase, double snr) {}
    record Day(LocalDate date, int highs, int lows, Double hhw, Double llw, Double range) {}
    record Event(int first, int last, int peak, boolean positive) {}
    record DailyMean(LocalDate date, double level, int filled) {}
    record MeanStats(double average, double slope, DailyMean maximum, DailyMean minimum) {}
    record Validation(int split, int train, int test, int constituents, double rms, double inSample,
                      double skill) {}
    static final class Tides {
        double form, spring, neap, mhhw, mhw, mlw, mllw, mtl, dtl, mn, gt, hat, lat, rise, fall,
            ratio, relative, above, below;
        String type, dominance;
        Predict.Extremum highest, lowest;
        Day widest, narrowest;
    }
    static final class Result {
        Records.Station station;
        Cleaning.Record clean;
        Selection selection;
        HarmonicFit.Model model;
        double[] residuals = new double[10001], hourly;
        double ss, s2, rms, maxAbs, explained, lag1;
        int dof, raw;
        List<Error> errors = new ArrayList<>();
        List<Predict.Extremum> extrema;
        List<Day> days = new ArrayList<>();
        List<Event> events = new ArrayList<>();
        List<DailyMean> means = new ArrayList<>();
        MeanStats meanStats;
        Validation validation;
        Tides tides;
    }
    static int integer(String name, int i) { return settings.integer(name, i); }
    static double real(String name, int i) { return settings.real(name, i); }
    static String f(double value, int places) { return Report.f(value, places); }
    static String hour(int t) { return Records.hour(settings, t); }
    static String minute(int m) { return Records.minute(settings, m); }
    static double height(Result r, double t) { return Predict.height(r.model, t); }
    static Selection select(int length) {
        List<Records.Constituent> selected = new ArrayList<>();
        String[] status = new String[constituents.size()];
        for (int i = 0; i < constituents.size(); i++) {
            Records.Constituent c = constituents.get(i);
            if (c.speed() * length < 360 * real("rayleigh", 0)) {
                status[i] = "short";
                continue;
            }
            String conflict = null;
            for (Records.Constituent chosen : selected)
                if (Math.abs(c.speed() - chosen.speed()) * length < 360 * real("rayleigh", 0)) {
                    conflict = chosen.name();
                    break;
                }
            if (conflict != null)
                status[i] = "conflict:" + conflict;
            else {
                status[i] = "fitted";
                selected.add(c);
            }
        }
        return new Selection(selected, status);
    }
    static int index(Result r, String name) {
        for (int k = 0; k < r.model.selected().size(); k++)
            if (r.model.selected().get(k).name().equals(name))
                return k;
        throw new IllegalStateException();
    }
    static HarmonicFit.Constant constant(Result r, String name) {
        return r.model.constants().get(index(r, name));
    }
    static void analyze(Records.Station station) {
        Result r = new Result();
        r.station = station;
        r.clean = Cleaning.prepare(station, integer("flat_run", 0));
        Cleaning.Record c = r.clean;
        r.selection = select(c.last - c.first);
        HarmonicFit.Model prefit = HarmonicFit.fit(c.values, c.candidates, r.selection.selected());
        double[] preliminary = new double[10001];
        double preSs = 0;
        for (int t : c.candidates) {
            preliminary[t] = c.values[t] - Predict.height(prefit, t);
            preSs += preliminary[t] * preliminary[t];
        }
        c.prefitRms = Math.sqrt(preSs / c.candidates.size());
        Cleaning.spikes(c, preliminary, settings);
        r.model = HarmonicFit.fit(c.values, c.times, r.selection.selected());
        int p = r.model.coefficients().length, n = c.times.size();
        r.dof = n - p;
        double mean = 0;
        for (int t : c.times) {
            mean += c.values[t];
            double residual = c.values[t] - height(r, t);
            r.residuals[t] = residual;
            r.ss += residual * residual;
            r.maxAbs = Math.max(r.maxAbs, Math.abs(residual));
        }
        mean /= n;
        double variance = 0, lagProduct = 0, lagSquares = 0;
        for (int t : c.times) {
            double v = c.values[t] - mean;
            variance += v * v;
            if (t < 10000 && c.usable[t + 1]) {
                lagProduct += r.residuals[t] * r.residuals[t + 1];
                lagSquares += r.residuals[t] * r.residuals[t];
            }
        }
        r.s2 = r.ss / r.dof;
        r.rms = Math.sqrt(r.ss / n);
        r.explained = 100 * (1 - r.ss / variance);
        r.lag1 = lagProduct / lagSquares;
        for (int k = 0; k < r.model.constants().size(); k++) {
            HarmonicFit.Constant item = r.model.constants().get(k);
            int ia = 2 * k + 1, ib = 2 * k + 2;
            double a = item.a(), b = item.b(), amp = item.amplitude(),
                   va = r.s2 * r.model.inverse()[ia][ia], vb = r.s2 * r.model.inverse()[ib][ib],
                   cab = r.s2 * r.model.inverse()[ia][ib];
            double ea = Math.sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amp,
                   ep = Math.sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amp * amp) * 180 /
                        HarmonicFit.PI,
                   ratio = amp / ea;
            r.errors.add(new Error(ea, ep, ratio * ratio));
        }
        prediction(r);
        validation(r);
        events(r);
        dailyMeans(r);
        r.tides = tides(r);
        results.add(r);
    }
    static void prediction(Result r) {
        int count = integer("predict", 2);
        r.hourly = Predict.hours(r.model, settings.ts, count);
        r.extrema = Predict.extrema(r.model, settings.ts, count, integer("grid_minutes", 0));
        r.raw = r.extrema.size();
        while (r.extrema.size() >= 2) {
            int chosen = 0;
            double difference = Math.abs(r.extrema.get(0).height - r.extrema.get(1).height);
            for (int i = 1; i < r.extrema.size() - 1; i++) {
                double d = Math.abs(r.extrema.get(i).height - r.extrema.get(i + 1).height);
                if (d < difference) {
                    difference = d;
                    chosen = i;
                }
            }
            if (difference >= real("min_range", 0))
                break;
            r.extrema.remove(chosen + 1);
            r.extrema.remove(chosen);
        }
        TreeMap<LocalDate, List<Predict.Extremum>> byDate = new TreeMap<>();
        for (Predict.Extremum e : r.extrema) {
            e.rounded = (int)Math.floor(e.minute + 0.5);
            LocalDate date = Records.dateMinute(settings, e.rounded);
            byDate.computeIfAbsent(date, key -> new ArrayList<>()).add(e);
        }
        for (List<Predict.Extremum> group : byDate.values()) {
            Predict.Extremum high = null, low = null;
            for (Predict.Extremum e : group)
                if (e.high) {
                    if (high == null || e.height > high.height)
                        high = e;
                } else if (low == null || e.height < low.height)
                    low = e;
            for (Predict.Extremum e : group)
                e.label = e.high ? (e == high ? "HHW" : "LHW") : (e == low ? "LLW" : "HLW");
        }
        for (int d = 0; d < count / 24; d++) {
            LocalDate date = settings.start.toLocalDate().plusDays(d);
            List<Predict.Extremum> group = byDate.getOrDefault(date, List.of());
            int highs = 0, lows = 0;
            Double high = null, low = null;
            for (Predict.Extremum e : group)
                if (e.high) {
                    highs++;
                    if (high == null || e.height > high)
                        high = e.height;
                } else {
                    lows++;
                    if (low == null || e.height < low)
                        low = e.height;
                }
            r.days.add(new Day(date, highs, lows, high, low,
                               high == null || low == null ? null : high - low));
        }
    }
    static void validation(Result r) {
        Cleaning.Record c = r.clean;
        int split = c.first + (c.last - c.first) / 2;
        List<Integer> train = new ArrayList<>(), test = new ArrayList<>();
        for (int t : c.times)
            (t <= split ? train : test).add(t);
        Selection selection = select(train.getLast() - train.getFirst());
        HarmonicFit.Model model = HarmonicFit.fit(c.values, train, selection.selected());
        double mean = 0;
        for (int t : test)
            mean += c.values[t];
        mean /= test.size();
        double errors = 0, inSample = 0, variance = 0;
        for (int t : test) {
            double error = c.values[t] - Predict.height(model, t), difference = c.values[t] - mean;
            errors += error * error;
            inSample += r.residuals[t] * r.residuals[t];
            variance += difference * difference;
        }
        r.validation = new Validation(split, train.size(), test.size(), selection.selected().size(),
                                      Math.sqrt(errors / test.size()),
                                      Math.sqrt(inSample / test.size()), 1 - errors / variance);
    }
    static int eventSign(Result r, int t) {
        return !r.clean.usable[t]            ? 0
        : r.residuals[t] > real("surge", 0)  ? 1
        : r.residuals[t] < -real("surge", 0) ? -1
                                             : 0;
    }
    static void events(Result r) {
        int t = r.clean.first;
        while (t <= r.clean.last) {
            int sign = eventSign(r, t);
            if (sign == 0) {
                t++;
                continue;
            }
            int first = t, peak = t;
            while (t + 1 <= r.clean.last && eventSign(r, t + 1) == sign) {
                t++;
                if (sign * r.residuals[t] > sign * r.residuals[peak])
                    peak = t;
            }
            if (t - first + 1 >= integer("surge", 1))
                r.events.add(new Event(first, t, peak, sign > 0));
            t++;
        }
    }
    static void dailyMeans(Result r) {
        int[] weights = {0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1};
        LocalDate first = Records.dateHour(settings, r.clean.first),
                  last = Records.dateHour(settings, r.clean.last);
        for (LocalDate date = first; !date.isAfter(last); date = date.plusDays(1)) {
            int noon = Records.noon(settings, date);
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
                    value = height(r, t);
                    filled++;
                }
                sum += weights[Math.abs(j)] * value;
            }
            r.means.add(new DailyMean(date, sum / 30, filled));
        }
        double xm = 0, vm = 0;
        DailyMean maximum = r.means.getFirst(), minimum = maximum;
        LocalDate origin = maximum.date();
        for (DailyMean day : r.means) {
            xm += ChronoUnit.DAYS.between(origin, day.date());
            vm += day.level();
            if (day.level() > maximum.level())
                maximum = day;
            if (day.level() < minimum.level())
                minimum = day;
        }
        xm /= r.means.size();
        vm /= r.means.size();
        double numerator = 0, denominator = 0;
        for (DailyMean day : r.means) {
            double x = ChronoUnit.DAYS.between(origin, day.date()) - xm, v = day.level() - vm;
            numerator += x * v;
            denominator += x * x;
        }
        r.meanStats = new MeanStats(vm, 1000 * (numerator / denominator), maximum, minimum);
    }
    static Tides tides(Result r) {
        Tides t = new Tides();
        double m2 = constant(r, "M2").amplitude(), s2 = constant(r, "S2").amplitude(),
               k1 = constant(r, "K1").amplitude(), o1 = constant(r, "O1").amplitude();
        t.form = (k1 + o1) / (m2 + s2);
        t.type = t.form < 0.25  ? "semidiurnal"
                 : t.form < 1.5 ? "mixed_semidiurnal"
                 : t.form < 3   ? "mixed_diurnal"
                                : "diurnal";
        t.spring = 2 * (m2 + s2);
        t.neap = 2 * (m2 - s2);
        int nh = 0, nl = 0, nhh = 0, nll = 0;
        for (Predict.Extremum e : r.extrema)
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
        for (Day day : r.days) {
            if (day.hhw() != null) {
                t.mhhw += day.hhw();
                nhh++;
            }
            if (day.llw() != null) {
                t.mllw += day.llw();
                nll++;
            }
            if (day.range() != null) {
                if (t.widest == null || day.range() > t.widest.range())
                    t.widest = day;
                if (t.narrowest == null || day.range() < t.narrowest.range())
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
        for (HarmonicFit.Constant c : r.model.constants())
            amplitudes += c.amplitude();
        t.hat = r.model.coefficients()[0] + amplitudes;
        t.lat = r.model.coefficients()[0] - amplitudes;
        int rise = 0, fall = 0;
        for (int i = 1; i < r.extrema.size(); i++) {
            Predict.Extremum a = r.extrema.get(i - 1), b = r.extrema.get(i);
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
        t.ratio = constant(r, "M4").amplitude() / m2;
        t.relative = 2 * constant(r, "M2").phase() - constant(r, "M4").phase();
        while (t.relative < 0)
            t.relative += 360;
        while (t.relative >= 360)
            t.relative -= 360;
        t.dominance = t.relative < 180 ? "flood" : "ebb";
        int above = 0, below = 0;
        for (double value : r.hourly) {
            if (value > t.mhhw)
                above++;
            if (value < t.mllw)
                below++;
        }
        t.above = 100.0 * above / r.hourly.length;
        t.below = 100.0 * below / r.hourly.length;
        return t;
    }
    static List<String> cleaningLines() {
        List<String> lines = new ArrayList<>();
        for (Result r : results) {
            Cleaning.Record c = r.clean;
            Map<String, Integer> counts = new HashMap<>();
            for (int t = c.first; t <= c.last; t++)
                if (c.reasons[t] != null)
                    counts.merge(c.reasons[t], 1, Integer::sum);
            lines.add("station=" + r.station.code + " name=" + r.station.name);
            lines.add("span start=" + hour(c.first) + " end=" + hour(c.last) +
                      " hours=" + (c.last - c.first + 1) + " record_length=" + (c.last - c.first));
            lines.add("counts rows=" + r.station.rows + " numeric=" + c.numeric + " na=" +
                      counts.getOrDefault("na", 0) + " absent=" + counts.getOrDefault("absent", 0) +
                      " flat=" + counts.getOrDefault("flat", 0) +
                      " spikes=" + counts.getOrDefault("spike", 0) + " usable=" + c.times.size());
            for (Cleaning.Run run : c.runs)
                lines.add("flat start=" + hour(run.first()) + " end=" + hour(run.last()) +
                          " value=" + f(run.value(), 3) + " removed=" + (run.last() - run.first()));
            lines.add("spike_test window=" + integer("spike", 0) +
                      " candidates=" + c.candidates.size() + " tested=" + c.tested +
                      " prefit_rms=" + f(c.prefitRms, 4));
            for (Cleaning.Spike spike : c.spikes)
                lines.add("spike time=" + hour(spike.time()) + " value=" + f(spike.value(), 3) +
                          " residual=" + f(spike.residual(), 4) +
                          " median=" + f(spike.median(), 4) + " mad=" + f(spike.mad(), 4) +
                          " limit=" + f(spike.limit(), 4));
            for (Cleaning.Gap gap : c.gaps)
                lines.add("gap start=" + hour(gap.first()) + " end=" + hour(gap.last()) +
                          " hours=" + (gap.last() - gap.first() + 1) + " cause=" + gap.cause());
        }
        return lines;
    }
    static List<String> constituentLines() {
        List<String> lines = new ArrayList<>();
        lines.add(
            "station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant");
        for (Result r : results) {
            int k = 0;
            for (int i = 0; i < constituents.size(); i++) {
                Records.Constituent c = constituents.get(i);
                String status = r.selection.status()[i],
                       line =
                           r.station.code + "," + c.name() + "," + f(c.speed(), 7) + "," + status;
                if (!status.equals("fitted"))
                    line += ",,,,,,";
                else {
                    HarmonicFit.Constant v = r.model.constants().get(k);
                    Error e = r.errors.get(k++);
                    line += "," + f(v.amplitude(), 4) + "," + f(v.phase(), 2) + "," +
                            f(e.amplitude(), 4) + "," + f(e.phase(), 2) + "," + f(e.snr(), 1) +
                            "," + (e.snr() >= real("snr_min", 0) ? "yes" : "no");
                }
                lines.add(line);
            }
        }
        return lines;
    }
    static List<String> predictionLines() {
        List<String> lines = new ArrayList<>();
        String header = "time";
        for (Result r : results)
            header += "," + r.station.code;
        lines.add(header);
        for (int i = 0; i <= integer("predict", 2); i++) {
            String line = hour(settings.ts + i);
            for (Result r : results)
                line += "," + f(r.hourly[i], 3);
            lines.add(line);
        }
        return lines;
    }
    static List<String> extremeLines() {
        List<String> lines = new ArrayList<>();
        for (Result r : results) {
            lines.add("station=" + r.station.code + " extremes=" + r.extrema.size() +
                      " raw=" + r.raw + " removed=" + (r.raw - r.extrema.size()));
            Predict.Extremum previous = null;
            for (Predict.Extremum e : r.extrema) {
                lines.add(minute(e.rounded) + " " + e.label + " " + f(e.height, 3) + " change=" +
                          (previous == null ? "none" : f(e.height - previous.height, 3)));
                previous = e;
            }
            for (Day day : r.days)
                lines.add("day date=" + day.date() + " high_waters=" + day.highs() +
                          " low_waters=" + day.lows() + " hhw=" + Report.optional(day.hhw(), 3) +
                          " llw=" + Report.optional(day.llw(), 3) +
                          " range=" + Report.optional(day.range(), 3));
        }
        return lines;
    }
    static List<String> stationSummary(Result r) {
        Cleaning.Record c = r.clean;
        Tides t = r.tides;
        List<String> lines = new ArrayList<>();
        lines.add("[station " + r.station.code + "] " + r.station.name);
        lines.add("record first=" + hour(c.first) + " last=" + hour(c.last) +
                  " length=" + (c.last - c.first) + " usable=" + c.times.size());
        lines.add("fit constituents=" + r.model.selected().size() +
                  " unknowns=" + r.model.coefficients().length + " dof=" + r.dof +
                  " mean_level=" + f(r.model.coefficients()[0], 4));
        lines.add("residual rms=" + f(r.rms, 4) + " max_abs=" + f(r.maxAbs, 4) +
                  " explained_percent=" + f(r.explained, 4) +
                  " lag1_autocorrelation=" + f(r.lag1, 4));
        List<Integer> top = new ArrayList<>(c.times);
        top.sort((a, b) -> {
            int order = Double.compare(Math.abs(r.residuals[b]), Math.abs(r.residuals[a]));
            return order != 0 ? order : Integer.compare(a, b);
        });
        for (int i = 0; i < integer("top_residuals", 0); i++) {
            int time = top.get(i);
            lines.add("top_residual rank=" + (i + 1) + " time=" + hour(time) +
                      " observed=" + f(c.values[time], 3) + " fitted=" + f(height(r, time), 4) +
                      " residual=" + f(r.residuals[time], 4));
        }
        Validation v = r.validation;
        lines.add("validation split=" + hour(v.split()) + " train=" + v.train() + " test=" +
                  v.test() + " constituents=" + v.constituents() + " rms=" + f(v.rms(), 4) +
                  " in_sample_rms=" + f(v.inSample(), 4) + " skill=" + f(v.skill(), 4));
        lines.add("form_number=" + f(t.form, 4) + " type=" + t.type);
        lines.add("ranges spring=" + f(t.spring, 3) + " neap=" + f(t.neap, 3) +
                  " mn=" + f(t.mn, 3) + " gt=" + f(t.gt, 3));
        lines.add("asymmetry rise_minutes=" + f(t.rise, 1) + " fall_minutes=" + f(t.fall, 1) +
                  " m4_m2_ratio=" + f(t.ratio, 4) + " relative_phase=" + f(t.relative, 2) +
                  " dominance=" + t.dominance);
        lines.add("datums mhhw=" + f(t.mhhw, 3) + " mhw=" + f(t.mhw, 3) + " mtl=" + f(t.mtl, 3) +
                  " dtl=" + f(t.dtl, 3) + " mlw=" + f(t.mlw, 3) + " mllw=" + f(t.mllw, 3));
        lines.add("bounds hat=" + f(t.hat, 3) + " lat=" + f(t.lat, 3));
        int nh = 0, nl = 0;
        for (Predict.Extremum e : r.extrema)
            if (e.high)
                nh++;
            else
                nl++;
        lines.add("window high_waters=" + nh + " low_waters=" + nl + " highest=" +
                  f(t.highest.height, 3) + " highest_time=" + minute(t.highest.rounded) +
                  " lowest=" + f(t.lowest.height, 3) + " lowest_time=" + minute(t.lowest.rounded));
        lines.add("daily_range widest=" + f(t.widest.range(), 3) +
                  " widest_date=" + t.widest.date() + " narrowest=" + f(t.narrowest.range(), 3) +
                  " narrowest_date=" + t.narrowest.date());
        lines.add("exceedance above_mhhw=" + f(t.above, 2) + " below_mllw=" + f(t.below, 2));
        double dw = r.model.selected().get(index(r, "S2")).speed() -
                    r.model.selected().get(index(r, "M2")).speed(),
               dg = constant(r, "S2").phase() - constant(r, "M2").phase();
        double q0 = (settings.ts * dw - dg) / 180,
               q1 = ((settings.ts + integer("predict", 2)) * dw - dg) / 180;
        int first = (int)Math.floor(Math.min(q0, q1)) - 1, last =
                                                               (int)Math.ceil(Math.max(q0, q1)) + 1;
        for (int q = first; q <= last; q++) {
            double time = (dg + 180 * q) / dw;
            if (time >= settings.ts && time <= settings.ts + integer("predict", 2))
                lines.add((q % 2 == 0 ? "spring" : "neap") +
                          " time=" + minute((int)Math.floor(time * 60 + 0.5)));
        }
        lines.add("surges count=" + r.events.size() + " threshold=" + f(real("surge", 0), 3) +
                  " min_hours=" + integer("surge", 1));
        for (Event event : r.events)
            lines.add("surge type=" + (event.positive() ? "positive" : "negative") +
                      " start=" + hour(event.first()) + " end=" + hour(event.last()) +
                      " hours=" + (event.last() - event.first() + 1) + " peak=" +
                      f(r.residuals[event.peak()], 4) + " peak_time=" + hour(event.peak()));
        MeanStats m = r.meanStats;
        lines.add("daily_mean days=" + r.means.size() + " average=" + f(m.average(), 4) +
                  " slope_mm_per_day=" + f(m.slope(), 3) + " max=" + f(m.maximum().level(), 4) +
                  " max_date=" + m.maximum().date() + " min=" + f(m.minimum().level(), 4) +
                  " min_date=" + m.minimum().date());
        for (DailyMean day : r.means)
            lines.add("daily_mean date=" + day.date() + " level=" + f(day.level(), 4) +
                      " filled=" + day.filled());
        return lines;
    }
    static double lag(Result station, Result reference, boolean high) {
        double sum = 0;
        int count = 0;
        for (Predict.Extremum e : station.extrema)
            if (e.high == high) {
                int distance = Integer.MAX_VALUE, chosen = 0;
                for (Predict.Extremum other : reference.extrema)
                    if (other.high == high) {
                        int d = Math.abs(e.rounded - other.rounded);
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
    record Correlation(double value, int count) {}
    static Correlation correlation(Result a, Result b, int lag) {
        double mx = 0, my = 0;
        int count = 0;
        for (int t : a.clean.times) {
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
        for (int t : a.clean.times) {
            int u = t + lag;
            if (u >= 0 && u <= 10000 && b.clean.usable[u]) {
                double x = a.residuals[t] - mx, y = b.residuals[u] - my;
                sxy += x * y;
                sxx += x * x;
                syy += y * y;
            }
        }
        return new Correlation(sxy / Math.sqrt(sxx * syy), count);
    }
    static List<String> plot(Result r) {
        int width = integer("plot", 1), top = integer("plot", 2), bottom = integer("plot", 3),
            step = integer("plot", 4), rows = (top - bottom) / step + 1;
        char[][] cells = new char[rows][width];
        for (char[] row : cells)
            Arrays.fill(row, ' ');
        int zero = (int)Math.floor((top - 100 * r.model.coefficients()[0]) / step + 0.5);
        if (zero >= 0 && zero < rows)
            Arrays.fill(cells[zero], '-');
        char[] marks = new char[width];
        for (Predict.Extremum e : r.extrema) {
            int column = (e.rounded - 60 * settings.ts + 30) / 60;
            if (column >= 0 && column < width)
                marks[column] = e.high ? 'H' : 'L';
        }
        for (int column = 0; column < width; column++) {
            int row = (int)Math.floor((top - 100 * r.hourly[column]) / step + 0.5);
            if (row < 0)
                cells[0][column] = '^';
            else if (row >= rows)
                cells[rows - 1][column] = 'v';
            else
                cells[row][column] = marks[column] == 0 ? '*' : marks[column];
        }
        String[] labels = new String[rows];
        for (int row = 0; row < rows; row++)
            labels[row] = f((top - row * step) / 100.0, 2);
        return Report.plot(cells, labels);
    }
    static List<String> summary() {
        List<String> lines = new ArrayList<>();
        Result reference = null, plotted = null;
        for (Result r : results) {
            lines.addAll(stationSummary(r));
            if (r.station.code.equals(settings.text("reference", 0)))
                reference = r;
            if (r.station.code.equals(settings.text("plot", 0)))
                plotted = r;
        }
        lines.add("[comparison] reference=" + reference.station.code);
        for (Result r : results)
            if (r != reference) {
                lines.add(r.station.code + " tide hw_lag_min=" + f(lag(r, reference, true), 1) +
                          " lw_lag_min=" + f(lag(r, reference, false), 1) +
                          " range_ratio=" + f(r.tides.gt / reference.tides.gt, 4) +
                          " mtl_diff=" + f(r.tides.mtl - reference.tides.mtl, 3));
                for (String name : new String[] {"M2", "S2", "K1", "O1"}) {
                    HarmonicFit.Constant own = constant(r, name), ref = constant(reference, name);
                    double difference = own.phase() - ref.phase();
                    if (difference > 180)
                        difference -= 360;
                    if (difference <= -180)
                        difference += 360;
                    double timeLag =
                        difference / r.model.selected().get(index(r, name)).speed() * 60;
                    lines.add(r.station.code + " " + name +
                              " amplitude_ratio=" + f(own.amplitude() / ref.amplitude(), 4) +
                              " phase_diff=" + f(difference, 2) + " time_lag_min=" + f(timeLag, 1));
                }
            }
        int limit = integer("correlation_lag", 0);
        lines.add("[correlation] max_lag=" + limit);
        for (int i = 0; i < results.size(); i++)
            for (int j = i + 1; j < results.size(); j++) {
                Result a = results.get(i), b = results.get(j);
                Correlation best = null, zero = null;
                int bestLag = 0;
                for (int lag = -limit; lag <= limit; lag++) {
                    Correlation value = correlation(a, b, lag);
                    if (lag == 0)
                        zero = value;
                    if (best == null || value.value() > best.value() ||
                        value.value() == best.value() &&
                            (Math.abs(lag) < Math.abs(bestLag) ||
                             Math.abs(lag) == Math.abs(bestLag) && lag < bestLag)) {
                        best = value;
                        bestLag = lag;
                    }
                }
                lines.add(a.station.code + "-" + b.station.code + " lag0=" + f(zero.value(), 4) +
                          " best_lag=" + bestLag + " best=" + f(best.value(), 4) +
                          " pairs=" + best.count());
            }
        lines.add("[plot] station=" + plotted.station.code + " start=" + hour(settings.ts) +
                  " hours=" + integer("plot", 1) + " step_cm=" + integer("plot", 4));
        lines.addAll(plot(plotted));
        return lines;
    }
    public static void main(String[] args) throws Exception {
        Records.Data data = Records.read();
        settings = data.settings();
        constituents = data.constituents();
        for (Records.Station station : data.stations())
            analyze(station);
        Report.write("cleaning.txt", cleaningLines());
        Report.write("constituents.csv", constituentLines());
        Report.write("predictions.csv", predictionLines());
        Report.write("extremes.txt", extremeLines());
        Report.write("summary.txt", summary());
    }
}
