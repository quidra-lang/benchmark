using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly string[] FILTERS = { "cv", "ca", "abg", "imm", "rts" };
    public static readonly Dictionary<string, List<string>> settings = new();
    public static readonly List<List<double[]>> measurements = new();
    public static double[] times;
    public static int scans, primary, conflictMeasurements, conflictTracks, greedyDifferences;
    public static readonly List<Target> targets = new();
    public static readonly List<Track> tracks = new(), evaluated = new();
    public static readonly List<string> rows = new(), log = new();
    public static int[][][] labels;
    public static double[][] ospa;
    public static int[][] sizes;
    public static Evaluation.Continuity[][] continuity;
    public static Track[] matched;
    public static TargetResult[] results;
    public static double[] overallPosition, overallVelocity;
    public static class Target {
        public int number, first, last;
        public double[][] positions;
        public Target(int number) {
            this.number = number;
            first = scans + 1;
            positions = new double [scans + 1][];
        }
    }
    public static class Track {
        public int number, birth, lastHit, confirmed, deleted, hits = 1, misses, longest, target = -1;
        public string status = "tentative";
        public Kalman kalman;
        public double[][] observations;
        public double[] nis, high;
        public int[] primaryMatches;
        public double[][][] estimates, primaryCovariances;
        public double[] modelLogs = new double[2];
        public double path, meanDistance;
        public int commonFirst, commonLast;
        public Track(int number, int scan, double[] measurement, Kalman kalman) {
            this.number = number;
            birth = lastHit = scan;
            this.kalman = kalman;
            observations = new double [scans + 1][];
            observations[scan] = measurement;
            nis = new double[scans + 1];
            primaryMatches = new int[scans + 1];
        }
    }
    public record TargetResult(double[] position, double[] velocity, int velocityCount, double[] nees) {
    }
    public static string F(double value) {
        return Evaluation.Real(value);
    }
    public static string Optional(int value) {
        return value == 0 ? "-" : Convert.ToString(value);
    }
    public static double Parameter(string name) {
        return Real(name, 0);
    }
    public static double Real(string name, int i) {
        return double.Parse(settings[name][i]);
    }
    public static int Integer(string name, int i) {
        return int.Parse(settings[name][i]);
    }
    public static double[] Values(string name) {
        List<string> values = settings[name];
        double[] result = new double[values.Count];
        for (int i = 0; i < result.Length; i++)
            result[i] = double.Parse(values[i]);
        return result;
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name)).ToList();
    }
    public static void Read() {
        List<string> input = Lines("measurements.csv");
        scans = int.Parse(input[^1].Split(',')[0]);
        times = new double[scans + 1];
        for (int k = 0; k <= scans; k++)
            measurements.Add(new());
        for (int i = 1; i < input.Count; i++) {
            string[] w = input[i].Split(',');
            int k = int.Parse(w[0]);
            times[k] = double.Parse(w[1]);
            measurements[k].Add(new double[] { double.Parse(w[2]), double.Parse(w[3]) });
        }
        input = Lines("truth.csv");
        for (int i = 1; i < input.Count; i++) {
            string[] w = input[i].Split(',');
            int number = int.Parse(w[0]), scan = int.Parse(w[1]);
            if (targets.Count == 0 || targets[^1].number != number)
                targets.Add(new Target(number));
            Target t = targets[^1];
            t.first = Math.Min(t.first, scan);
            t.last = scan;
            t.positions[scan] = new double[] { double.Parse(w[2]), double.Parse(w[3]) };
        }
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            settings[w[0]] = w.Skip(1).ToList();
        }
        primary = settings["MODEL"][0].Equals("CV") ? 0 : 1;
    }
    public static Kalman MakeKalman(string model, double[] measurement) {
        return new Kalman(model, Parameter("Q_" + model), Parameter("SIGMA"),
                          Parameter("INIT_VELOCITY_VARIANCE"), Parameter("INIT_ACCELERATION_VARIANCE"),
                          measurement);
    }
    public static string Listed(string keyword, List<string> items) {
        return keyword + " " + (items.Count == 0 ? "none" : string.Join(" ", items));
    }
    public static string Pairs(string keyword, List<Association.Pair> pairs, List<Track> live) {
        List<string> items = new();
        foreach (Association.Pair pair in pairs)
            items.Add(live[pair.row].number + ":" + (pair.column + 1));
        return Listed(keyword, items);
    }
    public static void TrackAll() {
        rows.Add("track,scan,x,y,vx,vy,status");
        for (int scan = 1; scan <= scans; scan++) {
            List<Track> live = new();
            foreach (Track t in tracks)
                if (!t.status.Equals("deleted"))
                    live.Add(t);
            List<double[]> points = measurements[scan];
            if (scan > 1)
                foreach (Track t in live)
                    t.kalman.Predict(times[scan] - times[scan - 1]);
            int a = live.Count, b = points.Count;
            double[][] costs = Enumerable.Range(0, a)
                                   .Select(
                                       _ => new double[b])
                                   .ToArray();
            bool[][] usable = Enumerable.Range(0, a)
                                  .Select(
                                      _ => new bool[b])
                                  .ToArray();
            Kalman.Innovation[][] innovations = Enumerable.Range(0, a)
                                                    .Select(
                                                        _ => new Kalman.Innovation[b])
                                                    .ToArray();
            int[] rowGates = new int[a], columnGates = new int[b];
            List<Association.Pair> gated = new();
            List<string> gateLines = new();
            for (int i = 0; i < a; i++)
                for (int j = 0; j < b; j++) {
                    Kalman.Innovation v = live[i].kalman.ComputeInnovation(points[j]);
                    if (v.distance <= Parameter("GATE")) {
                        costs[i][j] = v.distance;
                        usable[i][j] = true;
                        innovations[i][j] = v;
                        rowGates[i]++;
                        columnGates[j]++;
                        gated.Add(new Association.Pair(i, j));
                        gateLines.Add(live[i].number + ":" + (j + 1) + "=" + F(v.distance));
                    }
                }
            List<Association.Pair> assigned = Association.Optimal(costs, usable);
            gated.Sort(Comparer<Association.Pair>.Create((first, second) => {
                int c = costs[first.row][first.column].CompareTo(costs[second.row][second.column]);
                return c != 0                    ? c
                       : first.row != second.row ? first.row.CompareTo(second.row)
                                                 : first.column.CompareTo(second.column);
            }));
            List<Association.Pair> greedy = new();
            bool[] usedRows = new bool[a], usedColumns = new bool[b];
            foreach (Association.Pair p in gated)
                if (!usedRows[p.row] && !usedColumns[p.column]) {
                    greedy.Add(p);
                    usedRows[p.row] = true;
                    usedColumns[p.column] = true;
                }
            greedy.Sort(Comparer<Association.Pair>.Create(
                (first, second) => first.row != second.row ? first.row.CompareTo(second.row)
                                                           : first.column.CompareTo(second.column)));
            if (!assigned.SequenceEqual(greedy))
                greedyDifferences++;
            int[] matches = new int[a];
            Array.Fill(matches, -1);
            Array.Fill(usedColumns, false);
            foreach (Association.Pair p in assigned) {
                matches[p.row] = p.column;
                usedColumns[p.column] = true;
            }
            List<string> missed = new(), confirmed = new(), deleted = new(), created = new();
            List<Track> processed = new(live);
            for (int i = 0; i < a; i++) {
                Track t = live[i];
                int j = matches[i];
                if (j >= 0) {
                    t.kalman.Update(points[j], innovations[i][j]);
                    t.observations[scan] = points[j];
                    t.nis[scan] = costs[i][j];
                    t.lastHit = scan;
                    t.hits++;
                    t.misses = 0;
                } else {
                    t.misses++;
                    missed.Add(Convert.ToString(t.number));
                }
                if (t.status.Equals("confirmed")) {
                    if (t.misses >= Integer("DELETE", 0)) {
                        t.status = "deleted";
                        t.deleted = scan;
                        deleted.Add(Convert.ToString(t.number));
                    }
                } else if (t.hits >= Integer("CONFIRM", 0)) {
                    t.status = "confirmed";
                    t.confirmed = scan;
                    confirmed.Add(Convert.ToString(t.number));
                } else if (scan - t.birth + 1 >= Integer("CONFIRM", 1)) {
                    t.status = "deleted";
                    t.deleted = scan;
                    deleted.Add(Convert.ToString(t.number));
                }
            }
            for (int j = 0; j < b; j++)
                if (!usedColumns[j]) {
                    Track t = new Track(tracks.Count + 1, scan, points[j],
                                        MakeKalman(settings["MODEL"][0], points[j]));
                    tracks.Add(t);
                    processed.Add(t);
                    created.Add(t.number + ":" + (j + 1));
                }
            int cm = 0, ct = 0, tentative = 0, confirmedCount = 0;
            foreach (int count in columnGates)
                if (count >= 2)
                    cm++;
            foreach (int count in rowGates)
                if (count >= 2)
                    ct++;
            conflictMeasurements += cm;
            conflictTracks += ct;
            foreach (Track t in tracks) {
                if (t.status.Equals("tentative"))
                    tentative++;
                if (t.status.Equals("confirmed"))
                    confirmedCount++;
            }
            log.Add("scan " + scan + " tracks " + a + " measurements " + b);
            log.Add(Listed("gate", gateLines));
            log.Add(Pairs("assign", assigned, live));
            log.Add(Pairs("greedy", greedy, live));
            log.Add(Listed("missed", missed));
            log.Add(Listed("new", created));
            log.Add(Listed("confirmed", confirmed));
            log.Add(Listed("deleted", deleted));
            log.Add("status tentative " + tentative + " confirmed " + confirmedCount);
            log.Add("conflicts measurements " + cm + " tracks " + ct);
            foreach (Track t in processed) {
                string row = t.number + "," + scan;
                for (int c = 0; c < 4; c++)
                    row += "," + F(t.kalman.x[c]);
                rows.Add(row + "," + t.status);
            }
        }
        foreach (Track t in tracks)
            if (t.confirmed != 0)
                evaluated.Add(t);
    }
    public static void CompareFilters() {
        foreach (Track t in evaluated) {
            t.estimates = Enumerable.Range(0, 5)
                              .Select(
                                  _ => new double [scans + 1][])
                              .ToArray();
            t.primaryCovariances = new double [scans + 1][][];
            List<Kalman.FilterState> primaryHistory = null;
            for (int filter = 0; filter < 2; filter++) {
                Kalman k = MakeKalman(FILTERS[filter].ToUpperInvariant(), t.observations[t.birth]);
                List<Kalman.FilterState> history = new();
                double likelihood = 0;
                for (int scan = t.birth; scan <= t.lastHit; scan++) {
                    if (scan > t.birth) {
                        k.Predict(times[scan] - times[scan - 1]);
                        if (t.observations[scan] != null)
                            likelihood += k.Update(t.observations[scan]).likelihood;
                    }
                    t.estimates[filter][scan] = k.x[..(4)];
                    history.Add(k.Capture());
                }
                t.modelLogs[filter] = likelihood;
                if (filter == primary)
                    primaryHistory = history;
            }
            List<double[]> smooth = Kalman.Smooth(primaryHistory);
            for (int scan = t.birth; scan <= t.lastHit; scan++) {
                int i = scan - t.birth;
                t.primaryCovariances[scan] = primaryHistory[i].p;
                t.estimates[4][scan] = smooth[i][..(4)];
            }
            double[] abg = new double[6];
            Array.Copy(t.observations[t.birth], 0, abg, 0, 2);
            double alpha = Real("ABG", 0), beta = Real("ABG", 1), gamma = Real("ABG", 2);
            Imm imm =
                new Imm(Values("IMM_Q"), Values("IMM_TRANSITION"), Values("IMM_INITIAL"), Parameter("SIGMA"),
                        Parameter("INIT_VELOCITY_VARIANCE"), t.observations[t.birth]);
            t.high = new double[scans + 1];
            int gap = 0;
            double[] previous = null;
            for (int scan = t.birth; scan <= t.lastHit; scan++) {
                if (scan > t.birth) {
                    double interval = times[scan] - times[scan - 1];
                    double[] measurement = t.observations[scan];
                    for (int axis = 0; axis < 2; axis++) {
                        double p = abg[axis], v = abg[axis + 2], w = abg[axis + 4];
                        p = p + interval * v + interval * interval * w / 2;
                        v = v + interval * w;
                        if (measurement != null) {
                            double residual = measurement[axis] - p;
                            p = p + alpha * residual;
                            v = v + beta * residual / interval;
                            w = w + 2 * gamma * residual / (interval * interval);
                        }
                        abg[axis] = p;
                        abg[axis + 2] = v;
                        abg[axis + 4] = w;
                    }
                    imm.Step(interval, measurement);
                }
                t.estimates[2][scan] = abg[..(4)];
                t.estimates[3][scan] = imm.Estimate();
                t.high[scan] = imm.probabilities[1];
                gap = t.observations[scan] == null ? gap + 1 : 0;
                t.longest = Math.Max(t.longest, gap);
                if (previous != null)
                    t.path += Evaluation.Distance(previous, t.estimates[4][scan]);
                previous = t.estimates[4][scan];
            }
        }
    }
    public static void EvaluateScans() {
        labels = Enumerable.Range(0, 5)
                     .Select(filterIndex => Enumerable.Range(0, targets.Count)
                                                .Select(
                                                    _ => new int[scans + 1])
                                                .ToArray())
                     .ToArray();
        ospa = Enumerable.Range(0, 5)
                   .Select(
                       _ => new double[scans])
                   .ToArray();
        sizes = Enumerable.Range(0, scans)
                    .Select(
                        _ => new int[2])
                    .ToArray();
        double threshold = Parameter("MATCH_DISTANCE"), cutoff = Parameter("OSPA_CUTOFF");
        for (int scan = 1; scan <= scans; scan++) {
            List<Track> active = new();
            foreach (Track t in evaluated)
                if (t.birth <= scan && scan <= t.lastHit)
                    active.Add(t);
            List<int> present = new();
            List<double[]> truth = new();
            for (int b = 0; b < targets.Count; b++)
                if (targets[b].positions[scan] != null) {
                    present.Add(b);
                    truth.Add(targets[b].positions[scan]);
                }
            sizes[scan - 1] = new int[] { truth.Count, active.Count };
            for (int filter = 0; filter < 5; filter++) {
                List<double[]> estimates = new();
                foreach (Track t in active)
                    estimates.Add(t.estimates[filter][scan]);
                double[][] costs = Enumerable.Range(0, active.Count)
                                       .Select(
                                           _ => new double[truth.Count])
                                       .ToArray();
                bool[][] usable = Enumerable.Range(0, active.Count)
                                      .Select(
                                          _ => new bool[truth.Count])
                                      .ToArray();
                for (int i = 0; i < active.Count; i++)
                    for (int j = 0; j < truth.Count; j++) {
                        costs[i][j] = Evaluation.Distance(estimates[i], truth[j]);
                        usable[i][j] = costs[i][j] <= threshold;
                    }
                foreach (Association.Pair pair in Association.Optimal(costs, usable)) {
                    Track t = active[pair.row];
                    int b = present[pair.column];
                    labels[filter][b][scan] = t.number;
                    if (filter == primary)
                        t.primaryMatches[scan] = targets[b].number;
                }
                ospa[filter][scan - 1] = Evaluation.Ospa(estimates, truth, cutoff);
            }
        }
        continuity = Enumerable.Range(0, 5)
                         .Select(
                             _ => new Evaluation.Continuity[targets.Count])
                         .ToArray();
        for (int f = 0; f < 5; f++)
            for (int b = 0; b < targets.Count; b++) {
                Target t = targets[b];
                continuity[f][b] = Evaluation.MeasureContinuity(labels[f][b][t.first..t.last + 1]);
            }
    }
    public static void MatchTracks() {
        int a = evaluated.Count, b = targets.Count;
        double[][] costs = Enumerable.Range(0, a)
                               .Select(
                                   _ => new double[b])
                               .ToArray();
        bool[][] usable = Enumerable.Range(0, a)
                              .Select(
                                  _ => new bool[b])
                              .ToArray();
        double cutoff = Parameter("OSPA_CUTOFF");
        for (int i = 0; i < a; i++) {
            Track t = evaluated[i];
            for (int j = 0; j < b; j++) {
                Target target = targets[j];
                int first = Math.Max(t.birth, target.first), last = Math.Min(t.lastHit, target.last);
                if (first > last)
                    continue;
                double total = 0;
                bool accepted = false;
                int count = 0;
                for (int scan = Math.Min(t.birth, target.first); scan <= Math.Max(t.lastHit, target.last);
                     scan++) {
                    bool inTrack = t.birth <= scan && scan <= t.lastHit,
                         inTarget = target.first <= scan && scan <= target.last;
                    if (!inTrack && !inTarget)
                        continue;
                    count++;
                    if (inTrack && inTarget) {
                        double d = Evaluation.Distance(t.estimates[primary][scan], target.positions[scan]);
                        total += Math.Min(cutoff, d);
                        if (d < cutoff)
                            accepted = true;
                    } else
                        total += cutoff;
                }
                costs[i][j] = total / count;
                usable[i][j] = accepted;
            }
        }
        matched = new Track[b];
        foreach (Association.Pair pair in Association.Optimal(costs, usable)) {
            Track t = evaluated[pair.row];
            int j = pair.column;
            Target target = targets[j];
            t.target = j;
            t.meanDistance = costs[pair.row][j];
            t.commonFirst = Math.Max(t.birth, target.first);
            t.commonLast = Math.Min(t.lastHit, target.last);
            matched[j] = t;
        }
    }
    public static void EvaluateErrors() {
        results = new TargetResult[targets.Count];
        double[] totalsP = new double[5], totalsV = new double[5];
        int countP = 0, countV = 0;
        for (int b = 0; b < targets.Count; b++) {
            Track t = matched[b];
            if (t == null)
                continue;
            Target target = targets[b];
            double[] position = new double[5], velocity = new double[5],
                     nees = new double[t.commonLast - t.commonFirst + 1];
            int velocityCount = 0;
            for (int scan = t.commonFirst; scan <= t.commonLast; scan++) {
                double[] trueVelocity = null;
                if (scan > target.first && scan < target.last) {
                    double interval = times[scan + 1] - times[scan - 1];
                    trueVelocity = new double[] {
                        (target.positions[scan + 1][0] - target.positions[scan - 1][0]) / interval,
                        (target.positions[scan + 1][1] - target.positions[scan - 1][1]) / interval
                    };
                    velocityCount++;
                }
                for (int filter = 0; filter < 5; filter++) {
                    double[] estimate = t.estimates[filter][scan];
                    double pe = Evaluation.Squared(estimate, target.positions[scan]);
                    position[filter] += pe;
                    totalsP[filter] += pe;
                    if (trueVelocity != null) {
                        double[] v = { estimate[2], estimate[3] };
                        double ve = Evaluation.Squared(v, trueVelocity);
                        velocity[filter] += ve;
                        totalsV[filter] += ve;
                    }
                }
                double[] error = { t.estimates[primary][scan][0] - target.positions[scan][0],
                                   t.estimates[primary][scan][1] - target.positions[scan][1] };
                double[][] p = t.primaryCovariances[scan],
                           p2 = new double[][] { new double[] { p[0][0], p[0][1] },
                                                 new double[] { p[1][0], p[1][1] } };
                nees[scan - t.commonFirst] = Matrix.Quadratic2(error, Matrix.Inverse(p2));
            }
            int n = t.commonLast - t.commonFirst + 1;
            for (int filter = 0; filter < 5; filter++) {
                position[filter] = Math.Sqrt(position[filter] / n);
                velocity[filter] = Math.Sqrt(velocity[filter] / velocityCount);
            }
            countP += n;
            countV += velocityCount;
            results[b] = new TargetResult(position, velocity, velocityCount, nees);
        }
        overallPosition = new double[5];
        overallVelocity = new double[5];
        for (int filter = 0; filter < 5; filter++) {
            overallPosition[filter] = Math.Sqrt(totalsP[filter] / countP);
            overallVelocity[filter] = Math.Sqrt(totalsV[filter] / countV);
        }
    }
    public static string Scores(double[] values) {
        int best = 0;
        string text = "";
        for (int k = 0; k < 5; k++) {
            if (k > 0)
                text += " ";
            text += FILTERS[k] + " " + F(values[k]);
            if (double.Parse(F(values[k])) < double.Parse(F(values[best])))
                best = k;
        }
        return text + " best " + FILTERS[best];
    }
    public static List<string> Segments(int[] labels, int first, int last, bool includeLabel) {
        List<string> result = new();
        int scan = first;
        while (scan <= last) {
            if (labels[scan] == 0) {
                scan++;
                continue;
            }
            int start = scan, label = labels[scan];
            while (scan + 1 <= last && labels[scan + 1] == label)
                scan++;
            result.Add(start + "-" + scan + (includeLabel ? ":" + label : ""));
            scan++;
        }
        return result;
    }
    public static void Section(List<string> lines, string title) {
        if (lines.Count != 0)
            lines.Add("");
        lines.Add(title);
    }
    public static List<string> EvaluationLines() {
        List<string> lines = new();
        Section(lines, "summary");
        int totalMeasurements = 0, falseTracks = 0, used = 0, lost = 0;
        foreach (List<double[]> points in measurements)
            totalMeasurements += points.Count;
        foreach (Track t in evaluated) {
            int count = 0;
            foreach (int label in t.primaryMatches)
                if (label != 0)
                    count++;
            if (count == 0)
                falseTracks++;
            used += t.hits;
        }
        foreach (Track t in matched)
            if (t == null)
                lost++;
        lines.AddRange([
            "scans " + scans, "measurements " + totalMeasurements, "targets " + targets.Count,
            "tracks_created " + tracks.Count, "tracks_confirmed " + evaluated.Count,
            "false_tracks " + falseTracks, "missed_targets " + lost, "measurements_used " + used,
            "conflict_measurements " + conflictMeasurements, "conflict_tracks " + conflictTracks,
            "greedy_differences " + greedyDifferences
        ]);
        Section(lines, "targets");
        foreach (Target target in targets) {
            double path = 0;
            for (int k = target.first + 1; k <= target.last; k++)
                path += Evaluation.Distance(target.positions[k - 1], target.positions[k]);
            lines.Add("target " + target.number + " first " + target.first + " last " + target.last +
                      " scans " + (target.last - target.first + 1) + " path " + F(path) + " mean_speed " +
                      F(path / (times[target.last] - times[target.first])));
        }
        double bound = Parameter("CONSISTENCY_BOUND");
        List<double> allNis = new();
        Section(lines, "tracks");
        foreach (Track t in evaluated) {
            double sum = 0;
            int count = 0, inside = 0;
            for (int k = t.birth + 1; k <= t.lastHit; k++)
                if (t.observations[k] != null) {
                    double value = t.nis[k];
                    sum += value;
                    count++;
                    if (value <= bound)
                        inside++;
                    allNis.Add(value);
                }
            lines.Add("track " + t.number + " birth " + t.birth + " confirmed " + t.confirmed + " end " +
                      t.lastHit + " deleted " + Optional(t.deleted) + " hits " + t.hits + " misses " +
                      (t.lastHit - t.birth + 1 - t.hits) + " longest_gap " + t.longest + " path " +
                      F(t.path) + " nis " + F(sum / count) + " nis_inside " + inside + "/" + count);
        }
        Section(lines, "matching");
        foreach (Track t in evaluated) {
            string line =
                "track " + t.number + " target " + (t.target < 0 ? "-" : targets[t.target].number.ToString());
            if (t.target >= 0)
                line +=
                    " common " + (t.commonLast - t.commonFirst + 1) + " mean_distance " + F(t.meanDistance);
            int count = 0;
            foreach (int label in t.primaryMatches)
                if (label != 0)
                    count++;
            line += " matched_scans " + count + " " +
                    Listed("segments", Segments(t.primaryMatches, t.birth, t.lastHit, true));
            lines.Add(line);
        }
        Section(lines, "rmse");
        for (int b = 0; b < targets.Count; b++) {
            Target target = targets[b];
            Track t = matched[b];
            if (t == null) {
                lines.Add("target " + target.number + " track -");
                continue;
            }
            TargetResult result = results[b];
            lines.Add("target " + target.number + " track " + t.number + " common " +
                      (t.commonLast - t.commonFirst + 1) + " " + Scores(result.position));
            lines.Add("target " + target.number + " velocity " + result.velocityCount + " " +
                      Scores(result.velocity));
        }
        lines.Add("overall position " + Scores(overallPosition));
        lines.Add("overall velocity " + Scores(overallVelocity));
        Section(lines, "consistency");
        for (int b = 0; b < targets.Count; b++) {
            Target target = targets[b];
            Track t = matched[b];
            if (t == null) {
                lines.Add("target " + target.number + " track -");
                continue;
            }
            double[] values = results[b].nees;
            int inside = 0;
            foreach (double value in values)
                if (value <= bound)
                    inside++;
            lines.Add("target " + target.number + " track " + t.number + " nees " +
                      F(Matrix.Total(values) / values.Length) + " inside " + inside + "/" + values.Length);
        }
        double[] edges = Values("NIS_EDGES");
        int[] observed = new int[edges.Length + 1];
        foreach (double value in allNis) {
            int bin = 0;
            while (bin < edges.Length && value >= edges[bin])
                bin++;
            observed[bin]++;
        }
        string histogram = "nis_histogram total " + allNis.Count + " observed";
        foreach (int count in observed)
            histogram += " " + count;
        histogram += " expected";
        double lower = 0;
        for (int k = 0; k <= edges.Length; k++) {
            double upperProbability = k == edges.Length ? 0 : Math.Exp(-edges[k] / 2);
            histogram += " " + F(allNis.Count * (Math.Exp(-lower / 2) - upperProbability));
            if (k < edges.Length)
                lower = edges[k];
        }
        lines.Add(histogram);
        Section(lines, "models");
        foreach (Track t in evaluated)
            lines.Add("track " + t.number + " updates " + (t.hits - 1) + " cv " + F(t.modelLogs[0]) + " ca " +
                      F(t.modelLogs[1]) + " better " + (t.modelLogs[0] >= t.modelLogs[1] ? "cv" : "ca"));
        Section(lines, "ospa cutoff " + F(Parameter("OSPA_CUTOFF")) + " order 2");
        lines.Add("scan targets tracks cv ca abg imm rts");
        for (int k = 0; k < scans; k++) {
            string line = (k + 1) + " " + sizes[k][0] + " " + sizes[k][1];
            for (int filter = 0; filter < 5; filter++)
                line += " " + F(ospa[filter][k]);
            lines.Add(line);
        }
        string mean = "mean";
        for (int filter = 0; filter < 5; filter++)
            mean += " " + F(Matrix.Total(ospa[filter]) / scans);
        lines.Add(mean);
        Section(lines, "continuity");
        for (int filter = 0; filter < 5; filter++) {
            int covered = 0, breaks = 0, swaps = 0;
            foreach (Evaluation.Continuity c in continuity[filter]) {
                covered += c.covered;
                breaks += c.breaks;
                swaps += c.swaps;
            }
            lines.Add(FILTERS[filter] + " covered " + covered + " breaks " + breaks + " swaps " + swaps);
            for (int b = 0; b < targets.Count; b++) {
                Target target = targets[b];
                Evaluation.Continuity c = continuity[filter][b];
                lines.Add("  target " + target.number + " scans " + (target.last - target.first + 1) +
                          " covered " + c.covered + " breaks " + c.breaks + " swaps " + c.swaps + " delay " +
                          (c.delay < 0 ? "-" : Convert.ToString(c.delay)));
            }
        }
        Section(lines, "imm");
        foreach (Track t in evaluated) {
            double sum = 0;
            int maximum = t.birth, count = 0;
            int[] high = new int[scans + 1];
            for (int scan = t.birth; scan <= t.lastHit; scan++) {
                sum += t.high[scan];
                if (t.high[scan] > t.high[maximum])
                    maximum = scan;
                if (t.high[scan] > 0.5) {
                    high[scan] = 1;
                    count++;
                }
            }
            lines.Add("track " + t.number + " mean_high " + F(sum / (t.lastHit - t.birth + 1)) +
                      " max_high " + F(t.high[maximum]) + " at " + maximum + " high_scans " + count + " " +
                      Listed("segments", Segments(high, t.birth, t.lastHit, false)));
        }
        return lines;
    }
    public static int[] Cell(double[] point) {
        double xmin = Real("PLOT_X", 0), xmax = Real("PLOT_X", 1), ymin = Real("PLOT_Y", 0),
               ymax = Real("PLOT_Y", 1);
        int width = Integer("PLOT_SIZE", 0), height = Integer("PLOT_SIZE", 1);
        double dx = (xmax - xmin) / width, dy = (ymax - ymin) / height;
        int c = (int)Math.Floor((point[0] - xmin) / dx), r = (int)Math.Floor((ymax - point[1]) / dy);
        return c >= 0 && c < width && r >= 0 && r < height ? new int[] { r, c } : null;
    }
    public static char[][] Grid(int height, int width) {
        char[][] result = Enumerable.Range(0, height)
                              .Select(
                                  _ => new char[width])
                              .ToArray();
        foreach (char[] row in result)
            Array.Fill(row, ' ');
        return result;
    }
    public static List<string> Framed(char[][] rows) {
        List<string> lines = new();
        string border = "+" + new string('-', rows[0].Length) + "+";
        lines.Add(border);
        foreach (char[] row in rows)
            lines.Add("|" + new string(row) + "|");
        lines.Add(border);
        return lines;
    }
    public static List<string> PlotLines() {
        int width = Integer("PLOT_SIZE", 0), height = Integer("PLOT_SIZE", 1);
        char[] characters = new char[tracks.Count + 1];
        for (int i = 0; i < evaluated.Count; i++)
            characters[evaluated[i].number] = (char)(i < 26 ? 'A' + i : 'a' + i - 26);
        char[][] trajectory = Grid(height, width);
        foreach (Target target in targets)
            for (int k = target.first; k <= target.last; k++) {
                int[] c = Cell(target.positions[k]);
                if (c != null)
                    trajectory[c[0]][c[1]] = '.';
            }
        foreach (Track t in evaluated)
            for (int k = t.birth; k <= t.lastHit; k++) {
                int[] c = Cell(t.estimates[4][k]);
                if (c != null)
                    trajectory[c[0]][c[1]] = characters[t.number];
            }
        List<string> lines = new();
        lines.Add("tracks x " + F(Real("PLOT_X", 0)) + " " + F(Real("PLOT_X", 1)) + " y " +
                  F(Real("PLOT_Y", 0)) + " " + F(Real("PLOT_Y", 1)) + " size " + width + " " + height);
        lines.AddRange(Framed(trajectory));
        foreach (Track t in evaluated)
            lines.Add(characters[t.number] + " track " + t.number + " target " +
                      (t.target < 0 ? "-" : targets[t.target].number.ToString()));
        int[][] counts = Enumerable.Range(0, height)
                             .Select(
                                 _ => new int[width])
                             .ToArray();
        for (int k = 1; k <= scans; k++)
            foreach (double[] measurement in measurements[k]) {
                int[] c = Cell(measurement);
                if (c != null)
                    counts[c[0]][c[1]]++;
            }
        char[][] density = Grid(height, width);
        for (int r = 0; r < height; r++)
            for (int c = 0; c < width; c++) {
                int n = counts[r][c];
                density[r][c] = n == 0 ? ' ' : n < 10 ? (char)('0' + n) : '#';
            }
        lines.Add("");
        lines.Add("measurements");
        lines.AddRange(Framed(density));
        lines.Add("");
        lines.Add("timeline");
        for (int b = 0; b < targets.Count; b++) {
            Target target = targets[b];
            StringBuilder timeline = new StringBuilder();
            for (int k = 1; k <= scans; k++)
                timeline.Append(target.positions[k] == null  ? ' '
                                : labels[primary][b][k] == 0 ? '.'
                                                             : characters[labels[primary][b][k]]);
            lines.Add(target.number + " |" + timeline + "|");
        }
        lines.Add("");
        lines.Add("ospa " + FILTERS[primary]);
        char[][] bars = Grid(10, scans);
        for (int k = 0; k < scans; k++) {
            int h = (int)Math.Floor(10 * ospa[primary][k] / Parameter("OSPA_CUTOFF"));
            for (int r = 0; r < 10; r++)
                if (h >= 10 - r)
                    bars[r][k] = '#';
        }
        lines.AddRange(Framed(bars));
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Read();
        TrackAll();
        CompareFilters();
        EvaluateScans();
        MatchTracks();
        EvaluateErrors();
        Directory.CreateDirectory(Path.Combine("output"));
        List<string> smoothed = new();
        smoothed.Add("track,scan,x,y,vx,vy");
        foreach (Track t in evaluated)
            for (int k = t.birth; k <= t.lastHit; k++) {
                string line = t.number + "," + k;
                foreach (double value in t.estimates[4][k])
                    line += "," + F(value);
                smoothed.Add(line);
            }
        Write("tracks.csv", rows);
        Write("smoothed.csv", smoothed);
        Write("association_log.txt", log);
        Write("evaluation.txt", EvaluationLines());
        Write("track_plot.txt", PlotLines());
    }
}
