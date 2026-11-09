import java.nio.file.*;
import java.util.*;

public class Main {
    static final String[] FILTERS = {"cv", "ca", "abg", "imm", "rts"};
    static final Map<String, List<String>> params = new HashMap<>();
    static final List<List<double[]>> measurements = new ArrayList<>();
    static double[] times;
    static int scans, primary, conflictMeasurements, conflictTracks, greedyDifferences;
    static final List<Target> targets = new ArrayList<>();
    static final List<Track> tracks = new ArrayList<>(), evaluated = new ArrayList<>();
    static final List<String> rows = new ArrayList<>(), log = new ArrayList<>();
    static int[][][] labels;
    static double[][] ospa;
    static int[][] sizes;
    static Evaluation.Continuity[][] continuity;
    static Track[] matched;
    static TargetResult[] results;
    static double[] overallPosition, overallVelocity;
    static class Target {
        int number, first, last;
        double[][] positions;
        Target(int number) {
            this.number = number;
            first = scans + 1;
            positions = new double[scans + 1][];
        }
    }
    static class Track {
        int number, birth, lastHit, confirmed, deleted, hits = 1, misses, longest, target = -1;
        String status = "tentative";
        Kalman kalman;
        double[][] observations;
        double[] nis, high;
        int[] primaryMatches;
        double[][][] estimates, primaryCovariances;
        double[] modelLogs = new double[2];
        double path, meanDistance;
        int commonFirst, commonLast;
        Track(int number, int scan, double[] measurement, Kalman kalman) {
            this.number = number;
            birth = lastHit = scan;
            this.kalman = kalman;
            observations = new double[scans + 1][];
            observations[scan] = measurement;
            nis = new double[scans + 1];
            primaryMatches = new int[scans + 1];
        }
    }
    record TargetResult(double[] position, double[] velocity, int velocityCount, double[] nees) {}
    static String f(double value) {
        return Evaluation.real(value);
    }
    static String optional(int value) {
        return value == 0 ? "-" : Integer.toString(value);
    }
    static double parameter(String name) {
        return real(name, 0);
    }
    static double real(String name, int i) {
        return Double.parseDouble(params.get(name).get(i));
    }
    static int integer(String name, int i) {
        return Integer.parseInt(params.get(name).get(i));
    }
    static double[] values(String name) {
        List<String> values = params.get(name);
        double[] result = new double[values.size()];
        for (int i = 0; i < result.length; i++)
            result[i] = Double.parseDouble(values.get(i));
        return result;
    }
    static List<String> lines(String name) throws Exception {
        return Files.readAllLines(Path.of("input", name));
    }
    static void read() throws Exception {
        List<String> input = lines("measurements.csv");
        scans = Integer.parseInt(input.getLast().split(",")[0]);
        times = new double[scans + 1];
        for (int k = 0; k <= scans; k++)
            measurements.add(new ArrayList<>());
        for (int i = 1; i < input.size(); i++) {
            String[] w = input.get(i).split(",");
            int k = Integer.parseInt(w[0]);
            times[k] = Double.parseDouble(w[1]);
            measurements.get(k).add(new double[] {Double.parseDouble(w[2]), Double.parseDouble(w[3])});
        }
        input = lines("truth.csv");
        for (int i = 1; i < input.size(); i++) {
            String[] w = input.get(i).split(",");
            int number = Integer.parseInt(w[0]), scan = Integer.parseInt(w[1]);
            if (targets.isEmpty() || targets.getLast().number != number)
                targets.add(new Target(number));
            Target t = targets.getLast();
            t.first = Math.min(t.first, scan);
            t.last = scan;
            t.positions[scan] = new double[] {Double.parseDouble(w[2]), Double.parseDouble(w[3])};
        }
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            params.put(w[0], new ArrayList<>(Arrays.asList(w).subList(1, w.length)));
        }
        primary = params.get("MODEL").get(0).equals("CV") ? 0 : 1;
    }
    static Kalman makeKalman(String model, double[] measurement) {
        return new Kalman(model, parameter("Q_" + model), parameter("SIGMA"),
                          parameter("INIT_VELOCITY_VARIANCE"), parameter("INIT_ACCELERATION_VARIANCE"),
                          measurement);
    }
    static String listed(String keyword, List<String> items) {
        return keyword + " " + (items.isEmpty() ? "none" : String.join(" ", items));
    }
    static String pairs(String keyword, List<Association.Pair> pairs, List<Track> live) {
        List<String> items = new ArrayList<>();
        for (Association.Pair pair : pairs)
            items.add(live.get(pair.row()).number + ":" + (pair.column() + 1));
        return listed(keyword, items);
    }
    static void trackAll() {
        rows.add("track,scan,x,y,vx,vy,status");
        for (int scan = 1; scan <= scans; scan++) {
            List<Track> live = new ArrayList<>();
            for (Track t : tracks)
                if (!t.status.equals("deleted"))
                    live.add(t);
            List<double[]> points = measurements.get(scan);
            if (scan > 1)
                for (Track t : live)
                    t.kalman.predict(times[scan] - times[scan - 1]);
            int a = live.size(), b = points.size();
            double[][] costs = new double[a][b];
            boolean[][] usable = new boolean[a][b];
            Kalman.Innovation[][] innovations = new Kalman.Innovation[a][b];
            int[] rowGates = new int[a], columnGates = new int[b];
            List<Association.Pair> gated = new ArrayList<>();
            List<String> gateLines = new ArrayList<>();
            for (int i = 0; i < a; i++)
                for (int j = 0; j < b; j++) {
                    Kalman.Innovation v = live.get(i).kalman.innovation(points.get(j));
                    if (v.distance() <= parameter("GATE")) {
                        costs[i][j] = v.distance();
                        usable[i][j] = true;
                        innovations[i][j] = v;
                        rowGates[i]++;
                        columnGates[j]++;
                        gated.add(new Association.Pair(i, j));
                        gateLines.add(live.get(i).number + ":" + (j + 1) + "=" + f(v.distance()));
                    }
                }
            List<Association.Pair> assigned = Association.optimal(costs, usable);
            gated.sort(Comparator.comparingDouble((Association.Pair p) -> costs[p.row()][p.column()])
                           .thenComparingInt(Association.Pair::row)
                           .thenComparingInt(Association.Pair::column));
            List<Association.Pair> greedy = new ArrayList<>();
            boolean[] usedRows = new boolean[a], usedColumns = new boolean[b];
            for (Association.Pair p : gated)
                if (!usedRows[p.row()] && !usedColumns[p.column()]) {
                    greedy.add(p);
                    usedRows[p.row()] = true;
                    usedColumns[p.column()] = true;
                }
            greedy.sort(
                Comparator.comparingInt(Association.Pair::row).thenComparingInt(Association.Pair::column));
            if (!assigned.equals(greedy))
                greedyDifferences++;
            int[] matches = new int[a];
            Arrays.fill(matches, -1);
            Arrays.fill(usedColumns, false);
            for (Association.Pair p : assigned) {
                matches[p.row()] = p.column();
                usedColumns[p.column()] = true;
            }
            List<String> missed = new ArrayList<>(), confirmed = new ArrayList<>(),
                         deleted = new ArrayList<>(), created = new ArrayList<>();
            List<Track> processed = new ArrayList<>(live);
            for (int i = 0; i < a; i++) {
                Track t = live.get(i);
                int j = matches[i];
                if (j >= 0) {
                    t.kalman.update(points.get(j), innovations[i][j]);
                    t.observations[scan] = points.get(j);
                    t.nis[scan] = costs[i][j];
                    t.lastHit = scan;
                    t.hits++;
                    t.misses = 0;
                } else {
                    t.misses++;
                    missed.add(Integer.toString(t.number));
                }
                if (t.status.equals("confirmed")) {
                    if (t.misses >= integer("DELETE", 0)) {
                        t.status = "deleted";
                        t.deleted = scan;
                        deleted.add(Integer.toString(t.number));
                    }
                } else if (t.hits >= integer("CONFIRM", 0)) {
                    t.status = "confirmed";
                    t.confirmed = scan;
                    confirmed.add(Integer.toString(t.number));
                } else if (scan - t.birth + 1 >= integer("CONFIRM", 1)) {
                    t.status = "deleted";
                    t.deleted = scan;
                    deleted.add(Integer.toString(t.number));
                }
            }
            for (int j = 0; j < b; j++)
                if (!usedColumns[j]) {
                    Track t = new Track(tracks.size() + 1, scan, points.get(j),
                                        makeKalman(params.get("MODEL").get(0), points.get(j)));
                    tracks.add(t);
                    processed.add(t);
                    created.add(t.number + ":" + (j + 1));
                }
            int cm = 0, ct = 0, tentative = 0, confirmedCount = 0;
            for (int count : columnGates)
                if (count >= 2)
                    cm++;
            for (int count : rowGates)
                if (count >= 2)
                    ct++;
            conflictMeasurements += cm;
            conflictTracks += ct;
            for (Track t : tracks) {
                if (t.status.equals("tentative"))
                    tentative++;
                if (t.status.equals("confirmed"))
                    confirmedCount++;
            }
            log.add("scan " + scan + " tracks " + a + " measurements " + b);
            log.add(listed("gate", gateLines));
            log.add(pairs("assign", assigned, live));
            log.add(pairs("greedy", greedy, live));
            log.add(listed("missed", missed));
            log.add(listed("new", created));
            log.add(listed("confirmed", confirmed));
            log.add(listed("deleted", deleted));
            log.add("status tentative " + tentative + " confirmed " + confirmedCount);
            log.add("conflicts measurements " + cm + " tracks " + ct);
            for (Track t : processed) {
                String row = t.number + "," + scan;
                for (int c = 0; c < 4; c++)
                    row += "," + f(t.kalman.x[c]);
                rows.add(row + "," + t.status);
            }
        }
        for (Track t : tracks)
            if (t.confirmed != 0)
                evaluated.add(t);
    }
    static void compareFilters() {
        for (Track t : evaluated) {
            t.estimates = new double[5][scans + 1][];
            t.primaryCovariances = new double[scans + 1][][];
            List<Kalman.Snapshot> primaryHistory = null;
            for (int filter = 0; filter < 2; filter++) {
                Kalman k = makeKalman(FILTERS[filter].toUpperCase(Locale.ROOT), t.observations[t.birth]);
                List<Kalman.Snapshot> history = new ArrayList<>();
                double likelihood = 0;
                for (int scan = t.birth; scan <= t.lastHit; scan++) {
                    if (scan > t.birth) {
                        k.predict(times[scan] - times[scan - 1]);
                        if (t.observations[scan] != null)
                            likelihood += k.update(t.observations[scan]).likelihood();
                    }
                    t.estimates[filter][scan] = Arrays.copyOf(k.x, 4);
                    history.add(k.snapshot());
                }
                t.modelLogs[filter] = likelihood;
                if (filter == primary)
                    primaryHistory = history;
            }
            List<double[]> smooth = Kalman.smooth(primaryHistory);
            for (int scan = t.birth; scan <= t.lastHit; scan++) {
                int i = scan - t.birth;
                t.primaryCovariances[scan] = primaryHistory.get(i).p();
                t.estimates[4][scan] = Arrays.copyOf(smooth.get(i), 4);
            }
            double[] abg = new double[6];
            System.arraycopy(t.observations[t.birth], 0, abg, 0, 2);
            double alpha = real("ABG", 0), beta = real("ABG", 1), gamma = real("ABG", 2);
            Imm imm =
                new Imm(values("IMM_Q"), values("IMM_TRANSITION"), values("IMM_INITIAL"), parameter("SIGMA"),
                        parameter("INIT_VELOCITY_VARIANCE"), t.observations[t.birth]);
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
                    imm.step(interval, measurement);
                }
                t.estimates[2][scan] = Arrays.copyOf(abg, 4);
                t.estimates[3][scan] = imm.estimate();
                t.high[scan] = imm.probabilities[1];
                gap = t.observations[scan] == null ? gap + 1 : 0;
                t.longest = Math.max(t.longest, gap);
                if (previous != null)
                    t.path += Evaluation.distance(previous, t.estimates[4][scan]);
                previous = t.estimates[4][scan];
            }
        }
    }
    static void evaluateScans() {
        labels = new int[5][targets.size()][scans + 1];
        ospa = new double[5][scans];
        sizes = new int[scans][2];
        double threshold = parameter("MATCH_DISTANCE"), cutoff = parameter("OSPA_CUTOFF");
        for (int scan = 1; scan <= scans; scan++) {
            List<Track> active = new ArrayList<>();
            for (Track t : evaluated)
                if (t.birth <= scan && scan <= t.lastHit)
                    active.add(t);
            List<Integer> present = new ArrayList<>();
            List<double[]> truth = new ArrayList<>();
            for (int b = 0; b < targets.size(); b++)
                if (targets.get(b).positions[scan] != null) {
                    present.add(b);
                    truth.add(targets.get(b).positions[scan]);
                }
            sizes[scan - 1] = new int[] {truth.size(), active.size()};
            for (int filter = 0; filter < 5; filter++) {
                List<double[]> estimates = new ArrayList<>();
                for (Track t : active)
                    estimates.add(t.estimates[filter][scan]);
                double[][] costs = new double[active.size()][truth.size()];
                boolean[][] usable = new boolean[active.size()][truth.size()];
                for (int i = 0; i < active.size(); i++)
                    for (int j = 0; j < truth.size(); j++) {
                        costs[i][j] = Evaluation.distance(estimates.get(i), truth.get(j));
                        usable[i][j] = costs[i][j] <= threshold;
                    }
                for (Association.Pair pair : Association.optimal(costs, usable)) {
                    Track t = active.get(pair.row());
                    int b = present.get(pair.column());
                    labels[filter][b][scan] = t.number;
                    if (filter == primary)
                        t.primaryMatches[scan] = targets.get(b).number;
                }
                ospa[filter][scan - 1] = Evaluation.ospa(estimates, truth, cutoff);
            }
        }
        continuity = new Evaluation.Continuity[5][targets.size()];
        for (int f = 0; f < 5; f++)
            for (int b = 0; b < targets.size(); b++) {
                Target t = targets.get(b);
                continuity[f][b] =
                    Evaluation.continuity(Arrays.copyOfRange(labels[f][b], t.first, t.last + 1));
            }
    }
    static void matchTracks() {
        int a = evaluated.size(), b = targets.size();
        double[][] costs = new double[a][b];
        boolean[][] usable = new boolean[a][b];
        double cutoff = parameter("OSPA_CUTOFF");
        for (int i = 0; i < a; i++) {
            Track t = evaluated.get(i);
            for (int j = 0; j < b; j++) {
                Target target = targets.get(j);
                int first = Math.max(t.birth, target.first), last = Math.min(t.lastHit, target.last);
                if (first > last)
                    continue;
                double total = 0;
                boolean accepted = false;
                int count = 0;
                for (int scan = Math.min(t.birth, target.first); scan <= Math.max(t.lastHit, target.last);
                     scan++) {
                    boolean inTrack = t.birth <= scan && scan <= t.lastHit,
                            inTarget = target.first <= scan && scan <= target.last;
                    if (!inTrack && !inTarget)
                        continue;
                    count++;
                    if (inTrack && inTarget) {
                        double d = Evaluation.distance(t.estimates[primary][scan], target.positions[scan]);
                        total += Math.min(cutoff, d);
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
        for (Association.Pair pair : Association.optimal(costs, usable)) {
            Track t = evaluated.get(pair.row());
            int j = pair.column();
            Target target = targets.get(j);
            t.target = j;
            t.meanDistance = costs[pair.row()][j];
            t.commonFirst = Math.max(t.birth, target.first);
            t.commonLast = Math.min(t.lastHit, target.last);
            matched[j] = t;
        }
    }
    static void evaluateErrors() {
        results = new TargetResult[targets.size()];
        double[] totalsP = new double[5], totalsV = new double[5];
        int countP = 0, countV = 0;
        for (int b = 0; b < targets.size(); b++) {
            Track t = matched[b];
            if (t == null)
                continue;
            Target target = targets.get(b);
            double[] position = new double[5], velocity = new double[5],
                     nees = new double[t.commonLast - t.commonFirst + 1];
            int velocityCount = 0;
            for (int scan = t.commonFirst; scan <= t.commonLast; scan++) {
                double[] trueVelocity = null;
                if (scan > target.first && scan < target.last) {
                    double interval = times[scan + 1] - times[scan - 1];
                    trueVelocity = new double[] {
                        (target.positions[scan + 1][0] - target.positions[scan - 1][0]) / interval,
                        (target.positions[scan + 1][1] - target.positions[scan - 1][1]) / interval};
                    velocityCount++;
                }
                for (int filter = 0; filter < 5; filter++) {
                    double[] estimate = t.estimates[filter][scan];
                    double pe = Evaluation.squared(estimate, target.positions[scan]);
                    position[filter] += pe;
                    totalsP[filter] += pe;
                    if (trueVelocity != null) {
                        double[] v = {estimate[2], estimate[3]};
                        double ve = Evaluation.squared(v, trueVelocity);
                        velocity[filter] += ve;
                        totalsV[filter] += ve;
                    }
                }
                double[] error = {t.estimates[primary][scan][0] - target.positions[scan][0],
                                  t.estimates[primary][scan][1] - target.positions[scan][1]};
                double[][] p = t.primaryCovariances[scan], p2 = {{p[0][0], p[0][1]}, {p[1][0], p[1][1]}};
                nees[scan - t.commonFirst] = Matrix.quadratic2(error, Matrix.inverse(p2));
            }
            int n = t.commonLast - t.commonFirst + 1;
            for (int filter = 0; filter < 5; filter++) {
                position[filter] = Math.sqrt(position[filter] / n);
                velocity[filter] = Math.sqrt(velocity[filter] / velocityCount);
            }
            countP += n;
            countV += velocityCount;
            results[b] = new TargetResult(position, velocity, velocityCount, nees);
        }
        overallPosition = new double[5];
        overallVelocity = new double[5];
        for (int filter = 0; filter < 5; filter++) {
            overallPosition[filter] = Math.sqrt(totalsP[filter] / countP);
            overallVelocity[filter] = Math.sqrt(totalsV[filter] / countV);
        }
    }
    static String scores(double[] values) {
        int best = 0;
        String text = "";
        for (int k = 0; k < 5; k++) {
            if (k > 0)
                text += " ";
            text += FILTERS[k] + " " + f(values[k]);
            if (Double.parseDouble(f(values[k])) < Double.parseDouble(f(values[best])))
                best = k;
        }
        return text + " best " + FILTERS[best];
    }
    static List<String> segments(int[] labels, int first, int last, boolean includeLabel) {
        List<String> result = new ArrayList<>();
        int scan = first;
        while (scan <= last) {
            if (labels[scan] == 0) {
                scan++;
                continue;
            }
            int start = scan, label = labels[scan];
            while (scan + 1 <= last && labels[scan + 1] == label)
                scan++;
            result.add(start + "-" + scan + (includeLabel ? ":" + label : ""));
            scan++;
        }
        return result;
    }
    static void section(List<String> lines, String title) {
        if (!lines.isEmpty())
            lines.add("");
        lines.add(title);
    }
    static List<String> evaluationLines() {
        List<String> lines = new ArrayList<>();
        section(lines, "summary");
        int totalMeasurements = 0, falseTracks = 0, used = 0, lost = 0;
        for (List<double[]> points : measurements)
            totalMeasurements += points.size();
        for (Track t : evaluated) {
            int count = 0;
            for (int label : t.primaryMatches)
                if (label != 0)
                    count++;
            if (count == 0)
                falseTracks++;
            used += t.hits;
        }
        for (Track t : matched)
            if (t == null)
                lost++;
        lines.addAll(List.of("scans " + scans, "measurements " + totalMeasurements,
                             "targets " + targets.size(), "tracks_created " + tracks.size(),
                             "tracks_confirmed " + evaluated.size(), "false_tracks " + falseTracks,
                             "missed_targets " + lost, "measurements_used " + used,
                             "conflict_measurements " + conflictMeasurements,
                             "conflict_tracks " + conflictTracks, "greedy_differences " + greedyDifferences));
        section(lines, "targets");
        for (Target target : targets) {
            double path = 0;
            for (int k = target.first + 1; k <= target.last; k++)
                path += Evaluation.distance(target.positions[k - 1], target.positions[k]);
            lines.add("target " + target.number + " first " + target.first + " last " + target.last +
                      " scans " + (target.last - target.first + 1) + " path " + f(path) + " mean_speed " +
                      f(path / (times[target.last] - times[target.first])));
        }
        double bound = parameter("CONSISTENCY_BOUND");
        List<Double> allNis = new ArrayList<>();
        section(lines, "tracks");
        for (Track t : evaluated) {
            double sum = 0;
            int count = 0, inside = 0;
            for (int k = t.birth + 1; k <= t.lastHit; k++)
                if (t.observations[k] != null) {
                    double value = t.nis[k];
                    sum += value;
                    count++;
                    if (value <= bound)
                        inside++;
                    allNis.add(value);
                }
            lines.add("track " + t.number + " birth " + t.birth + " confirmed " + t.confirmed + " end " +
                      t.lastHit + " deleted " + optional(t.deleted) + " hits " + t.hits + " misses " +
                      (t.lastHit - t.birth + 1 - t.hits) + " longest_gap " + t.longest + " path " +
                      f(t.path) + " nis " + f(sum / count) + " nis_inside " + inside + "/" + count);
        }
        section(lines, "matching");
        for (Track t : evaluated) {
            String line =
                "track " + t.number + " target " + (t.target < 0 ? "-" : targets.get(t.target).number);
            if (t.target >= 0)
                line +=
                    " common " + (t.commonLast - t.commonFirst + 1) + " mean_distance " + f(t.meanDistance);
            int count = 0;
            for (int label : t.primaryMatches)
                if (label != 0)
                    count++;
            line += " matched_scans " + count + " " +
                    listed("segments", segments(t.primaryMatches, t.birth, t.lastHit, true));
            lines.add(line);
        }
        section(lines, "rmse");
        for (int b = 0; b < targets.size(); b++) {
            Target target = targets.get(b);
            Track t = matched[b];
            if (t == null) {
                lines.add("target " + target.number + " track -");
                continue;
            }
            TargetResult result = results[b];
            lines.add("target " + target.number + " track " + t.number + " common " +
                      (t.commonLast - t.commonFirst + 1) + " " + scores(result.position()));
            lines.add("target " + target.number + " velocity " + result.velocityCount() + " " +
                      scores(result.velocity()));
        }
        lines.add("overall position " + scores(overallPosition));
        lines.add("overall velocity " + scores(overallVelocity));
        section(lines, "consistency");
        for (int b = 0; b < targets.size(); b++) {
            Target target = targets.get(b);
            Track t = matched[b];
            if (t == null) {
                lines.add("target " + target.number + " track -");
                continue;
            }
            double[] values = results[b].nees();
            int inside = 0;
            for (double value : values)
                if (value <= bound)
                    inside++;
            lines.add("target " + target.number + " track " + t.number + " nees " +
                      f(Matrix.total(values) / values.length) + " inside " + inside + "/" + values.length);
        }
        double[] edges = values("NIS_EDGES");
        int[] observed = new int[edges.length + 1];
        for (double value : allNis) {
            int bin = 0;
            while (bin < edges.length && value >= edges[bin])
                bin++;
            observed[bin]++;
        }
        String histogram = "nis_histogram total " + allNis.size() + " observed";
        for (int count : observed)
            histogram += " " + count;
        histogram += " expected";
        double lower = 0;
        for (int k = 0; k <= edges.length; k++) {
            double upperProbability = k == edges.length ? 0 : Math.exp(-edges[k] / 2);
            histogram += " " + f(allNis.size() * (Math.exp(-lower / 2) - upperProbability));
            if (k < edges.length)
                lower = edges[k];
        }
        lines.add(histogram);
        section(lines, "models");
        for (Track t : evaluated)
            lines.add("track " + t.number + " updates " + (t.hits - 1) + " cv " + f(t.modelLogs[0]) + " ca " +
                      f(t.modelLogs[1]) + " better " + (t.modelLogs[0] >= t.modelLogs[1] ? "cv" : "ca"));
        section(lines, "ospa cutoff " + f(parameter("OSPA_CUTOFF")) + " order 2");
        lines.add("scan targets tracks cv ca abg imm rts");
        for (int k = 0; k < scans; k++) {
            String line = (k + 1) + " " + sizes[k][0] + " " + sizes[k][1];
            for (int filter = 0; filter < 5; filter++)
                line += " " + f(ospa[filter][k]);
            lines.add(line);
        }
        String mean = "mean";
        for (int filter = 0; filter < 5; filter++)
            mean += " " + f(Matrix.total(ospa[filter]) / scans);
        lines.add(mean);
        section(lines, "continuity");
        for (int filter = 0; filter < 5; filter++) {
            int covered = 0, breaks = 0, swaps = 0;
            for (Evaluation.Continuity c : continuity[filter]) {
                covered += c.covered();
                breaks += c.breaks();
                swaps += c.swaps();
            }
            lines.add(FILTERS[filter] + " covered " + covered + " breaks " + breaks + " swaps " + swaps);
            for (int b = 0; b < targets.size(); b++) {
                Target target = targets.get(b);
                Evaluation.Continuity c = continuity[filter][b];
                lines.add("  target " + target.number + " scans " + (target.last - target.first + 1) +
                          " covered " + c.covered() + " breaks " + c.breaks() + " swaps " + c.swaps() +
                          " delay " + (c.delay() < 0 ? "-" : Integer.toString(c.delay())));
            }
        }
        section(lines, "imm");
        for (Track t : evaluated) {
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
            lines.add("track " + t.number + " mean_high " + f(sum / (t.lastHit - t.birth + 1)) +
                      " max_high " + f(t.high[maximum]) + " at " + maximum + " high_scans " + count + " " +
                      listed("segments", segments(high, t.birth, t.lastHit, false)));
        }
        return lines;
    }
    static int[] cell(double[] point) {
        double xmin = real("PLOT_X", 0), xmax = real("PLOT_X", 1), ymin = real("PLOT_Y", 0),
               ymax = real("PLOT_Y", 1);
        int width = integer("PLOT_SIZE", 0), height = integer("PLOT_SIZE", 1);
        double dx = (xmax - xmin) / width, dy = (ymax - ymin) / height;
        int c = (int)Math.floor((point[0] - xmin) / dx), r = (int)Math.floor((ymax - point[1]) / dy);
        return c >= 0 && c < width && r >= 0 && r < height ? new int[] {r, c} : null;
    }
    static char[][] grid(int height, int width) {
        char[][] result = new char[height][width];
        for (char[] row : result)
            Arrays.fill(row, ' ');
        return result;
    }
    static List<String> framed(char[][] rows) {
        List<String> lines = new ArrayList<>();
        String border = "+"
                        + "-".repeat(rows[0].length) + "+";
        lines.add(border);
        for (char[] row : rows)
            lines.add("|" + new String(row) + "|");
        lines.add(border);
        return lines;
    }
    static List<String> plotLines() {
        int width = integer("PLOT_SIZE", 0), height = integer("PLOT_SIZE", 1);
        char[] characters = new char[tracks.size() + 1];
        for (int i = 0; i < evaluated.size(); i++)
            characters[evaluated.get(i).number] = (char)(i < 26 ? 'A' + i : 'a' + i - 26);
        char[][] trajectory = grid(height, width);
        for (Target target : targets)
            for (int k = target.first; k <= target.last; k++) {
                int[] c = cell(target.positions[k]);
                if (c != null)
                    trajectory[c[0]][c[1]] = '.';
            }
        for (Track t : evaluated)
            for (int k = t.birth; k <= t.lastHit; k++) {
                int[] c = cell(t.estimates[4][k]);
                if (c != null)
                    trajectory[c[0]][c[1]] = characters[t.number];
            }
        List<String> lines = new ArrayList<>();
        lines.add("tracks x " + f(real("PLOT_X", 0)) + " " + f(real("PLOT_X", 1)) + " y " +
                  f(real("PLOT_Y", 0)) + " " + f(real("PLOT_Y", 1)) + " size " + width + " " + height);
        lines.addAll(framed(trajectory));
        for (Track t : evaluated)
            lines.add(characters[t.number] + " track " + t.number + " target " +
                      (t.target < 0 ? "-" : targets.get(t.target).number));
        int[][] counts = new int[height][width];
        for (int k = 1; k <= scans; k++)
            for (double[] measurement : measurements.get(k)) {
                int[] c = cell(measurement);
                if (c != null)
                    counts[c[0]][c[1]]++;
            }
        char[][] density = grid(height, width);
        for (int r = 0; r < height; r++)
            for (int c = 0; c < width; c++) {
                int n = counts[r][c];
                density[r][c] = n == 0 ? ' ' : n < 10 ? (char)('0' + n) : '#';
            }
        lines.add("");
        lines.add("measurements");
        lines.addAll(framed(density));
        lines.add("");
        lines.add("timeline");
        for (int b = 0; b < targets.size(); b++) {
            Target target = targets.get(b);
            StringBuilder timeline = new StringBuilder();
            for (int k = 1; k <= scans; k++)
                timeline.append(target.positions[k] == null  ? ' '
                                : labels[primary][b][k] == 0 ? '.'
                                                             : characters[labels[primary][b][k]]);
            lines.add(target.number + " |" + timeline + "|");
        }
        lines.add("");
        lines.add("ospa " + FILTERS[primary]);
        char[][] bars = grid(10, scans);
        for (int k = 0; k < scans; k++) {
            int h = (int)Math.floor(10 * ospa[primary][k] / parameter("OSPA_CUTOFF"));
            for (int r = 0; r < 10; r++)
                if (h >= 10 - r)
                    bars[r][k] = '#';
        }
        lines.addAll(framed(bars));
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
    public static void main(String[] args) throws Exception {
        read();
        trackAll();
        compareFilters();
        evaluateScans();
        matchTracks();
        evaluateErrors();
        Files.createDirectories(Path.of("output"));
        List<String> smoothed = new ArrayList<>();
        smoothed.add("track,scan,x,y,vx,vy");
        for (Track t : evaluated)
            for (int k = t.birth; k <= t.lastHit; k++) {
                String line = t.number + "," + k;
                for (double value : t.estimates[4][k])
                    line += "," + f(value);
                smoothed.add(line);
            }
        write("tracks.csv", rows);
        write("smoothed.csv", smoothed);
        write("association_log.txt", log);
        write("evaluation.txt", evaluationLines());
        write("track_plot.txt", plotLines());
    }
}
