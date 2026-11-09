import java.util.*;
public class Main {
    static final double PI = 3.141592653589793;
    static FlightPlans.Settings settings;
    static Map<String, FlightPlans.AircraftType> types;
    static List<FlightPlans.Sector> sectors;
    static TreeMap<String, FlightPlans.Plan> initial, finalPlans;
    static TreeMap<String, Trajectory.Built> trajectoriesInitial = new TreeMap<>(),
                                             trajectoriesFinal = new TreeMap<>();
    static List<Conflict.Event> initialConflicts, finalConflicts;
    static Set<Conflict.Pair> unresolved = new HashSet<>(), resolved = new HashSet<>();
    static List<Conflict.Event> unresolvedConflicts = new ArrayList<>();
    static List<Round> rounds = new ArrayList<>();
    static List<Integer> samples = new ArrayList<>();
    static final class Trial {
        String aircraft, name, status;
        Conflict.Event blocker;
        Trial(String aircraft, String name) {
            this.aircraft = aircraft;
            this.name = name;
        }
    }
    static final class Round {
        int number;
        Conflict.Event target;
        List<Trial> trials = new ArrayList<>();
        Trial accepted;
        Round(int number, Conflict.Event target) {
            this.number = number;
            this.target = target;
        }
    }
    record Involvement(Conflict.Event conflict, String partner) {}
    record Interval(double lo, double hi) {}
    static final class Transit {
        String callsign, previous = "-", next = "-";
        int sector, previousIndex = -1, nextIndex = -1;
        double entry, exit;
        Transit(String callsign, int sector, double entry, double exit) {
            this.callsign = callsign;
            this.sector = sector;
            this.entry = entry;
            this.exit = exit;
        }
    }
    record Period(int sector, int number, int start, int end, int entriesInitial, int entriesFinal,
                  int peakInitial, int peakFinal, double meanFinal, String status) {}
    static final class Usage {
        Set<String> flights = new HashSet<>();
        double time;
    }
    record Observation(int time, double loss, double distance) {}
    static final class Alert {
        Conflict.Pair pair;
        int first, last, count;
        double predicted, minimum;
        Double lead;
        Alert(Conflict.Pair pair, Observation observation) {
            this.pair = pair;
            first = last = observation.time();
            count = 1;
            predicted = observation.loss();
            minimum = observation.distance();
        }
    }
    record Cell(int column, int row) {}
    record RadarPosition(Trajectory.Vec position, Trajectory.Segment segment, Cell cell) {}
    static String f(double value) { return Report.decimal(value); }
    static String f(double value, int digits) { return Report.decimal(value, digits); }
    static <K> void add(Map<K, Integer> counts, K key) { counts.merge(key, 1, Integer::sum); }
    static boolean active(Conflict.Event conflict, double time) {
        return conflict.start <= time && time < conflict.end;
    }
    static List<Conflict.Event> activeConflicts(List<Conflict.Event> conflicts, double time) {
        List<Conflict.Event> result = new ArrayList<>();
        for (Conflict.Event conflict : conflicts)
            if (active(conflict, time))
                result.add(conflict);
        return result;
    }
    static TreeMap<String, List<Involvement>> involvement(List<Conflict.Event> conflicts) {
        TreeMap<String, List<Involvement>> result = new TreeMap<>();
        for (Conflict.Event conflict : conflicts) {
            result.computeIfAbsent(conflict.pair.first(), key -> new ArrayList<>())
                .add(new Involvement(conflict, conflict.pair.second()));
            result.computeIfAbsent(conflict.pair.second(), key -> new ArrayList<>())
                .add(new Involvement(conflict, conflict.pair.first()));
        }
        return result;
    }
    static Conflict.Event blocker(String changed, Trajectory.Built trajectory, String partner,
                                  double start) {
        Conflict.Event first = null;
        for (String other : trajectoriesFinal.keySet()) {
            if (other.equals(changed))
                continue;
            Conflict.Pair pair = Conflict.Pair.of(changed, other);
            if (unresolved.contains(pair))
                continue;
            Trajectory.Built a = pair.first().equals(changed) ? trajectory
                                                              : trajectoriesFinal.get(pair.first()),
                             b = pair.second().equals(changed)
                                     ? trajectory
                                     : trajectoriesFinal.get(pair.second());
            for (Conflict.Event conflict :
                 Conflict.pair(pair.first(), a, pair.second(), b, settings.dh(), settings.dv()))
                if (other.equals(partner) || conflict.start < start + settings.lookahead())
                    if (first == null || Conflict.ORDER.compare(conflict, first) < 0)
                        first = conflict;
        }
        return first;
    }
    static void resolve() {
        finalPlans = new TreeMap<>();
        for (var entry : initial.entrySet()) {
            FlightPlans.Plan copy = entry.getValue().copy();
            finalPlans.put(entry.getKey(), copy);
            trajectoriesFinal.put(entry.getKey(), Trajectory.build(copy, types));
        }
        List<Resolution.Manoeuvre> manoeuvres = Resolution.manoeuvres(settings.maxDelay());
        while (true) {
            Conflict.Event target = null;
            for (Conflict.Event conflict :
                 Conflict.all(trajectoriesFinal, settings.dh(), settings.dv()))
                if (!unresolved.contains(conflict.pair)) {
                    target = conflict;
                    break;
                }
            if (target == null)
                break;
            Round round = new Round(rounds.size() + 1, target);
            String[] priority = Resolution.priority(finalPlans.get(target.pair.first()),
                                                    finalPlans.get(target.pair.second()));
            for (int side = 0; side < 2 && round.accepted == null; side++) {
                String aircraft = priority[side], partner = priority[1 - side];
                for (Resolution.Manoeuvre manoeuvre : manoeuvres) {
                    Trial trial = new Trial(aircraft, manoeuvre.name());
                    FlightPlans.Plan proposal =
                        Resolution.propose(finalPlans.get(aircraft), manoeuvre, types, settings);
                    if (proposal == null)
                        trial.status = "infeasible";
                    else {
                        Trajectory.Built trajectory = Trajectory.build(proposal, types);
                        Conflict.Event blocker =
                            blocker(aircraft, trajectory, partner, target.start);
                        if (blocker != null) {
                            trial.status = "blocked";
                            trial.blocker = blocker;
                        } else {
                            trial.status = "accepted";
                            proposal.history.add(manoeuvre.name());
                            finalPlans.put(aircraft, proposal);
                            trajectoriesFinal.put(aircraft, trajectory);
                            round.accepted = trial;
                        }
                    }
                    round.trials.add(trial);
                    if (round.accepted != null)
                        break;
                }
            }
            if (round.accepted == null) {
                unresolved.add(target.pair);
                unresolvedConflicts.add(target);
            } else
                resolved.add(target.pair);
            rounds.add(round);
        }
    }
    static double track(Trajectory.Segment segment) {
        double angle = Math.atan2(segment.velocity().x(), segment.velocity().y()) * 180 / PI;
        return angle < 0 ? angle + 360 : angle;
    }
    static boolean contains(FlightPlans.Sector sector, Trajectory.Vec point) {
        return sector.x1() / 10.0 <= point.x() && point.x() < sector.x2() / 10.0 &&
            sector.y1() / 10.0 <= point.y() && point.y() < sector.y2() / 10.0 &&
            sector.lower() * 100.0 <= point.z() && point.z() < sector.upper() * 100.0;
    }
    static void classify(List<Conflict.Event> conflicts, Set<Conflict.Pair> finalPairs,
                         boolean last) {
        for (Conflict.Event conflict : conflicts) {
            Conflict.Piece piece = conflict.closest;
            Trajectory.Segment a = piece.a(), b = piece.b();
            Trajectory.Vec pa = Trajectory.position(a, piece.loss().tc()),
                           pb = Trajectory.position(b, piece.loss().tc());
            conflict.levelA = pa.z() / 100;
            conflict.levelB = pb.z() / 100;
            conflict.trackA = track(a);
            conflict.trackB = track(b);
            double angle = Math.abs(conflict.trackA - conflict.trackB);
            conflict.angle = angle > 180 ? 360 - angle : angle;
            double dot = a.velocity().x() * b.velocity().x() + a.velocity().y() * b.velocity().y(),
                   cross =
                       a.velocity().x() * b.velocity().y() - a.velocity().y() * b.velocity().x();
            conflict.geometry =
                dot * dot > cross * cross ? (dot < 0 ? "head_on" : "trailing") : "crossing";
            double distance = piece.loss().distance();
            conflict.severity = 10 * distance < 4.0 * settings.dh()   ? "HIGH"
                                : 10 * distance < 7.0 * settings.dh() ? "MEDIUM"
                                                                    : "LOW";
            Trajectory.Vec midpoint = new Trajectory.Vec(
                (pa.x() + pb.x()) / 2, (pa.y() + pb.y()) / 2, (pa.z() + pb.z()) / 2);
            conflict.sector = "-";
            for (FlightPlans.Sector sector : sectors)
                if (contains(sector, midpoint)) {
                    conflict.sector = sector.name();
                    break;
                }
            conflict.outcome = last || finalPairs.contains(conflict.pair) ? "remaining"
                               : resolved.contains(conflict.pair)         ? "resolved"
                                                                          : "indirect";
        }
    }
    static List<String> trajectoriesCsv() {
        List<String> lines = new ArrayList<>();
        lines.add(
            "callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end");
        for (var entry : trajectoriesFinal.entrySet())
            for (Trajectory.Segment segment : entry.getValue().segments()) {
                Trajectory.Vec a = segment.start(), b = segment.end();
                lines.add(entry.getKey() + "," + segment.number() + "," + segment.leg() + "," +
                          segment.phase() + "," + f(segment.ts()) + "," + f(segment.te()) + "," +
                          f(a.x()) + "," + f(a.y()) + "," + (int)(a.z() / 100) + "," + f(b.x()) +
                          "," + f(b.y()) + "," + (int)(b.z() / 100));
            }
        return lines;
    }
    static List<String> conflictLines(String label, List<Conflict.Event> conflicts,
                                      Map<String, Trajectory.Built> trajectories) {
        List<String> lines = new ArrayList<>();
        lines.add("CONFLICTS plan=" + label + " count=" + conflicts.size());
        Map<String, Integer> geometry = new HashMap<>(), severity = new HashMap<>();
        double duration = 0, minimum = Double.POSITIVE_INFINITY;
        for (int i = 0; i < conflicts.size(); i++) {
            Conflict.Event conflict = conflicts.get(i);
            Conflict.Piece piece = conflict.closest;
            Conflict.Loss loss = piece.loss();
            lines.add("CONFLICT " + (i + 1) + " " + conflict.pair.name() +
                      " start=" + f(conflict.start) + " end=" + f(conflict.end) + " duration=" +
                      f(conflict.end - conflict.start) + " outcome=" + conflict.outcome);
            lines.add("  CPA t=" + f(loss.tc()) + " dist=" + f(loss.distance()) +
                      " vert=" + f(loss.vertical(), 1) + " levels=" + f(conflict.levelA, 2) + "/" +
                      f(conflict.levelB, 2) + " tracks=" + f(conflict.trackA, 1) + "/" +
                      f(conflict.trackB, 1) + " angle=" + f(conflict.angle, 1));
            lines.add("  TYPE geometry=" + conflict.geometry + " phases=" + piece.a().phase() +
                      "/" + piece.b().phase() + " segments=" + piece.a().number() + "/" +
                      piece.b().number() + " sector=" + conflict.sector +
                      " severity=" + conflict.severity);
            for (Conflict.Piece part : conflict.pieces)
                lines.add("  PIECE " + part.a().number() + "/" + part.b().number() + " " +
                          f(part.loss().lo()) + " " + f(part.loss().hi()));
            add(geometry, conflict.geometry);
            add(severity, conflict.severity);
            duration += conflict.end - conflict.start;
            minimum = Math.min(minimum, loss.distance());
        }
        lines.add("SUMMARY count=" + conflicts.size() + " total=" + f(duration) +
                  " min_dist=" + (conflicts.isEmpty() ? "-" : f(minimum)) +
                  " head_on=" + geometry.getOrDefault("head_on", 0) +
                  " crossing=" + geometry.getOrDefault("crossing", 0) +
                  " trailing=" + geometry.getOrDefault("trailing", 0) +
                  " high=" + severity.getOrDefault("HIGH", 0) + " medium=" +
                  severity.getOrDefault("MEDIUM", 0) + " low=" + severity.getOrDefault("LOW", 0));
        TreeMap<String, List<Involvement>> involved = involvement(conflicts);
        for (var entry : involved.entrySet()) {
            TreeSet<String> partners = new TreeSet<>();
            double first = Double.POSITIVE_INFINITY;
            for (Involvement item : entry.getValue()) {
                partners.add(item.partner());
                first = Math.min(first, item.conflict().start);
            }
            lines.add("FLIGHT " + entry.getKey() + " conflicts=" + entry.getValue().size() +
                      " first=" + f(first) + " partners=" + String.join(",", partners));
        }
        lines.add("TIMELINE from=" + settings.sampleStart() + " to=" + settings.sampleEnd() +
                  " step=60");
        for (var entry : involved.entrySet()) {
            StringBuilder timeline = new StringBuilder();
            for (int time : samples) {
                if (Trajectory.active(trajectories.get(entry.getKey()), time) == null)
                    timeline.append('.');
                else {
                    boolean conflict = false;
                    for (Involvement item : entry.getValue())
                        if (active(item.conflict(), time))
                            conflict = true;
                    timeline.append(conflict ? 'X' : '-');
                }
            }
            lines.add(entry.getKey() + " " + timeline);
        }
        return lines;
    }
    static List<String> resolutionLines() {
        List<String> lines = new ArrayList<>();
        int trialCount = 0, infeasible = 0, blocked = 0, accepted = 0, level = 0, speed = 0,
            delay = 0;
        for (Round round : rounds) {
            Conflict.Event target = round.target;
            lines.add("ROUND " + round.number + " " + target.pair.name() +
                      " start=" + f(target.start) + " end=" + f(target.end) +
                      " dist=" + f(target.closest.loss().distance()));
            for (Trial trial : round.trials) {
                trialCount++;
                String line = "  TRY " + trial.aircraft + " " + trial.name + " " + trial.status;
                if (trial.status.equals("infeasible"))
                    infeasible++;
                if (trial.status.equals("blocked")) {
                    blocked++;
                    line += " " + trial.blocker.pair.name() + " start=" + f(trial.blocker.start);
                }
                lines.add(line);
            }
            if (round.accepted == null)
                lines.add("  RESULT unresolved");
            else {
                Trial trial = round.accepted;
                accepted++;
                if (trial.name.startsWith("level_"))
                    level++;
                else if (trial.name.equals("speed_down"))
                    speed++;
                else
                    delay++;
                lines.add("  RESULT resolved " + trial.aircraft + " " + trial.name);
            }
        }
        Map<String, List<Involvement>> before = involvement(initialConflicts),
                                       after = involvement(finalConflicts);
        double totalExtra = 0;
        long totalDelay = 0;
        for (String code : finalPlans.keySet()) {
            FlightPlans.Plan old = initial.get(code), plan = finalPlans.get(code);
            Trajectory.Built first = trajectoriesInitial.get(code), last =
                                                                        trajectoriesFinal.get(code);
            double extra = last.arrival() - first.arrival();
            totalExtra += extra;
            totalDelay += plan.delay;
            lines.add("FLIGHT " + code + " departure=" + (plan.departure + plan.delay) + " delay=" +
                      plan.delay + " level=" + Report.signed(plan.offset) + " speed=" + old.speed +
                      "->" + plan.speed + " arrival=" + f(first.arrival()) + "->" +
                      f(last.arrival()) + " extra=" + f(extra) + " length=" + f(last.length()) +
                      " conflicts=" + before.getOrDefault(code, List.of()).size() + "->" +
                      after.getOrDefault(code, List.of()).size() + " manoeuvres=" +
                      (plan.history.isEmpty() ? "-" : String.join(",", plan.history)));
        }
        for (Conflict.Event conflict : unresolvedConflicts)
            lines.add("UNRESOLVED " + conflict.pair.name() + " start=" + f(conflict.start) +
                      " dist=" + f(conflict.closest.loss().distance()));
        lines.add("TOTAL rounds=" + rounds.size() + " resolved=" + accepted +
                  " unresolved=" + unresolvedConflicts.size() + " level=" + level +
                  " speed=" + speed + " delay=" + delay + " total_delay=" + totalDelay +
                  " total_extra=" + f(totalExtra) + " trials=" + trialCount +
                  " infeasible=" + infeasible + " blocked=" + blocked);
        return lines;
    }
    static Interval inside(Trajectory.Segment segment, FlightPlans.Sector sector) {
        double[] low = {sector.x1() / 10.0, sector.y1() / 10.0, sector.lower() * 100.0},
                 high = {sector.x2() / 10.0, sector.y2() / 10.0, sector.upper() * 100.0};
        double lo = segment.ts(), hi = segment.te();
        for (int axis = 0; axis < 3; axis++) {
            double p = segment.start().component(axis), v = segment.velocity().component(axis);
            if (v == 0) {
                if (!(low[axis] <= p && p < high[axis]))
                    return null;
            } else {
                double r1 = (low[axis] - p) / v, r2 = (high[axis] - p) / v;
                lo = Math.max(lo, segment.ts() + Math.min(r1, r2));
                hi = Math.min(hi, segment.ts() + Math.max(r1, r2));
            }
        }
        return hi - lo > 1e-6 ? new Interval(lo, hi) : null;
    }
    static List<Transit> transits(Map<String, Trajectory.Built> trajectories) {
        List<Transit> all = new ArrayList<>();
        for (String code : new TreeSet<>(trajectories.keySet())) {
            List<Transit> flight = new ArrayList<>();
            for (FlightPlans.Sector sector : sectors) {
                List<Interval> combined = new ArrayList<>();
                for (Trajectory.Segment segment : trajectories.get(code).segments()) {
                    Interval interval = inside(segment, sector);
                    if (interval == null)
                        continue;
                    if (!combined.isEmpty() && interval.lo() - combined.getLast().hi() <= 1e-6)
                        combined.set(combined.size() - 1,
                                     new Interval(combined.getLast().lo(), interval.hi()));
                    else
                        combined.add(interval);
                }
                for (Interval interval : combined)
                    flight.add(new Transit(code, sector.index(), interval.lo(), interval.hi()));
            }
            flight.sort(Comparator.comparingDouble((Transit transit) -> transit.entry)
                            .thenComparingInt(transit -> transit.sector));
            for (int i = 0; i + 1 < flight.size(); i++) {
                Transit before = flight.get(i), after = flight.get(i + 1);
                if (Math.abs(after.entry - before.exit) <= 1e-6) {
                    before.next = sectors.get(after.sector).name();
                    before.nextIndex = after.sector;
                    after.previous = sectors.get(before.sector).name();
                    after.previousIndex = before.sector;
                }
            }
            all.addAll(flight);
        }
        return all;
    }
    static List<String> transitLines(List<Transit> transits) {
        List<String> lines = new ArrayList<>();
        lines.add("callsign,sector,entry,exit,duration,from,to");
        for (Transit transit : transits)
            lines.add(transit.callsign + "," + sectors.get(transit.sector).name() + "," +
                      f(transit.entry) + "," + f(transit.exit) + "," +
                      f(transit.exit - transit.entry) + "," + transit.previous + "," +
                      transit.next);
        return lines;
    }

    static int[][] occupancy(Map<String, Trajectory.Built> trajectories) {
        int[][] values = new int[sectors.size()][samples.size()];
        for (int j = 0; j < samples.size(); j++)
            for (String code : new TreeSet<>(trajectories.keySet())) {
                Trajectory.Observed observed =
                    Trajectory.current(trajectories.get(code), samples.get(j));
                if (observed == null)
                    continue;
                for (FlightPlans.Sector sector : sectors)
                    if (contains(sector, observed.position()))
                        values[sector.index()][j]++;
            }
        return values;
    }
    static List<Period> periods(int[][] before, int[][] after, List<Transit> first,
                                List<Transit> last) {
        List<Period> result = new ArrayList<>();
        for (FlightPlans.Sector sector : sectors)
            for (int j = 0; j < samples.size(); j += 5) {
                int start = samples.get(j), end = start + 300, peakInitial = 0, peakFinal = 0,
                    sum = 0, entriesInitial = 0, entriesFinal = 0;
                for (int k = j; k < j + 5; k++) {
                    peakInitial = Math.max(peakInitial, before[sector.index()][k]);
                    peakFinal = Math.max(peakFinal, after[sector.index()][k]);
                    sum += after[sector.index()][k];
                }
                for (Transit transit : first)
                    if (transit.sector == sector.index() && start <= transit.entry &&
                        transit.entry < end)
                        entriesInitial++;
                for (Transit transit : last)
                    if (transit.sector == sector.index() && start <= transit.entry &&
                        transit.entry < end)
                        entriesFinal++;
                String status = peakFinal > sector.capacity()     ? "OVER"
                                : peakInitial > sector.capacity() ? "RELIEVED"
                                                                  : "OK";
                result.add(new Period(sector.index(), j / 5 + 1, start, end, entriesInitial,
                                      entriesFinal, peakInitial, peakFinal, sum / 5.0, status));
            }
        return result;
    }
    static List<String> sectorLoad(List<Period> periods) {
        List<String> lines = new ArrayList<>();
        lines.add(
            "sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status");
        for (Period period : periods) {
            FlightPlans.Sector sector = sectors.get(period.sector());
            lines.add(sector.name() + "," + period.number() + "," + period.start() + "," +
                      period.end() + "," + period.entriesInitial() + "," + period.entriesFinal() +
                      "," + period.peakInitial() + "," + period.peakFinal() + "," +
                      f(period.meanFinal(), 1) + "," + sector.capacity() + "," + period.status());
        }
        return lines;
    }
    static TreeMap<Integer, Usage> levelUsage(Map<String, Trajectory.Built> trajectories) {
        TreeMap<Integer, Usage> result = new TreeMap<>(Comparator.reverseOrder());
        for (String code : new TreeSet<>(trajectories.keySet()))
            for (Trajectory.Segment segment : trajectories.get(code).segments())
                if (segment.phase().equals("LVL")) {
                    int level = (int)(segment.start().z() / 100);
                    Usage usage = result.computeIfAbsent(level, key -> new Usage());
                    usage.flights.add(code);
                    usage.time += segment.te() - segment.ts();
                }
        return result;
    }
    static String sectorSummary(String label, int index, int[][] occupancy, List<Transit> transits,
                                List<Conflict.Event> conflicts) {
        int entries = 0, peak = 0, over = 0, count = 0;
        double dwell = 0;
        for (Transit transit : transits)
            if (transit.sector == index) {
                entries++;
                dwell += transit.exit - transit.entry;
            }
        for (int j = 0; j < samples.size(); j += 5) {
            int periodPeak = 0;
            for (int k = j; k < j + 5; k++)
                periodPeak = Math.max(periodPeak, occupancy[index][k]);
            peak = Math.max(peak, periodPeak);
            if (periodPeak > sectors.get(index).capacity())
                over++;
        }
        for (Conflict.Event conflict : conflicts)
            if (conflict.sector.equals(sectors.get(index).name()))
                count++;
        return label + " entries=" + entries + " time=" + f(dwell) +
            " mean=" + (entries == 0 ? "-" : f(dwell / entries)) + " peak=" + peak +
            " over=" + over + " conflicts=" + count;
    }
    static List<String> sectorReport(int[][] before, int[][] after, List<Transit> first,
                                     List<Transit> last) {
        List<String> lines = new ArrayList<>();
        for (FlightPlans.Sector sector : sectors) {
            int index = sector.index();
            lines.add("SECTOR " + sector.name() + " x=" + sector.x1() + ".." + sector.x2() +
                      " y=" + sector.y1() + ".." + sector.y2() + " fl=" + sector.lower() + ".." +
                      sector.upper() + " capacity=" + sector.capacity());
            lines.add(sectorSummary("INITIAL", index, before, first, initialConflicts));
            lines.add(sectorSummary("FINAL", index, after, last, finalConflicts));
            int height = sector.capacity() + 1;
            for (int value : after[index])
                height = Math.max(height, value);
            List<String> rows = new ArrayList<>();
            for (int level = height; level >= 1; level--) {
                StringBuilder row = new StringBuilder();
                for (int value : after[index])
                    row.append(value >= level ? '#' : level == sector.capacity() ? '-' : '.');
                rows.add(row.toString());
            }
            lines.addAll(Report.chart(rows));
        }
        TreeMap<Integer, Usage> initialUsage = levelUsage(trajectoriesInitial),
                                finalUsage = levelUsage(trajectoriesFinal);
        TreeSet<Integer> levels = new TreeSet<>(Comparator.reverseOrder());
        levels.addAll(initialUsage.keySet());
        levels.addAll(finalUsage.keySet());
        lines.add("LEVELS");
        for (int level : levels) {
            Usage old = initialUsage.getOrDefault(level, new Usage()),
                  now = finalUsage.getOrDefault(level, new Usage());
            lines.add("LEVEL " + level + " flights=" + old.flights.size() + "->" +
                      now.flights.size() + " time=" + f(old.time) + "->" + f(now.time));
        }
        int[][] handoffs = new int[sectors.size()][sectors.size()];
        int count = 0;
        for (Transit transit : last)
            if (transit.nextIndex >= 0) {
                handoffs[transit.sector][transit.nextIndex]++;
                count++;
            }
        lines.add("HANDOFFS plan=final count=" + count);
        for (int a = 0; a < sectors.size(); a++)
            for (int b = 0; b < sectors.size(); b++)
                if (handoffs[a][b] > 0)
                    lines.add("HANDOFF " + sectors.get(a).name() + " " + sectors.get(b).name() +
                              " " + handoffs[a][b]);
        return lines;
    }
    static List<String> alertLines(String label, Map<String, Trajectory.Built> trajectories,
                                   List<Conflict.Event> conflicts) {
        Map<Conflict.Pair, List<Observation>> observations = new HashMap<>();
        for (int time : samples) {
            TreeMap<String, Trajectory.Observed> flying = new TreeMap<>();
            for (String code : trajectories.keySet()) {
                Trajectory.Observed observed = Trajectory.current(trajectories.get(code), time);
                if (observed != null)
                    flying.put(code, observed);
            }
            List<String> names = new ArrayList<>(flying.keySet());
            for (int a = 0; a < names.size(); a++)
                for (int b = a + 1; b < names.size(); b++) {
                    String first = names.get(a), second = names.get(b);
                    Trajectory.Observed pa = flying.get(first), pb = flying.get(second);
                    Conflict.Loss loss =
                        Conflict.loss(pa.position().minus(pb.position()),
                                      pa.segment().velocity().minus(pb.segment().velocity()), 0,
                                      settings.alert(), settings.dh(), settings.dv());
                    if (loss != null)
                        observations
                            .computeIfAbsent(new Conflict.Pair(first, second),
                                             key -> new ArrayList<>())
                            .add(new Observation(time, time + loss.lo(), loss.distance()));
                }
        }
        List<Alert> alerts = new ArrayList<>();
        for (var entry : observations.entrySet()) {
            Alert group = null;
            for (Observation observation : entry.getValue()) {
                if (group == null || observation.time() - group.last != 60) {
                    group = new Alert(entry.getKey(), observation);
                    alerts.add(group);
                } else {
                    group.last = observation.time();
                    group.count++;
                    group.minimum = Math.min(group.minimum, observation.distance());
                }
            }
        }
        alerts.sort(Comparator.comparingInt((Alert alert) -> alert.first)
                        .thenComparing(alert -> alert.pair.first())
                        .thenComparing(alert -> alert.pair.second()));
        boolean[] detected = new boolean[conflicts.size()];
        for (Alert alert : alerts)
            for (int i = 0; i < conflicts.size(); i++) {
                Conflict.Event conflict = conflicts.get(i);
                if (conflict.pair.equals(alert.pair) &&
                    conflict.start < alert.last + (double)settings.alert() &&
                    conflict.end > alert.first) {
                    detected[i] = true;
                    if (alert.lead == null)
                        alert.lead = conflict.start - alert.first;
                }
            }
        List<String> lines = new ArrayList<>();
        lines.add("ALERTS plan=" + label + " horizon=" + settings.alert() +
                  " count=" + alerts.size());
        int trueCount = 0, missed = 0;
        double leadSum = 0;
        for (int i = 0; i < alerts.size(); i++) {
            Alert alert = alerts.get(i);
            String status = "status=false lead=-";
            if (alert.lead != null) {
                trueCount++;
                leadSum += alert.lead;
                status = "status=true lead=" + f(alert.lead);
            }
            lines.add("ALERT " + (i + 1) + " " + alert.pair.name() + " first=" + alert.first +
                      " last=" + alert.last + " samples=" + alert.count + " predicted=" +
                      f(alert.predicted) + " min_dist=" + f(alert.minimum) + " " + status);
        }
        for (int i = 0; i < conflicts.size(); i++)
            if (!detected[i]) {
                missed++;
                Conflict.Event conflict = conflicts.get(i);
                lines.add("MISSED " + conflict.pair.name() + " start=" + f(conflict.start) +
                          " end=" + f(conflict.end));
            }
        lines.add("SUMMARY alerts=" + alerts.size() + " true=" + trueCount +
                  " false=" + (alerts.size() - trueCount) + " missed=" + missed +
                  " mean_lead=" + (trueCount == 0 ? "-" : f(leadSum / trueCount)));
        return lines;
    }
    static Cell cell(Trajectory.Vec position) {
        int[] r = settings.radar();
        double column = Math.floor((10 * position.x() - r[0]) * r[4] / (r[2] - r[0])),
               row = Math.floor((10 * position.y() - r[1]) * r[5] / (r[3] - r[1]));
        if (column < 0 || column >= r[4] || row < 0 || row >= r[5])
            return null;
        return new Cell((int)column, r[5] - 1 - (int)row);
    }
    static List<String> gridRows(char[][] grid) {
        List<String> rows = new ArrayList<>();
        for (char[] row : grid)
            rows.add(new String(row));
        return rows;
    }
    static List<String> radarSnapshot(String label, Map<String, Trajectory.Built> trajectories,
                                      List<Conflict.Event> conflicts, int time) {
        int width = settings.radar()[4], height = settings.radar()[5];
        char[][] grid = new char[height][width];
        for (char[] row : grid)
            Arrays.fill(row, '.');
        TreeMap<String, RadarPosition> positions = new TreeMap<>();
        Map<Cell, List<String>> placements = new HashMap<>();
        for (String code : new TreeSet<>(trajectories.keySet())) {
            Trajectory.Observed observed = Trajectory.current(trajectories.get(code), time);
            if (observed == null)
                continue;
            Cell cell = cell(observed.position());
            positions.put(code, new RadarPosition(observed.position(), observed.segment(), cell));
            if (cell != null)
                placements.computeIfAbsent(cell, key -> new ArrayList<>()).add(code);
        }
        List<Conflict.Event> active = activeConflicts(conflicts, time);
        Set<String> conflicted = new HashSet<>();
        for (Conflict.Event conflict : active) {
            conflicted.add(conflict.pair.first());
            conflicted.add(conflict.pair.second());
        }
        for (var entry : placements.entrySet()) {
            List<String> names = entry.getValue();
            String name = names.getFirst();
            char value = names.size() > 1            ? (char)('0' + names.size())
                         : conflicted.contains(name) ? Character.toLowerCase(name.charAt(0))
                                                     : name.charAt(0);
            grid[entry.getKey().row()][entry.getKey().column()] = value;
        }
        for (String code : positions.keySet()) {
            Trajectory.Observed predicted =
                Trajectory.current(trajectories.get(code), time + (double)settings.leader());
            if (predicted == null)
                continue;
            Cell cell = cell(predicted.position());
            if (cell != null && grid[cell.row()][cell.column()] == '.')
                grid[cell.row()][cell.column()] = '*';
        }
        List<String> lines = new ArrayList<>();
        lines.add("RADAR plan=" + label + " t=" + time + " aircraft=" + positions.size() +
                  " conflicts=" + active.size());
        lines.addAll(Report.chart(gridRows(grid)));
        for (var entry : positions.entrySet()) {
            RadarPosition value = entry.getValue();
            Trajectory.Vec p = value.position();
            Cell c = value.cell();
            lines.add(entry.getKey() + " x=" + f(p.x()) + " y=" + f(p.y()) +
                      " fl=" + f(p.z() / 100, 2) + " track=" + f(track(value.segment()), 1) +
                      " phase=" + value.segment().phase() +
                      " cell=" + (c == null ? "outside" : c.column() + "," + c.row()));
        }
        for (Conflict.Event conflict : active) {
            Trajectory.Vec a = positions.get(conflict.pair.first()).position(),
                           b = positions.get(conflict.pair.second()).position();
            double dx = a.x() - b.x(), dy = a.y() - b.y();
            lines.add("CONFLICT " + conflict.pair.name() + " dist=" +
                      f(Math.sqrt(dx * dx + dy * dy)) + " vert=" + f(Math.abs(a.z() - b.z()), 1));
        }
        return lines;
    }
    static List<String> density(String label, Map<String, Trajectory.Built> trajectories) {
        int width = settings.radar()[4], height = settings.radar()[5], maximum = 0;
        int[][] counts = new int[height][width];
        for (int time : samples)
            for (String code : new TreeSet<>(trajectories.keySet())) {
                Trajectory.Observed observed = Trajectory.current(trajectories.get(code), time);
                if (observed == null)
                    continue;
                Cell cell = cell(observed.position());
                if (cell != null)
                    counts[cell.row()][cell.column()]++;
            }
        char[][] grid = new char[height][width];
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++) {
                int count = counts[row][col];
                maximum = Math.max(maximum, count);
                grid[row][col] = count == 0 ? '.' : count < 10 ? (char)('0' + count) : '#';
            }
        List<String> lines = new ArrayList<>();
        lines.add("DENSITY plan=" + label + " from=" + settings.sampleStart() +
                  " to=" + settings.sampleEnd() + " step=60 max=" + maximum);
        lines.addAll(Report.chart(gridRows(grid)));
        return lines;
    }
    static List<String> strips(List<Transit> transits) {
        List<String> lines = new ArrayList<>();
        for (String code : initial.keySet()) {
            FlightPlans.Plan plan = finalPlans.get(code);
            Trajectory.Built before = trajectoriesInitial.get(code),
                             after = trajectoriesFinal.get(code);
            lines.add("STRIP " + code + " type=" + plan.type + " waypoints=" +
                      plan.waypoints.size() + " length=" + f(after.length()) + " manoeuvres=" +
                      (plan.history.isEmpty() ? "-" : String.join(",", plan.history)));
            for (int k = 0; k < plan.waypoints.size(); k++) {
                FlightPlans.Waypoint point = plan.waypoints.get(k);
                Trajectory.Passing old = before.waypointTimes().get(k),
                                   now = after.waypointTimes().get(k);
                lines.add("WPT " + k + " at=" + point.x() + ":" + point.y() +
                          " eta=" + f(old.time()) + "->" + f(now.time()) + " fl=" + old.level() +
                          "->" + now.level());
            }
            List<String> sequence = new ArrayList<>();
            for (Transit transit : transits)
                if (transit.callsign.equals(code))
                    sequence.add(sectors.get(transit.sector).name() + "@" + f(transit.entry));
            lines.add("SECTORS " + (sequence.isEmpty() ? "-" : String.join(",", sequence)));
        }
        return lines;
    }
    public static void main(String[] args) throws Exception {
        FlightPlans.Input input = FlightPlans.read();
        initial = input.plans();
        types = input.types();
        sectors = input.sectors();
        settings = input.settings();
        for (var entry : initial.entrySet())
            trajectoriesInitial.put(entry.getKey(), Trajectory.build(entry.getValue(), types));
        initialConflicts = Conflict.all(trajectoriesInitial, settings.dh(), settings.dv());
        resolve();
        finalConflicts = Conflict.all(trajectoriesFinal, settings.dh(), settings.dv());
        Set<Conflict.Pair> finalPairs = new HashSet<>();
        for (Conflict.Event conflict : finalConflicts)
            finalPairs.add(conflict.pair);
        classify(initialConflicts, finalPairs, false);
        classify(finalConflicts, finalPairs, true);
        for (int time = settings.sampleStart(); time < settings.sampleEnd(); time += 60)
            samples.add(time);
        List<Transit> first = transits(trajectoriesInitial), last = transits(trajectoriesFinal);
        int[][] before = occupancy(trajectoriesInitial), after = occupancy(trajectoriesFinal);
        List<Period> periods = periods(before, after, first, last);
        Report.write("trajectories.csv", trajectoriesCsv());
        List<String> conflicts = conflictLines("initial", initialConflicts, trajectoriesInitial);
        conflicts.addAll(conflictLines("final", finalConflicts, trajectoriesFinal));
        Report.write("conflicts.txt", conflicts);
        Report.write("resolutions.txt", resolutionLines());
        Report.write("sector_transits.csv", transitLines(last));
        Report.write("sector_load.csv", sectorLoad(periods));
        Report.write("sector_report.txt", sectorReport(before, after, first, last));
        List<String> alerts = alertLines("initial", trajectoriesInitial, initialConflicts);
        alerts.addAll(alertLines("final", trajectoriesFinal, finalConflicts));
        Report.write("alerts.txt", alerts);
        List<String> radar = new ArrayList<>();
        for (int time : settings.snapshots()) {
            radar.addAll(radarSnapshot("initial", trajectoriesInitial, initialConflicts, time));
            radar.addAll(radarSnapshot("final", trajectoriesFinal, finalConflicts, time));
        }
        radar.addAll(density("initial", trajectoriesInitial));
        radar.addAll(density("final", trajectoriesFinal));
        Report.write("radar.txt", radar);
        Report.write("strips.txt", strips(last));
    }
}
