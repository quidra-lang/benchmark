import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.math.*;
import java.io.IOException;

public final class Main {
    static WaveformIo.Params params;
    static List<WaveformIo.Station> stations;
    static List<Picker.Pick> picks = new ArrayList<>();
    static List<Associator.Candidate> candidates;
    static List<Event> events = new ArrayList<>();
    static List<List<Event>> clusters = new ArrayList<>();
    record Jack(WaveformIo.Station station, double dx, double dy, double dz, double shift) {}
    static final class Event {
        int number, cluster;
        List<Picker.Pick> used;
        Locator.Run first, relocated;
        List<Locator.Observation> observations;
        Locator.Ellipse ellipse;
        List<Jack> jack = new ArrayList<>();
        Jack maximum;
        double startRms, gap, dmin, dh, dz, md;
        Double ml, mlc;
        String quality;
        List<Magnitude.Values> magnitudes = new ArrayList<>();
        double[] solution() {
            return relocated.solution;
        }
    }
    static String decimal(double value, int digits) {
        BigDecimal rounded = BigDecimal.valueOf(value).setScale(digits, RoundingMode.HALF_UP);
        if (rounded.signum() == 0)
            rounded = BigDecimal.ZERO.setScale(digits);
        return rounded.toPlainString();
    }
    static String magnitude(Double value) {
        return value == null ? "-" : decimal(value, 2);
    }
    static String time(int sample) {
        return sample / 100 + "." + String.format(Locale.ROOT, "%02d", sample % 100);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static List<Picker.Pick> ordered(List<Picker.Pick> input) {
        List<Picker.Pick> result = new ArrayList<>(input);
        result.sort(Comparator.comparingInt(p -> p.station.order));
        return result;
    }
    static List<Locator.Observation> observations(List<Picker.Pick> input, boolean corrected) {
        List<Locator.Observation> result = new ArrayList<>();
        for (Picker.Pick pick : input)
            result.add(new Locator.Observation(pick.station,
                                               pick.time() - (corrected ? pick.station.correction : 0)));
        return result;
    }
    static void locate() {
        for (Associator.Candidate candidate : candidates) {
            candidate.picks = ordered(candidate.picks);
            Locator.Run first = Locator.locate(observations(candidate.picks, false), params);
            candidate.passes.add(first);
            List<Picker.Pick> retained = new ArrayList<>();
            for (int i = 0; i < candidate.picks.size(); i++) {
                Picker.Pick pick = candidate.picks.get(i);
                if (Math.abs(first.residuals[i]) > params.get("residual_limit"))
                    candidate.dropped.add(pick);
                else
                    retained.add(pick);
            }
            if (!candidate.dropped.isEmpty() && retained.size() < params.integer("min_stations")) {
                candidate.rejected = true;
                for (Picker.Pick pick : candidate.picks)
                    pick.state = "rejected";
                continue;
            }
            Locator.Run adopted = first;
            if (!candidate.dropped.isEmpty()) {
                adopted = Locator.locate(observations(retained, false), params);
                candidate.passes.add(adopted);
            }
            Event event = new Event();
            event.number = events.size() + 1;
            event.used = retained;
            event.first = adopted;
            candidate.event = event;
            for (int i = 0; i < retained.size(); i++) {
                Picker.Pick pick = retained.get(i);
                pick.state = "used";
                pick.event = event.number;
                pick.firstResidual = adopted.residuals[i];
            }
            for (Picker.Pick pick : candidate.dropped) {
                pick.state = "dropped";
                pick.event = event.number;
            }
            events.add(event);
        }
    }
    static List<Picker.Pick> used(WaveformIo.Station station) {
        List<Picker.Pick> result = new ArrayList<>();
        for (Event event : events)
            for (Picker.Pick pick : event.used)
                if (pick.station == station)
                    result.add(pick);
        return result;
    }
    static void relocate() {
        double velocity = params.get("velocity");
        for (WaveformIo.Station station : stations) {
            List<Picker.Pick> used = used(station);
            double sum = 0;
            for (Picker.Pick pick : used)
                sum += pick.firstResidual;
            station.correction = used.isEmpty() ? 0 : sum / used.size();
        }
        for (Event event : events) {
            event.observations = observations(event.used, true);
            event.startRms = Locator.rms(event.first.solution, event.observations, velocity);
            event.relocated = Locator.geiger(event.first.solution, event.observations, velocity);
            for (int i = 0; i < event.used.size(); i++)
                event.used.get(i).residual = event.relocated.residuals[i];
            double[] solution = event.solution();
            event.ellipse = Locator.ellipse(solution, event.observations, velocity);
            List<Double> angles = new ArrayList<>();
            event.dmin = Double.POSITIVE_INFINITY;
            for (Picker.Pick pick : event.used) {
                WaveformIo.Station station = pick.station;
                double phi = Math.atan2(station.x - solution[0], station.y - solution[1]) * 180 / Locator.PI;
                if (phi < 0)
                    phi += 360;
                angles.add(phi);
                double distance =
                    Math.sqrt(Locator.sq(station.x - solution[0]) + Locator.sq(station.y - solution[1]));
                event.dmin = Math.min(event.dmin, distance);
            }
            Collections.sort(angles);
            event.gap = angles.getFirst() + 360 - angles.getLast();
            for (int i = 1; i < angles.size(); i++)
                event.gap = Math.max(event.gap, angles.get(i) - angles.get(i - 1));
            event.quality = "C";
            for (String grade : List.of("A", "B")) {
                double[] bound = params.row("quality_" + grade.toLowerCase(Locale.ROOT));
                if (event.gap <= bound[0] && event.relocated.rms <= bound[1] &&
                    event.ellipse.smaj() <= bound[2]) {
                    event.quality = grade;
                    break;
                }
            }
            event.dh = Math.sqrt(Locator.sq(solution[0] - event.first.solution[0]) +
                                 Locator.sq(solution[1] - event.first.solution[1]));
            event.dz = solution[2] - event.first.solution[2];
            for (int i = 0; i < event.used.size(); i++) {
                List<Locator.Observation> remaining = new ArrayList<>(event.observations);
                remaining.remove(i);
                double[] alternative = Locator.geiger(solution, remaining, velocity).solution;
                double dx = alternative[0] - solution[0], dy = alternative[1] - solution[1],
                       dz = alternative[2] - solution[2], shift = Math.sqrt(dx * dx + dy * dy);
                Jack jack = new Jack(event.used.get(i).station, dx, dy, dz, shift);
                event.jack.add(jack);
                if (event.maximum == null || shift > event.maximum.shift())
                    event.maximum = jack;
            }
        }
    }
    static void magnitudes() {
        Map<WaveformIo.Station, List<Double>> residuals = new HashMap<>();
        for (WaveformIo.Station station : stations)
            residuals.put(station, new ArrayList<>());
        for (Event event : events) {
            List<Double> local = new ArrayList<>(), duration = new ArrayList<>();
            for (Picker.Pick pick : event.used) {
                Magnitude.Values values =
                    Magnitude.perPick(pick, Locator.distance(event.solution(), pick.station) / 1000, params);
                event.magnitudes.add(values);
                duration.add(values.md());
                if (values.ml() != null)
                    local.add(values.ml());
            }
            event.ml = local.isEmpty() ? null : Magnitude.median(local);
            event.md = Magnitude.median(duration);
            for (int i = 0; i < event.used.size(); i++) {
                Magnitude.Values values = event.magnitudes.get(i);
                if (values.ml() != null)
                    residuals.get(event.used.get(i).station).add(values.ml() - event.ml);
            }
        }
        for (WaveformIo.Station station : stations) {
            List<Double> values = residuals.get(station);
            double sum = 0;
            for (double value : values)
                sum += value;
            station.magnitudeCorrection = values.isEmpty() ? 0 : sum / values.size();
        }
        for (Event event : events) {
            List<Double> values = new ArrayList<>();
            for (int i = 0; i < event.used.size(); i++) {
                Double ml = event.magnitudes.get(i).ml();
                if (ml != null)
                    values.add(ml - event.used.get(i).station.magnitudeCorrection);
            }
            event.mlc = values.isEmpty() ? null : Magnitude.median(values);
        }
    }
    static void cluster() {
        double[] bounds = params.row("cluster");
        boolean[] seen = new boolean[events.size()];
        for (int i = 0; i < events.size(); i++) {
            if (seen[i])
                continue;
            List<Event> members = new ArrayList<>();
            Deque<Integer> queue = new ArrayDeque<>();
            queue.add(i);
            seen[i] = true;
            while (!queue.isEmpty()) {
                int current = queue.removeFirst();
                Event event = events.get(current);
                members.add(event);
                for (int j = 0; j < events.size(); j++) {
                    if (seen[j])
                        continue;
                    double[] a = event.solution(), b = events.get(j).solution();
                    double distance = Math.sqrt(Locator.sq(a[0] - b[0]) + Locator.sq(a[1] - b[1]) +
                                                Locator.sq(a[2] - b[2]));
                    if (Math.abs(a[3] - b[3]) <= bounds[1] && distance <= bounds[0]) {
                        seen[j] = true;
                        queue.add(j);
                    }
                }
            }
            members.sort(Comparator.comparingInt(e -> e.number));
            clusters.add(members);
            for (Event event : members)
                event.cluster = clusters.size();
        }
    }
    static void reassociate() {
        List<Set<Integer>> stationSets = new ArrayList<>();
        for (Event event : events) {
            Set<Integer> set = new HashSet<>();
            for (Picker.Pick pick : event.used)
                set.add(pick.station.order);
            stationSets.add(set);
        }
        for (Picker.Pick pick : picks) {
            if (!pick.state.equals("unassociated"))
                continue;
            Event best = null;
            double error = 0;
            for (Event event : events) {
                if (stationSets.get(event.number - 1).contains(pick.station.order))
                    continue;
                double[] solution = event.solution();
                double residual = pick.time() - solution[3] -
                                  Locator.distance(solution, pick.station) / params.get("velocity") -
                                  pick.station.correction;
                if (Math.abs(residual) <= params.get("residual_limit") &&
                    (best == null || Math.abs(residual) < Math.abs(error))) {
                    best = event;
                    error = residual;
                }
            }
            if (best != null) {
                pick.state = "added";
                pick.event = best.number;
                pick.residual = error;
                stationSets.get(best.number - 1).add(pick.station.order);
            }
        }
    }
    static List<String> picksReport() {
        List<String> out = new ArrayList<>(
            List.of("station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual"));
        for (Picker.Pick pick : picks)
            out.add(
                pick.station.code + "," + pick.sample + "," + time(pick.sample) + "," + pick.duration + "," +
                decimal(pick.ratio, 2) + "," + pick.amplitude + "," + (pick.clipped ? "yes" : "no") + "," +
                pick.event + "," + pick.state + "," +
                (pick.state.equals("used") || pick.state.equals("added") ? decimal(pick.residual, 4) : "-"));
        return out;
    }
    static String solutionLine(String label, double[] s, double rms) {
        return label + " x=" + decimal(s[0], 1) + " y=" + decimal(s[1], 1) + " z=" + decimal(s[2], 1) +
            " t0=" + decimal(s[3], 3) + " rms=" + decimal(rms, 4);
    }
    static String codes(List<Picker.Pick> input) {
        List<String> codes = new ArrayList<>();
        for (Picker.Pick pick : input)
            codes.add(pick.station.code);
        return String.join(",", codes);
    }
    static void iterations(List<String> out, Locator.Run run) {
        for (Locator.Iteration row : run.trace)
            out.add(solutionLine("ITER " + row.number(), row.solution(), row.rms()));
    }
    static void pass(List<String> out, int number, List<Picker.Pick> input, Locator.Run run) {
        out.add("PASS " + number + " stations=" + codes(input));
        out.add(solutionLine("GRID", run.grid.solution(), run.grid.rms()));
        List<String> profile = new ArrayList<>();
        for (double value : run.grid.profile())
            profile.add(decimal(value, 4));
        out.add("PROFILE " + String.join(" ", profile));
        iterations(out, run);
        for (int i = 0; i < input.size(); i++) {
            Picker.Pick pick = input.get(i);
            double distance = Locator.distance(run.solution, pick.station);
            out.add("RES " + pick.station.code + " dist=" + decimal(distance, 1) +
                    " tt=" + decimal(distance / params.get("velocity"), 4) + " obs=" + time(pick.sample) +
                    " res=" + decimal(run.residuals[i], 4));
        }
    }
    static List<String> locationReport() {
        List<String> out = new ArrayList<>();
        for (Associator.Candidate candidate : candidates) {
            out.add("CANDIDATE " + candidate.number + " picks=" + candidate.picks.size() +
                    " first=" + time(candidate.first.sample));
            pass(out, 1, candidate.picks, candidate.passes.get(0));
            for (Picker.Pick pick : candidate.dropped) {
                int i = candidate.picks.indexOf(pick);
                out.add("DROP " + pick.station.code +
                        " res=" + decimal(candidate.passes.get(0).residuals[i], 4));
            }
            if (candidate.rejected)
                out.add("RESULT REJECTED stations=" + (candidate.picks.size() - candidate.dropped.size()));
            else {
                if (candidate.passes.size() == 2)
                    pass(out, 2, candidate.event.used, candidate.passes.get(1));
                out.add("RESULT EVENT " + candidate.event.number);
            }
        }
        out.add("CORRECTIONS");
        for (WaveformIo.Station station : stations)
            out.add(station.code + " n=" + used(station).size() +
                    " correction=" + decimal(station.correction, 4));
        for (Event event : events) {
            out.add("EVENT " + event.number);
            out.add(solutionLine("START", event.first.solution, event.startRms));
            iterations(out, event.relocated);
            for (Picker.Pick pick : event.used) {
                double distance = Locator.distance(event.solution(), pick.station);
                out.add("RES " + pick.station.code + " dist=" + decimal(distance, 1) +
                        " tt=" + decimal(distance / params.get("velocity"), 4) + " obs=" + time(pick.sample) +
                        " corr=" + decimal(pick.station.correction, 4) + " res=" + decimal(pick.residual, 4));
            }
            Locator.Ellipse e = event.ellipse;
            out.add("ELLIPSE smaj=" + decimal(e.smaj(), 1) + " smin=" + decimal(e.smin(), 1) + " az=" +
                    decimal(e.az(), 1) + " erz=" + decimal(e.erz(), 1) + " ert=" + decimal(e.ert(), 4));
            out.add("SHIFT dh=" + decimal(event.dh, 1) + " dz=" + decimal(event.dz, 1));
            out.add("GAP " + decimal(event.gap, 1) + " DMIN " + decimal(event.dmin, 1) + " QUALITY " +
                    event.quality);
            for (Jack jack : event.jack)
                out.add("JACK " + jack.station().code + " dx=" + decimal(jack.dx(), 1) +
                        " dy=" + decimal(jack.dy(), 1) + " dz=" + decimal(jack.dz(), 1) +
                        " shift=" + decimal(jack.shift(), 1));
            out.add("JACKKNIFE max=" + decimal(event.maximum.shift(), 1) +
                    " station=" + event.maximum.station().code);
        }
        List<double[]> points = new ArrayList<>();
        double sd = 0, st = 0, sdd = 0, sdt = 0;
        for (Event event : events)
            for (Picker.Pick pick : event.used) {
                double d = Locator.distance(event.solution(), pick.station) / 1000,
                       t = pick.time() - event.solution()[3];
                points.add(new double[] {d, t});
                sd += d;
                st += t;
                sdd += d * d;
                sdt += d * t;
            }
        int n = points.size();
        double slope = (n * sdt - sd * st) / (n * sdd - sd * sd), intercept = (st - slope * sd) / n, sum = 0;
        for (double[] point : points)
            sum += Locator.sq(point[1] - intercept - slope * point[0]);
        out.add("FIT n=" + n + " velocity=" + decimal(1000 / slope, 1) +
                " intercept=" + decimal(intercept, 4) + " rms=" + decimal(Math.sqrt(sum / n), 4));
        for (int c = 0; c < clusters.size(); c++) {
            List<Event> members = clusters.get(c);
            if (members.size() < 2)
                continue;
            double[] center = new double[3];
            double low = Double.POSITIVE_INFINITY, high = Double.NEGATIVE_INFINITY;
            List<String> numbers = new ArrayList<>();
            for (Event event : members) {
                numbers.add(Integer.toString(event.number));
                for (int a = 0; a < 3; a++)
                    center[a] += event.solution()[a];
                low = Math.min(low, event.solution()[3]);
                high = Math.max(high, event.solution()[3]);
            }
            out.add("CLUSTER " + (c + 1) + " events=" + String.join(",", numbers) + " x=" +
                    decimal(center[0] / members.size(), 1) + " y=" + decimal(center[1] / members.size(), 1) +
                    " z=" + decimal(center[2] / members.size(), 1) + " span=" + decimal(high - low, 3));
        }
        out.add("ADDED");
        int unassociated = 0;
        for (Picker.Pick pick : picks) {
            if (pick.state.equals("added"))
                out.add(pick.station.code + " sample=" + pick.sample + " event=" + pick.event +
                        " res=" + decimal(pick.residual, 4));
            if (pick.state.equals("unassociated"))
                unassociated++;
        }
        int rejected = 0;
        for (Associator.Candidate candidate : candidates)
            if (candidate.rejected)
                rejected++;
        out.add("SUMMARY picks=" + picks.size() + " candidates=" + candidates.size() +
                " events=" + events.size() + " rejected=" + rejected + " unassociated=" + unassociated);
        List<Double> depths = new ArrayList<>();
        int[] qualities = new int[3];
        sum = 0;
        for (Event event : events) {
            depths.add(event.solution()[2]);
            qualities[event.quality.charAt(0) - 'A']++;
            sum += event.relocated.rms;
        }
        out.add("DEPTH min=" + decimal(Collections.min(depths), 1) + " median=" +
                decimal(Magnitude.median(depths), 1) + " max=" + decimal(Collections.max(depths), 1));
        out.add("QUALITY A=" + qualities[0] + " B=" + qualities[1] + " C=" + qualities[2] +
                " mean_rms=" + decimal(sum / events.size(), 4));
        return out;
    }
    static List<String> catalog() {
        List<String> out = new ArrayList<>(List.of(
            "event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster"));
        for (Event event : events) {
            double[] s = event.solution();
            Locator.Ellipse e = event.ellipse;
            out.add(event.number + "," + decimal(s[3], 3) + "," + decimal(s[0], 1) + "," + decimal(s[1], 1) +
                    "," + decimal(s[2], 1) + "," + decimal(event.relocated.rms, 4) + "," + event.used.size() +
                    "," + decimal(event.gap, 1) + "," + decimal(event.dmin, 1) + "," + decimal(e.smaj(), 1) +
                    "," + decimal(e.smin(), 1) + "," + decimal(e.az(), 1) + "," + decimal(e.erz(), 1) + "," +
                    magnitude(event.ml) + "," + decimal(event.md, 2) + "," + event.quality + "," +
                    event.cluster);
        }
        return out;
    }
    static List<String> stationReport() {
        List<String> out = new ArrayList<>();
        for (WaveformIo.Station s : stations) {
            out.add("STATION " + s.code + " x=" + s.x + " y=" + s.y + " elevation=" + s.elevation);
            out.add("SAMPLES start=" + s.start + " count=" + s.samples.length + " mean=" + s.mean +
                    " noise=" + decimal(s.noise, 1) + " peak=" + s.peak + " clipped=" + s.clipped);
            out.add("TRIGGERS total=" + s.triggers + " short=" + s.shortTriggers +
                    " picks=" + s.picks.size());
            Map<String, Integer> counts = new HashMap<>();
            for (Picker.Pick pick : s.picks)
                counts.put(pick.state, counts.getOrDefault(pick.state, 0) + 1);
            String line = "PICKS";
            for (String state : List.of("used", "dropped", "added", "rejected", "unassociated"))
                line += " " + state + "=" + counts.getOrDefault(state, 0);
            out.add(line);
            List<Picker.Pick> used = used(s);
            double before = 0, after = 0;
            int nm = 0;
            for (Picker.Pick pick : used) {
                before += pick.firstResidual * pick.firstResidual;
                after += pick.residual * pick.residual;
                if (!pick.clipped)
                    nm++;
            }
            out.add("RESIDUALS n=" + used.size() +
                    " rms=" + (used.isEmpty() ? "-" : decimal(Math.sqrt(before / used.size()), 4)) +
                    " correction=" + decimal(s.correction, 4) +
                    " after=" + (used.isEmpty() ? "-" : decimal(Math.sqrt(after / used.size()), 4)));
            out.add("MAGNITUDES n=" + nm + " correction=" + decimal(s.magnitudeCorrection, 2));
        }
        return out;
    }

    static char[][] canvas(int width, int height) {
        char[][] result = new char[height][width];
        for (char[] row : result)
            Arrays.fill(row, ' ');
        return result;
    }
    static void frame(List<String> out, char[][] grid) {
        String edge = "+"
                      + "-".repeat(grid[0].length) + "+";
        out.add(edge);
        for (char[] row : grid)
            out.add("|" + new String(row) + "|");
        out.add(edge);
    }
    static List<String> magnitudeReport() {
        List<String> out = new ArrayList<>();
        List<Double> magnitudes = new ArrayList<>();
        for (Event event : events) {
            int count = 0;
            for (Magnitude.Values value : event.magnitudes)
                if (value.ml() != null)
                    count++;
            out.add("EVENT " + event.number + " ML=" + magnitude(event.ml) + " n=" + count +
                    " MD=" + decimal(event.md, 2));
            for (int i = 0; i < event.used.size(); i++) {
                Picker.Pick pick = event.used.get(i);
                Magnitude.Values value = event.magnitudes.get(i);
                out.add(pick.station.code + " r=" + decimal(value.distance(), 3) + " amp=" + pick.amplitude +
                        (pick.clipped ? " clipped"
                                      : " ml=" + decimal(value.ml(), 2) +
                                            " res=" + decimal(value.ml() - event.ml, 2)) +
                        " dur=" + pick.duration + " md=" + decimal(value.md(), 2));
            }
            if (event.ml != null)
                magnitudes.add(event.ml);
        }
        out.add("CORRECTED");
        for (Event event : events)
            out.add("EVENT " + event.number + " MLC=" + magnitude(event.mlc));
        Magnitude.Frequency frequency = Magnitude.frequency(magnitudes);
        out.add("FMD");
        for (int t = frequency.counts().firstKey(); t <= frequency.counts().lastKey(); t++) {
            int cumulative = 0;
            for (int key : frequency.counts().keySet())
                if (key >= t)
                    cumulative += frequency.counts().get(key);
            out.add("M=" + Magnitude.classText(t) + " N=" + frequency.counts().getOrDefault(t, 0) +
                    " CUM=" + cumulative);
        }
        out.add("MC " + Magnitude.classText(frequency.completeness()));
        out.add("BVALUE " + decimal(frequency.b(), 3) + " SIGMA " + decimal(frequency.sigma(), 3) + " N " +
                frequency.nb());
        out.add("AVALUE " + decimal(frequency.a(), 3));
        List<Double> x = new ArrayList<>(), y = new ArrayList<>();
        double sx = 0, sy = 0;
        for (Event event : events)
            if (event.ml != null) {
                x.add(event.md);
                y.add(event.ml);
                sx += event.md;
                sy += event.ml;
            }
        int n = x.size();
        double xm = sx / n, ym = sy / n, xx = 0, xy = 0, yy = 0;
        for (int i = 0; i < n; i++) {
            xx += (x.get(i) - xm) * (x.get(i) - xm);
            xy += (x.get(i) - xm) * (y.get(i) - ym);
            yy += (y.get(i) - ym) * (y.get(i) - ym);
        }
        double slope = xy / xx;
        out.add("MLMD n=" + n + " slope=" + decimal(slope, 3) + " intercept=" + decimal(ym - slope * xm, 3) +
                " r=" + decimal(xy / Math.sqrt(xx * yy), 3) + " mean_diff=" + decimal(ym - xm, 3));
        double[] v = params.row("timeline");
        int duration = (int)v[0], width = (int)v[1], low = (int)v[2], high = (int)v[3], height = (int)v[4];
        char[][] grid = canvas(width, height);
        for (Event event : events) {
            if (event.ml == null)
                continue;
            long t = Magnitude.rounded(event.solution()[3], 3), h = Magnitude.rounded(event.ml, 2);
            if (t < 0 || t >= 1000L * duration || h < 100L * low)
                continue;
            int col = (int)(t * width / (1000L * duration)),
                level = (int)Math.min((h - 100L * low) * height / (100L * (high - low)), height - 1);
            for (int k = 0; k <= level; k++) {
                int row = height - 1 - k;
                if (k == level)
                    grid[row][col] = 'o';
                else if (grid[row][col] == ' ')
                    grid[row][col] = '|';
            }
        }
        out.add("TIMELINE t=0.." + duration + " ML=" + low + ".." + high);
        frame(out, grid);
        return out;
    }
    static int[] position(long x, long y, long z, int chart) {
        double[] a = params.row("map_area"), size = params.row("map_size"), section = params.row("section");
        long xmin = (long)a[0], xmax = (long)a[1], ymin = (long)a[2], ymax = (long)a[3];
        int width = (int)size[0], height = (int)size[1], sh = (int)section[1];
        long zmax = (long)section[0];
        if (chart == 0) {
            if (x < 10 * xmin || x >= 10 * xmax || y < 10 * ymin || y >= 10 * ymax)
                return null;
            return new int[] {(int)((x - 10 * xmin) * width / (10 * (xmax - xmin))),
                              height - 1 - (int)((y - 10 * ymin) * height / (10 * (ymax - ymin)))};
        }
        if (z >= 10 * zmax)
            return null;
        long value = chart == 1 ? x : y, lo = chart == 1 ? xmin : ymin, hi = chart == 1 ? xmax : ymax;
        if (value < 10 * lo || value >= 10 * hi)
            return null;
        return new int[] {(int)((value - 10 * lo) * width / (10 * (hi - lo))), (int)(z * sh / (10 * zmax))};
    }
    static String positionText(int[] point) {
        return point == null ? "outside" : point[0] + "," + point[1];
    }
    static char symbol(Event event) {
        if (event.ml == null)
            return '?';
        long h = Magnitude.rounded(event.ml, 2);
        return h < 100 ? '.' : h < 200 ? 'o' : h < 300 ? 'O' : '@';
    }
    static void place(char[][] grid, int[] point, char symbol) {
        if (point == null)
            return;
        String priority = " ?.oO@^";
        if (priority.indexOf(symbol) > priority.indexOf(grid[point[1]][point[0]]))
            grid[point[1]][point[0]] = symbol;
    }
    static List<String> mapReport() {
        int width = (int)params.row("map_size")[0], height = (int)params.row("map_size")[1],
            sectionHeight = (int)params.row("section")[1];
        List<char[][]> charts =
            List.of(canvas(width, height), canvas(width, sectionHeight), canvas(width, sectionHeight));
        List<int[][]> positions = new ArrayList<>();
        for (Event event : events) {
            long x = Magnitude.rounded(event.solution()[0], 1), y = Magnitude.rounded(event.solution()[1], 1),
                 z = Magnitude.rounded(event.solution()[2], 1);
            int[][] pos = new int[3][];
            for (int chart = 0; chart < 3; chart++) {
                pos[chart] = position(x, y, z, chart);
                place(charts.get(chart), pos[chart], symbol(event));
            }
            positions.add(pos);
        }
        List<int[]> stationPositions = new ArrayList<>();
        for (WaveformIo.Station station : stations) {
            int[] pos = position(10L * station.x, 10L * station.y, 0, 0);
            stationPositions.add(pos);
            place(charts.get(0), pos, '^');
        }
        double[] a = params.row("map_area");
        long xmin = (long)a[0], xmax = (long)a[1], ymin = (long)a[2], ymax = (long)a[3],
             zmax = (long)params.row("section")[0];
        List<String> out = new ArrayList<>();
        out.add("MAP x=" + xmin + ".." + xmax + " y=" + ymin + ".." + ymax);
        frame(out, charts.get(0));
        out.add("SECTION EW x=" + xmin + ".." + xmax + " z=0.." + zmax);
        frame(out, charts.get(1));
        out.add("SECTION NS y=" + ymin + ".." + ymax + " z=0.." + zmax);
        frame(out, charts.get(2));
        out.add("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML");
        for (int i = 0; i < stations.size(); i++)
            out.add("STATION " + stations.get(i).code + " map=" + positionText(stationPositions.get(i)));
        for (int i = 0; i < events.size(); i++) {
            Event event = events.get(i);
            int[][] pos = positions.get(i);
            out.add("EVENT " + event.number + " " + symbol(event) + " map=" + positionText(pos[0]) +
                    " ew=" + positionText(pos[1]) + " ns=" + positionText(pos[2]));
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        WaveformIo.Data data = WaveformIo.read();
        stations = data.stations();
        params = data.params();
        for (WaveformIo.Station station : stations)
            picks.addAll(Picker.detect(station, params));
        picks.sort(
            Comparator.comparingInt((Picker.Pick p) -> p.sample).thenComparingInt(p -> p.station.order));
        candidates =
            Associator.associate(picks, params.integer("association_window"), params.integer("min_stations"));
        locate();
        relocate();
        magnitudes();
        cluster();
        reassociate();
        write("picks.csv", picksReport());
        write("locations.txt", locationReport());
        write("catalog.csv", catalog());
        write("magnitudes.txt", magnitudeReport());
        write("stations.txt", stationReport());
        write("map.txt", mapReport());
    }
}
