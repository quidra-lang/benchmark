using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static string Repeat(this string text, int count) => string.Concat(Enumerable.Repeat(text, count));
    public static WaveformIo.Params settings;
    public static List<WaveformIo.Station> stations;
    public static List<Picker.Pick> picks = new();
    public static List<Associator.Candidate> candidates;
    public static List<Event> events = new();
    public static List<List<Event>> clusters = new();
    public record Jack(WaveformIo.Station station, double dx, double dy, double dz, double shift) {
    }
    public sealed class Event {
        public int number, cluster;
        public List<Picker.Pick> used;
        public Locator.Run first, relocated;
        public List<Locator.Observation> observations;
        public Locator.Ellipse ellipse;
        public List<Jack> jack = new();
        public Jack maximum;
        public double startRms, gap, dmin, dh, dz, md;
        public double? ml, mlc;
        public string quality;
        public List<Magnitude.Values> magnitudes = new();
        public double[] Solution() {
            return relocated.solution;
        }
    }
    public static string Decimal(double value, int digits) {
        double result = Math.Round(value, digits, MidpointRounding.AwayFromZero);
        if (result == 0)
            result = 0;
        return result.ToString("F" + digits, CultureInfo.InvariantCulture);
    }
    public static string DisplayMagnitude(double? value) {
        return value == null ? "-" : Decimal(value.Value, 2);
    }
    public static string Time(int sample) {
        return sample / 100 + "." + (sample % 100).ToString("D2", CultureInfo.InvariantCulture);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static List<Picker.Pick> Ordered(List<Picker.Pick> input) {
        List<Picker.Pick> result = new(input);
        result.Sort(Comparer<Picker.Pick>.Create((a, b) => a.station.order.CompareTo(b.station.order)));
        return result;
    }
    public static List<Locator.Observation> Observations(List<Picker.Pick> input, bool corrected) {
        List<Locator.Observation> result = new();
        foreach (Picker.Pick pick in input)
            result.Add(new Locator.Observation(pick.station,
                                               pick.Time() - (corrected ? pick.station.correction : 0)));
        return result;
    }
    public static void Locate() {
        foreach (Associator.Candidate candidate in candidates) {
            candidate.picks = Ordered(candidate.picks);
            Locator.Run first = Locator.Locate(Observations(candidate.picks, false), settings);
            candidate.passes.Add(first);
            List<Picker.Pick> retained = new();
            for (int i = 0; i < candidate.picks.Count; i++) {
                Picker.Pick pick = candidate.picks[i];
                if (Math.Abs(first.residuals[i]) > settings.Get("residual_limit"))
                    candidate.dropped.Add(pick);
                else
                    retained.Add(pick);
            }
            if (candidate.dropped.Count != 0 && retained.Count < settings.Integer("min_stations")) {
                candidate.rejected = true;
                foreach (Picker.Pick pick in candidate.picks)
                    pick.state = "rejected";
                continue;
            }
            Locator.Run adopted = first;
            if (candidate.dropped.Count != 0) {
                adopted = Locator.Locate(Observations(retained, false), settings);
                candidate.passes.Add(adopted);
            }
            Event earthquake = new Event();
            earthquake.number = events.Count + 1;
            earthquake.used = retained;
            earthquake.first = adopted;
            candidate.earthquake = earthquake;
            for (int i = 0; i < retained.Count; i++) {
                Picker.Pick pick = retained[i];
                pick.state = "used";
                pick.earthquake = earthquake.number;
                pick.firstResidual = adopted.residuals[i];
            }
            foreach (Picker.Pick pick in candidate.dropped) {
                pick.state = "dropped";
                pick.earthquake = earthquake.number;
            }
            events.Add(earthquake);
        }
    }
    public static List<Picker.Pick> Used(WaveformIo.Station station) {
        List<Picker.Pick> result = new();
        foreach (Event earthquake in events)
            foreach (Picker.Pick pick in earthquake.used)
                if (pick.station == station)
                    result.Add(pick);
        return result;
    }
    public static void Relocate() {
        double velocity = settings.Get("velocity");
        foreach (WaveformIo.Station station in stations) {
            List<Picker.Pick> used = Used(station);
            double sum = 0;
            foreach (Picker.Pick pick in used)
                sum += pick.firstResidual;
            station.correction = used.Count == 0 ? 0 : sum / used.Count;
        }
        foreach (Event earthquake in events) {
            earthquake.observations = Observations(earthquake.used, true);
            earthquake.startRms = Locator.Rms(earthquake.first.solution, earthquake.observations, velocity);
            earthquake.relocated =
                Locator.Geiger(earthquake.first.solution, earthquake.observations, velocity);
            for (int i = 0; i < earthquake.used.Count; i++)
                earthquake.used[i].residual = earthquake.relocated.residuals[i];
            double[] solution = earthquake.Solution();
            earthquake.ellipse = Locator.EstimateEllipse(solution, earthquake.observations, velocity);
            List<Double> angles = new();
            earthquake.dmin = double.PositiveInfinity;
            foreach (Picker.Pick pick in earthquake.used) {
                WaveformIo.Station station = pick.station;
                double phi = Math.Atan2(station.x - solution[0], station.y - solution[1]) * 180 / Locator.PI;
                if (phi < 0)
                    phi += 360;
                angles.Add(phi);
                double distance =
                    Math.Sqrt(Locator.Sq(station.x - solution[0]) + Locator.Sq(station.y - solution[1]));
                earthquake.dmin = Math.Min(earthquake.dmin, distance);
            }
            angles.Sort();
            earthquake.gap = angles[0] + 360 - angles[^1];
            for (int i = 1; i < angles.Count; i++)
                earthquake.gap = Math.Max(earthquake.gap, angles[i] - angles[i - 1]);
            earthquake.quality = "C";
            foreach (string grade in new string[] { "A", "B" }) {
                double[] bound = settings.Row("quality_" + grade.ToLowerInvariant());
                if (earthquake.gap <= bound[0] && earthquake.relocated.rms <= bound[1] &&
                    earthquake.ellipse.smaj <= bound[2]) {
                    earthquake.quality = grade;
                    break;
                }
            }
            earthquake.dh = Math.Sqrt(Locator.Sq(solution[0] - earthquake.first.solution[0]) +
                                      Locator.Sq(solution[1] - earthquake.first.solution[1]));
            earthquake.dz = solution[2] - earthquake.first.solution[2];
            for (int i = 0; i < earthquake.used.Count; i++) {
                List<Locator.Observation> remaining = new(earthquake.observations);
                remaining.RemoveAt(i);
                double[] alternative = Locator.Geiger(solution, remaining, velocity).solution;
                double dx = alternative[0] - solution[0], dy = alternative[1] - solution[1],
                       dz = alternative[2] - solution[2], shift = Math.Sqrt(dx * dx + dy * dy);
                Jack jack = new Jack(earthquake.used[i].station, dx, dy, dz, shift);
                earthquake.jack.Add(jack);
                if (earthquake.maximum == null || shift > earthquake.maximum.shift)
                    earthquake.maximum = jack;
            }
        }
    }
    public static void Magnitudes() {
        Dictionary<WaveformIo.Station, List<Double>> residuals = new();
        foreach (WaveformIo.Station station in stations)
            residuals[station] = new();
        foreach (Event earthquake in events) {
            List<Double> local = new(), duration = new();
            foreach (Picker.Pick pick in earthquake.used) {
                Magnitude.Values values = Magnitude.PerPick(
                    pick, Locator.Distance(earthquake.Solution(), pick.station) / 1000, settings);
                earthquake.magnitudes.Add(values);
                duration.Add(values.md);
                if (values.ml != null)
                    local.Add(values.ml.Value);
            }
            earthquake.ml = local.Count == 0 ? null : Magnitude.Median(local);
            earthquake.md = Magnitude.Median(duration);
            for (int i = 0; i < earthquake.used.Count; i++) {
                Magnitude.Values values = earthquake.magnitudes[i];
                if (values.ml != null)
                    residuals[earthquake.used[i].station].Add(values.ml.Value - earthquake.ml.Value);
            }
        }
        foreach (WaveformIo.Station station in stations) {
            List<Double> values = residuals[station];
            double sum = 0;
            foreach (double value in values)
                sum += value;
            station.magnitudeCorrection = values.Count == 0 ? 0 : sum / values.Count;
        }
        foreach (Event earthquake in events) {
            List<Double> values = new();
            for (int i = 0; i < earthquake.used.Count; i++) {
                double? ml = earthquake.magnitudes[i].ml;
                if (ml != null)
                    values.Add(ml.Value - earthquake.used[i].station.magnitudeCorrection);
            }
            earthquake.mlc = values.Count == 0 ? null : Magnitude.Median(values);
        }
    }
    public static void Cluster() {
        double[] bounds = settings.Row("cluster");
        bool[] seen = new bool[events.Count];
        for (int i = 0; i < events.Count; i++) {
            if (seen[i])
                continue;
            List<Event> members = new();
            Queue<int> queue = new();
            queue.Enqueue(i);
            seen[i] = true;
            while (queue.Count != 0) {
                int current = queue.Dequeue();
                Event earthquake = events[current];
                members.Add(earthquake);
                for (int j = 0; j < events.Count; j++) {
                    if (seen[j])
                        continue;
                    double[] a = earthquake.Solution(), b = events[j].Solution();
                    double distance = Math.Sqrt(Locator.Sq(a[0] - b[0]) + Locator.Sq(a[1] - b[1]) +
                                                Locator.Sq(a[2] - b[2]));
                    if (Math.Abs(a[3] - b[3]) <= bounds[1] && distance <= bounds[0]) {
                        seen[j] = true;
                        queue.Enqueue(j);
                    }
                }
            }
            members.Sort(Comparer<Event>.Create((a, b) => a.number.CompareTo(b.number)));
            clusters.Add(members);
            foreach (Event earthquake in members)
                earthquake.cluster = clusters.Count;
        }
    }
    public static void Reassociate() {
        List<HashSet<int>> stationSets = new();
        foreach (Event earthquake in events) {
            HashSet<int> set = new();
            foreach (Picker.Pick pick in earthquake.used)
                set.Add(pick.station.order);
            stationSets.Add(set);
        }
        foreach (Picker.Pick pick in picks) {
            if (!pick.state.Equals("unassociated"))
                continue;
            Event best = null;
            double error = 0;
            foreach (Event earthquake in events) {
                if (stationSets[earthquake.number - 1].Contains(pick.station.order))
                    continue;
                double[] solution = earthquake.Solution();
                double residual = pick.Time() - solution[3] -
                                  Locator.Distance(solution, pick.station) / settings.Get("velocity") -
                                  pick.station.correction;
                if (Math.Abs(residual) <= settings.Get("residual_limit") &&
                    (best == null || Math.Abs(residual) < Math.Abs(error))) {
                    best = earthquake;
                    error = residual;
                }
            }
            if (best != null) {
                pick.state = "added";
                pick.earthquake = best.number;
                pick.residual = error;
                stationSets[best.number - 1].Add(pick.station.order);
            }
        }
    }
    public static List<string> PicksReport() {
        List<string> output =
            new(["station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"]);
        foreach (Picker.Pick pick in picks)
            output.Add(
                pick.station.code + "," + pick.sample + "," + Time(pick.sample) + "," + pick.duration + "," +
                Decimal(pick.ratio, 2) + "," + pick.amplitude + "," + (pick.clipped ? "yes" : "no") + "," +
                pick.earthquake + "," + pick.state + "," +
                (pick.state.Equals("used") || pick.state.Equals("added") ? Decimal(pick.residual, 4) : "-"));
        return output;
    }
    public static string SolutionLine(string label, double[] s, double rms) {
        return label + " x=" + Decimal(s[0], 1) + " y=" + Decimal(s[1], 1) + " z=" + Decimal(s[2], 1) +
               " t0=" + Decimal(s[3], 3) + " rms=" + Decimal(rms, 4);
    }
    public static string Codes(List<Picker.Pick> input) {
        List<string> codes = new();
        foreach (Picker.Pick pick in input)
            codes.Add(pick.station.code);
        return string.Join(",", codes);
    }
    public static void Iterations(List<string> output, Locator.Run run) {
        foreach (Locator.Iteration row in run.trace)
            output.Add(SolutionLine("ITER " + row.number, row.solution, row.rms));
    }
    public static void Pass(List<string> output, int number, List<Picker.Pick> input, Locator.Run run) {
        output.Add("PASS " + number + " stations=" + Codes(input));
        output.Add(SolutionLine("GRID", run.grid.solution, run.grid.rms));
        List<string> profile = new();
        foreach (double value in run.grid.profile)
            profile.Add(Decimal(value, 4));
        output.Add("PROFILE " + string.Join(" ", profile));
        Iterations(output, run);
        for (int i = 0; i < input.Count; i++) {
            Picker.Pick pick = input[i];
            double distance = Locator.Distance(run.solution, pick.station);
            output.Add("RES " + pick.station.code + " dist=" + Decimal(distance, 1) +
                       " tt=" + Decimal(distance / settings.Get("velocity"), 4) +
                       " obs=" + Time(pick.sample) + " res=" + Decimal(run.residuals[i], 4));
        }
    }
    public static List<string> LocationReport() {
        List<string> output = new();
        foreach (Associator.Candidate candidate in candidates) {
            output.Add("CANDIDATE " + candidate.number + " picks=" + candidate.picks.Count +
                       " first=" + Time(candidate.first.sample));
            Pass(output, 1, candidate.picks, candidate.passes[0]);
            foreach (Picker.Pick pick in candidate.dropped) {
                int i = candidate.picks.IndexOf(pick);
                output.Add("DROP " + pick.station.code +
                           " res=" + Decimal(candidate.passes[0].residuals[i], 4));
            }
            if (candidate.rejected)
                output.Add("RESULT REJECTED stations=" + (candidate.picks.Count - candidate.dropped.Count));
            else {
                if (candidate.passes.Count == 2)
                    Pass(output, 2, candidate.earthquake.used, candidate.passes[1]);
                output.Add("RESULT EVENT " + candidate.earthquake.number);
            }
        }
        output.Add("CORRECTIONS");
        foreach (WaveformIo.Station station in stations)
            output.Add(station.code + " n=" + Used(station).Count +
                       " correction=" + Decimal(station.correction, 4));
        foreach (Event earthquake in events) {
            output.Add("EVENT " + earthquake.number);
            output.Add(SolutionLine("START", earthquake.first.solution, earthquake.startRms));
            Iterations(output, earthquake.relocated);
            foreach (Picker.Pick pick in earthquake.used) {
                double distance = Locator.Distance(earthquake.Solution(), pick.station);
                output.Add("RES " + pick.station.code + " dist=" + Decimal(distance, 1) +
                           " tt=" + Decimal(distance / settings.Get("velocity"), 4) +
                           " obs=" + Time(pick.sample) + " corr=" + Decimal(pick.station.correction, 4) +
                           " res=" + Decimal(pick.residual, 4));
            }
            Locator.Ellipse e = earthquake.ellipse;
            output.Add("ELLIPSE smaj=" + Decimal(e.smaj, 1) + " smin=" + Decimal(e.smin, 1) +
                       " az=" + Decimal(e.az, 1) + " erz=" + Decimal(e.erz, 1) + " ert=" + Decimal(e.ert, 4));
            output.Add("SHIFT dh=" + Decimal(earthquake.dh, 1) + " dz=" + Decimal(earthquake.dz, 1));
            output.Add("GAP " + Decimal(earthquake.gap, 1) + " DMIN " + Decimal(earthquake.dmin, 1) +
                       " QUALITY " + earthquake.quality);
            foreach (Jack jack in earthquake.jack)
                output.Add("JACK " + jack.station.code + " dx=" + Decimal(jack.dx, 1) +
                           " dy=" + Decimal(jack.dy, 1) + " dz=" + Decimal(jack.dz, 1) +
                           " shift=" + Decimal(jack.shift, 1));
            output.Add("JACKKNIFE max=" + Decimal(earthquake.maximum.shift, 1) +
                       " station=" + earthquake.maximum.station.code);
        }
        List<double[]> points = new();
        double sd = 0, st = 0, sdd = 0, sdt = 0;
        foreach (Event earthquake in events)
            foreach (Picker.Pick pick in earthquake.used) {
                double d = Locator.Distance(earthquake.Solution(), pick.station) / 1000,
                       t = pick.Time() - earthquake.Solution()[3];
                points.Add(new double[] { d, t });
                sd += d;
                st += t;
                sdd += d * d;
                sdt += d * t;
            }
        int n = points.Count;
        double slope = (n * sdt - sd * st) / (n * sdd - sd * sd), intercept = (st - slope * sd) / n, sum = 0;
        foreach (double[] point in points)
            sum += Locator.Sq(point[1] - intercept - slope * point[0]);
        output.Add("FIT n=" + n + " velocity=" + Decimal(1000 / slope, 1) +
                   " intercept=" + Decimal(intercept, 4) + " rms=" + Decimal(Math.Sqrt(sum / n), 4));
        for (int c = 0; c < clusters.Count; c++) {
            List<Event> members = clusters[c];
            if (members.Count < 2)
                continue;
            double[] center = new double[3];
            double low = double.PositiveInfinity, high = double.NegativeInfinity;
            List<string> numbers = new();
            foreach (Event earthquake in members) {
                numbers.Add(Convert.ToString(earthquake.number));
                for (int a = 0; a < 3; a++)
                    center[a] += earthquake.Solution()[a];
                low = Math.Min(low, earthquake.Solution()[3]);
                high = Math.Max(high, earthquake.Solution()[3]);
            }
            output.Add("CLUSTER " + (c + 1) + " events=" + string.Join(",", numbers) + " x=" +
                       Decimal(center[0] / members.Count, 1) + " y=" + Decimal(center[1] / members.Count, 1) +
                       " z=" + Decimal(center[2] / members.Count, 1) + " span=" + Decimal(high - low, 3));
        }
        output.Add("ADDED");
        int unassociated = 0;
        foreach (Picker.Pick pick in picks) {
            if (pick.state.Equals("added"))
                output.Add(pick.station.code + " sample=" + pick.sample + " event=" + pick.earthquake +
                           " res=" + Decimal(pick.residual, 4));
            if (pick.state.Equals("unassociated"))
                unassociated++;
        }
        int rejected = 0;
        foreach (Associator.Candidate candidate in candidates)
            if (candidate.rejected)
                rejected++;
        output.Add("SUMMARY picks=" + picks.Count + " candidates=" + candidates.Count +
                   " events=" + events.Count + " rejected=" + rejected + " unassociated=" + unassociated);
        List<Double> depths = new();
        int[] qualities = new int[3];
        sum = 0;
        foreach (Event earthquake in events) {
            depths.Add(earthquake.Solution()[2]);
            qualities[earthquake.quality[0] - 'A']++;
            sum += earthquake.relocated.rms;
        }
        output.Add("DEPTH min=" + Decimal(depths.Min(), 1) +
                   " median=" + Decimal(Magnitude.Median(depths), 1) + " max=" + Decimal(depths.Max(), 1));
        output.Add("QUALITY A=" + qualities[0] + " B=" + qualities[1] + " C=" + qualities[2] +
                   " mean_rms=" + Decimal(sum / events.Count, 4));
        return output;
    }
    public static List<string> Catalog() {
        List<string> output = new([
            "event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"
        ]);
        foreach (Event earthquake in events) {
            double[] s = earthquake.Solution();
            Locator.Ellipse e = earthquake.ellipse;
            output.Add(earthquake.number + "," + Decimal(s[3], 3) + "," + Decimal(s[0], 1) + "," +
                       Decimal(s[1], 1) + "," + Decimal(s[2], 1) + "," +
                       Decimal(earthquake.relocated.rms, 4) + "," + earthquake.used.Count + "," +
                       Decimal(earthquake.gap, 1) + "," + Decimal(earthquake.dmin, 1) + "," +
                       Decimal(e.smaj, 1) + "," + Decimal(e.smin, 1) + "," + Decimal(e.az, 1) + "," +
                       Decimal(e.erz, 1) + "," + DisplayMagnitude(earthquake.ml) + "," +
                       Decimal(earthquake.md, 2) + "," + earthquake.quality + "," + earthquake.cluster);
        }
        return output;
    }
    public static List<string> StationReport() {
        List<string> output = new();
        foreach (WaveformIo.Station s in stations) {
            output.Add("STATION " + s.code + " x=" + s.x + " y=" + s.y + " elevation=" + s.elevation);
            output.Add("SAMPLES start=" + s.start + " count=" + s.samples.Length + " mean=" + s.mean +
                       " noise=" + Decimal(s.noise, 1) + " peak=" + s.peak + " clipped=" + s.clipped);
            output.Add("TRIGGERS total=" + s.triggers + " short=" + s.shortTriggers +
                       " picks=" + s.picks.Count);
            Dictionary<string, int> counts = new();
            foreach (Picker.Pick pick in s.picks)
                counts[pick.state] = counts.GetValueOrDefault(pick.state, 0) + 1;
            string line = "PICKS";
            foreach (string state in new string[] { "used", "dropped", "added", "rejected", "unassociated" })
                line += " " + state + "=" + counts.GetValueOrDefault(state, 0);
            output.Add(line);
            List<Picker.Pick> used = Used(s);
            double before = 0, after = 0;
            int nm = 0;
            foreach (Picker.Pick pick in used) {
                before += pick.firstResidual * pick.firstResidual;
                after += pick.residual * pick.residual;
                if (!pick.clipped)
                    nm++;
            }
            output.Add("RESIDUALS n=" + used.Count +
                       " rms=" + (used.Count == 0 ? "-" : Decimal(Math.Sqrt(before / used.Count), 4)) +
                       " correction=" + Decimal(s.correction, 4) +
                       " after=" + (used.Count == 0 ? "-" : Decimal(Math.Sqrt(after / used.Count), 4)));
            output.Add("MAGNITUDES n=" + nm + " correction=" + Decimal(s.magnitudeCorrection, 2));
        }
        return output;
    }

    public static char[][] Canvas(int width, int height) {
        char[][] result = Enumerable.Range(0, height)
                              .Select(
                                  _ => new char[width])
                              .ToArray();
        foreach (char[] row in result)
            Array.Fill(row, ' ');
        return result;
    }
    public static void Frame(List<string> output, char[][] grid) {
        string edge = "+" + "-".Repeat(grid[0].Length) + "+";
        output.Add(edge);
        foreach (char[] row in grid)
            output.Add("|" + new string(row) + "|");
        output.Add(edge);
    }
    public static List<string> MagnitudeReport() {
        List<string> output = new();
        List<Double> magnitudes = new();
        foreach (Event earthquake in events) {
            int count = 0;
            foreach (Magnitude.Values value in earthquake.magnitudes)
                if (value.ml != null)
                    count++;
            output.Add("EVENT " + earthquake.number + " ML=" + DisplayMagnitude(earthquake.ml) +
                       " n=" + count + " MD=" + Decimal(earthquake.md, 2));
            for (int i = 0; i < earthquake.used.Count; i++) {
                Picker.Pick pick = earthquake.used[i];
                Magnitude.Values value = earthquake.magnitudes[i];
                output.Add(pick.station.code + " r=" + Decimal(value.distance, 3) + " amp=" + pick.amplitude +
                           (pick.clipped ? " clipped"
                                         : " ml=" + Decimal(value.ml.Value, 2) +
                                               " res=" + Decimal(value.ml.Value - earthquake.ml.Value, 2)) +
                           " dur=" + pick.duration + " md=" + Decimal(value.md, 2));
            }
            if (earthquake.ml != null)
                magnitudes.Add(earthquake.ml.Value);
        }
        output.Add("CORRECTED");
        foreach (Event earthquake in events)
            output.Add("EVENT " + earthquake.number + " MLC=" + DisplayMagnitude(earthquake.mlc));
        Magnitude.Frequency frequency = Magnitude.ComputeFrequency(magnitudes);
        output.Add("FMD");
        for (int t = frequency.counts.Keys.First(); t <= frequency.counts.Keys.Last(); t++) {
            int cumulative = 0;
            foreach (int key in frequency.counts.Keys)
                if (key >= t)
                    cumulative += frequency.counts[key];
            output.Add("M=" + Magnitude.ClassText(t) + " N=" + frequency.counts.GetValueOrDefault(t, 0) +
                       " CUM=" + cumulative);
        }
        output.Add("MC " + Magnitude.ClassText(frequency.completeness));
        output.Add("BVALUE " + Decimal(frequency.b, 3) + " SIGMA " + Decimal(frequency.sigma, 3) + " N " +
                   frequency.nb);
        output.Add("AVALUE " + Decimal(frequency.a, 3));
        List<Double> x = new(), y = new();
        double sx = 0, sy = 0;
        foreach (Event earthquake in events)
            if (earthquake.ml != null) {
                x.Add(earthquake.md);
                y.Add(earthquake.ml.Value);
                sx += earthquake.md;
                sy += earthquake.ml.Value;
            }
        int n = x.Count;
        double xm = sx / n, ym = sy / n, xx = 0, xy = 0, yy = 0;
        for (int i = 0; i < n; i++) {
            xx += (x[i] - xm) * (x[i] - xm);
            xy += (x[i] - xm) * (y[i] - ym);
            yy += (y[i] - ym) * (y[i] - ym);
        }
        double slope = xy / xx;
        output.Add("MLMD n=" + n + " slope=" + Decimal(slope, 3) +
                   " intercept=" + Decimal(ym - slope * xm, 3) + " r=" + Decimal(xy / Math.Sqrt(xx * yy), 3) +
                   " mean_diff=" + Decimal(ym - xm, 3));
        double[] v = settings.Row("timeline");
        int duration = (int)v[0], width = (int)v[1], low = (int)v[2], high = (int)v[3], height = (int)v[4];
        char[][] grid = Canvas(width, height);
        foreach (Event earthquake in events) {
            if (earthquake.ml == null)
                continue;
            long t = Magnitude.Rounded(earthquake.Solution()[3], 3),
                 h = Magnitude.Rounded(earthquake.ml.Value, 2);
            if (t < 0 || t >= 1000L * duration || h < 100L * low)
                continue;
            int col = (int)(t * width / (1000L * duration)),
                level = (int)Math.Min((h - 100L * low) * height / (100L * (high - low)), height - 1);
            for (int k = 0; k <= level; k++) {
                int row = height - 1 - k;
                if (k == level)
                    grid[row][col] = 'o';
                else if (grid[row][col] == ' ')
                    grid[row][col] = '|';
            }
        }
        output.Add("TIMELINE t=0.." + duration + " ML=" + low + ".." + high);
        Frame(output, grid);
        return output;
    }
    public static int[] Position(long x, long y, long z, int chart) {
        double[] a = settings.Row("map_area"), size = settings.Row("map_size"),
                 section = settings.Row("section");
        long xmin = (long)a[0], xmax = (long)a[1], ymin = (long)a[2], ymax = (long)a[3];
        int width = (int)size[0], height = (int)size[1], sh = (int)section[1];
        long zmax = (long)section[0];
        if (chart == 0) {
            if (x < 10 * xmin || x >= 10 * xmax || y < 10 * ymin || y >= 10 * ymax)
                return null;
            return new int[] { (int)((x - 10 * xmin) * width / (10 * (xmax - xmin))),
                               height - 1 - (int)((y - 10 * ymin) * height / (10 * (ymax - ymin))) };
        }
        if (z >= 10 * zmax)
            return null;
        long value = chart == 1 ? x : y, lo = chart == 1 ? xmin : ymin, hi = chart == 1 ? xmax : ymax;
        if (value < 10 * lo || value >= 10 * hi)
            return null;
        return new int[] { (int)((value - 10 * lo) * width / (10 * (hi - lo))), (int)(z * sh / (10 * zmax)) };
    }
    public static string PositionText(int[] point) {
        return point == null ? "outside" : point[0] + "," + point[1];
    }
    public static char Symbol(Event earthquake) {
        if (earthquake.ml == null)
            return '?';
        long h = Magnitude.Rounded(earthquake.ml.Value, 2);
        return h < 100 ? '.' : h < 200 ? 'o' : h < 300 ? 'O' : '@';
    }
    public static void Place(char[][] grid, int[] point, char symbol) {
        if (point == null)
            return;
        string priority = " ?.oO@^";
        if (priority.IndexOf(symbol) > priority.IndexOf(grid[point[1]][point[0]]))
            grid[point[1]][point[0]] = symbol;
    }
    public static List<string> MapReport() {
        int width = (int)settings.Row("map_size")[0], height = (int)settings.Row("map_size")[1],
            sectionHeight = (int)settings.Row("section")[1];
        List<char[][]> charts =
            [Canvas(width, height), Canvas(width, sectionHeight), Canvas(width, sectionHeight)];
        List<int[][]> positions = new();
        foreach (Event earthquake in events) {
            long x = Magnitude.Rounded(earthquake.Solution()[0], 1),
                 y = Magnitude.Rounded(earthquake.Solution()[1], 1),
                 z = Magnitude.Rounded(earthquake.Solution()[2], 1);
            int[][] pos = new int [3][];
            for (int chart = 0; chart < 3; chart++) {
                pos[chart] = Position(x, y, z, chart);
                Place(charts[chart], pos[chart], Symbol(earthquake));
            }
            positions.Add(pos);
        }
        List<int[]> stationPositions = new();
        foreach (WaveformIo.Station station in stations) {
            int[] pos = Position(10L * station.x, 10L * station.y, 0, 0);
            stationPositions.Add(pos);
            Place(charts[0], pos, '^');
        }
        double[] a = settings.Row("map_area");
        long xmin = (long)a[0], xmax = (long)a[1], ymin = (long)a[2], ymax = (long)a[3],
             zmax = (long)settings.Row("section")[0];
        List<string> output = new();
        output.Add("MAP x=" + xmin + ".." + xmax + " y=" + ymin + ".." + ymax);
        Frame(output, charts[0]);
        output.Add("SECTION EW x=" + xmin + ".." + xmax + " z=0.." + zmax);
        Frame(output, charts[1]);
        output.Add("SECTION NS y=" + ymin + ".." + ymax + " z=0.." + zmax);
        Frame(output, charts[2]);
        output.Add("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML");
        for (int i = 0; i < stations.Count; i++)
            output.Add("STATION " + stations[i].code + " map=" + PositionText(stationPositions[i]));
        for (int i = 0; i < events.Count; i++) {
            Event earthquake = events[i];
            int[][] pos = positions[i];
            output.Add("EVENT " + earthquake.number + " " + Symbol(earthquake) + " map=" +
                       PositionText(pos[0]) + " ew=" + PositionText(pos[1]) + " ns=" + PositionText(pos[2]));
        }
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        WaveformIo.Data data = WaveformIo.Read();
        stations = data.stations;
        settings = data.settings;
        foreach (WaveformIo.Station station in stations)
            picks.AddRange(Picker.Detect(station, settings));
        picks.Sort(Comparer<Picker.Pick>.Create((a, b) => a.sample != b.sample
                                                              ? a.sample.CompareTo(b.sample)
                                                              : a.station.order.CompareTo(b.station.order)));
        candidates = Associator.Associate(picks, settings.Integer("association_window"),
                                          settings.Integer("min_stations"));
        Locate();
        Relocate();
        Magnitudes();
        Cluster();
        Reassociate();
        Write("picks.csv", PicksReport());
        Write("locations.txt", LocationReport());
        Write("catalog.csv", Catalog());
        Write("magnitudes.txt", MagnitudeReport());
        Write("stations.txt", StationReport());
        Write("map.txt", MapReport());
    }
}
