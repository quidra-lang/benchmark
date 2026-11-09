using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static readonly double PI = 3.141592653589793;
    public static FlightPlans.Settings settings;
    public static Dictionary<string, FlightPlans.AircraftType> types;
    public static List<FlightPlans.Sector> sectors;
    public static SortedDictionary<string, FlightPlans.Plan> initial, finalPlans;
    public static SortedDictionary<string, Trajectory.Built> trajectoriesInitial =
                                                                  new(StringComparer.Ordinal),
                                                              trajectoriesFinal =
                                                                  new(StringComparer.Ordinal);
    public static List<Conflict.Event> initialConflicts, finalConflicts;
    public static HashSet<Conflict.Pair> unresolved = new(), resolved = new();
    public static List<Conflict.Event> unresolvedConflicts = new();
    public static List<Round> rounds = new();
    public static List<int> samples = new();
    public sealed class Trial {
        public string aircraft, name, status;
        public Conflict.Event blocker;
        public Trial(string aircraft, string name) {
            this.aircraft = aircraft;
            this.name = name;
        }
    }
    public sealed class Round {
        public int number;
        public Conflict.Event target;
        public List<Trial> trials = new();
        public Trial accepted;
        public Round(int number, Conflict.Event target) {
            this.number = number;
            this.target = target;
        }
    }
    public record Involvement(Conflict.Event conflict, string partner) {}
    public record Interval(double lo, double hi) {}
    public sealed class Transit {
        public string callsign, previous = "-", next = "-";
        public int sector, previousIndex = -1, nextIndex = -1;
        public double entry, exit;
        public Transit(string callsign, int sector, double entry, double exit) {
            this.callsign = callsign;
            this.sector = sector;
            this.entry = entry;
            this.exit = exit;
        }
    }
    public record Period(int sector, int number, int start, int end, int entriesInitial,
                         int entriesFinal, int peakInitial, int peakFinal, double meanFinal,
                         string status) {}
    public sealed class Usage {
        public HashSet<string> flights = new();
        public double time;
    }
    public record Observation(int time, double loss, double distance) {}
    public sealed class Alert {
        public Conflict.Pair pair;
        public int first, last, count;
        public double predicted, minimum;
        public double? lead;
        public Alert(Conflict.Pair pair, Observation observation) {
            this.pair = pair;
            first = last = observation.time;
            count = 1;
            predicted = observation.loss;
            minimum = observation.distance;
        }
    }
    public record Cell(int column, int row) {}
    public record RadarPosition(Trajectory.Vec position, Trajectory.Segment segment, Cell cell) {}
    public static string F(double value) { return Report.Decimal(value); }
    public static string F(double value, int digits) { return Report.Decimal(value, digits); }
    public static void Add<K>(Dictionary<K, int> counts, K key) { counts.AddCount(key, 1); }
    public static bool Active(Conflict.Event conflict, double time) {
        return conflict.start <= time && time < conflict.end;
    }
    public static List<Conflict.Event> ActiveConflicts(List<Conflict.Event> conflicts,
                                                       double time) {
        List<Conflict.Event> result = new();
        foreach (Conflict.Event conflict in conflicts)
            if (Active(conflict, time))
                result.Add(conflict);
        return result;
    }
    public static SortedDictionary<string, List<Involvement>>
    InvolvementMap(List<Conflict.Event> conflicts) {
        SortedDictionary<string, List<Involvement>> result = new(StringComparer.Ordinal);
        foreach (Conflict.Event conflict in conflicts) {
            result.GetOrAdd(conflict.pair.first, key => new())
                .Add(new Involvement(conflict, conflict.pair.second));
            result.GetOrAdd(conflict.pair.second, key => new())
                .Add(new Involvement(conflict, conflict.pair.first));
        }
        return result;
    }
    public static Conflict.Event Blocker(string changed, Trajectory.Built trajectory,
                                         string partner, double start) {
        Conflict.Event first = null;
        foreach (string other in trajectoriesFinal.Keys) {
            if (other.Equals(changed))
                continue;
            Conflict.Pair pair = Conflict.Pair.Of(changed, other);
            if (unresolved.Contains(pair))
                continue;
            Trajectory.Built a = pair.first.Equals(changed) ? trajectory
                                                            : trajectoriesFinal[pair.first],
                             b = pair.second.Equals(changed) ? trajectory
                                                             : trajectoriesFinal[pair.second];
            foreach (Conflict.Event conflict in Conflict.FindPair(pair.first, a, pair.second, b,
                                                                  settings.dh, settings.dv))
                if (other.Equals(partner) || conflict.start < start + settings.lookahead)
                    if (first == null || Conflict.ORDER(conflict, first) < 0)
                        first = conflict;
        }
        return first;
    }
    public static void Resolve() {
        finalPlans = new(StringComparer.Ordinal);
        foreach (var entry in initial) {
            FlightPlans.Plan copy = entry.Value.Copy();
            finalPlans[entry.Key] = copy;
            trajectoriesFinal[entry.Key] = Trajectory.Build(copy, types);
        }
        List<Resolution.Manoeuvre> manoeuvres = Resolution.Manoeuvres(settings.maxDelay);
        while (true) {
            Conflict.Event target = null;
            foreach (Conflict.Event conflict in Conflict.All(trajectoriesFinal, settings.dh,
                                                             settings.dv))
                if (!unresolved.Contains(conflict.pair)) {
                    target = conflict;
                    break;
                }
            if (target == null)
                break;
            Round round = new Round(rounds.Count + 1, target);
            string[] priority =
                Resolution.Priority(finalPlans[target.pair.first], finalPlans[target.pair.second]);
            for (int side = 0; side < 2 && round.accepted == null; side++) {
                string aircraft = priority[side], partner = priority[1 - side];
                foreach (Resolution.Manoeuvre manoeuvre in manoeuvres) {
                    Trial trial = new Trial(aircraft, manoeuvre.name);
                    FlightPlans.Plan proposal =
                        Resolution.Propose(finalPlans[aircraft], manoeuvre, types, settings);
                    if (proposal == null)
                        trial.status = "infeasible";
                    else {
                        Trajectory.Built trajectory = Trajectory.Build(proposal, types);
                        Conflict.Event blocker =
                            Blocker(aircraft, trajectory, partner, target.start);
                        if (blocker != null) {
                            trial.status = "blocked";
                            trial.blocker = blocker;
                        } else {
                            trial.status = "accepted";
                            proposal.history.Add(manoeuvre.name);
                            finalPlans[aircraft] = proposal;
                            trajectoriesFinal[aircraft] = trajectory;
                            round.accepted = trial;
                        }
                    }
                    round.trials.Add(trial);
                    if (round.accepted != null)
                        break;
                }
            }
            if (round.accepted == null) {
                unresolved.Add(target.pair);
                unresolvedConflicts.Add(target);
            } else
                resolved.Add(target.pair);
            rounds.Add(round);
        }
    }
    public static double Track(Trajectory.Segment segment) {
        double angle = Math.Atan2(segment.velocity.x, segment.velocity.y) * 180 / PI;
        return angle < 0 ? angle + 360 : angle;
    }
    public static bool Contains(FlightPlans.Sector sector, Trajectory.Vec point) {
        return sector.x1 / 10.0 <= point.x && point.x < sector.x2 / 10.0 &&
               sector.y1 / 10.0 <= point.y && point.y < sector.y2 / 10.0 &&
               sector.lower * 100.0 <= point.z && point.z < sector.upper * 100.0;
    }
    public static void Classify(List<Conflict.Event> conflicts, HashSet<Conflict.Pair> finalPairs,
                                bool last) {
        foreach (Conflict.Event conflict in conflicts) {
            Conflict.Piece piece = conflict.closest;
            Trajectory.Segment a = piece.a, b = piece.b;
            Trajectory.Vec pa = Trajectory.Position(a, piece.loss.tc),
                           pb = Trajectory.Position(b, piece.loss.tc);
            conflict.levelA = pa.z / 100;
            conflict.levelB = pb.z / 100;
            conflict.trackA = Track(a);
            conflict.trackB = Track(b);
            double angle = Math.Abs(conflict.trackA - conflict.trackB);
            conflict.angle = angle > 180 ? 360 - angle : angle;
            double dot = a.velocity.x * b.velocity.x + a.velocity.y * b.velocity.y,
                   cross = a.velocity.x * b.velocity.y - a.velocity.y * b.velocity.x;
            conflict.geometry =
                dot * dot > cross * cross ? (dot < 0 ? "head_on" : "trailing") : "crossing";
            double distance = piece.loss.distance;
            conflict.severity = 10 * distance < 4.0 * settings.dh   ? "HIGH"
                                : 10 * distance < 7.0 * settings.dh ? "MEDIUM"
                                                                    : "LOW";
            Trajectory.Vec midpoint =
                new Trajectory.Vec((pa.x + pb.x) / 2, (pa.y + pb.y) / 2, (pa.z + pb.z) / 2);
            conflict.sector = "-";
            foreach (FlightPlans.Sector sector in sectors)
                if (Contains(sector, midpoint)) {
                    conflict.sector = sector.name;
                    break;
                }
            conflict.outcome = last || finalPairs.Contains(conflict.pair) ? "remaining"
                               : resolved.Contains(conflict.pair)         ? "resolved"
                                                                          : "indirect";
        }
    }
    public static List<string> TrajectoriesCsv() {
        List<string> lines = new();
        lines.Add(
            "callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end");
        foreach (var entry in trajectoriesFinal)
            foreach (Trajectory.Segment segment in entry.Value.segments) {
                Trajectory.Vec a = segment.start, b = segment.end;
                lines.Add(entry.Key + "," + segment.number + "," + segment.leg + "," +
                          segment.phase + "," + F(segment.ts) + "," + F(segment.te) + "," + F(a.x) +
                          "," + F(a.y) + "," + (int)(a.z / 100) + "," + F(b.x) + "," + F(b.y) +
                          "," + (int)(b.z / 100));
            }
        return lines;
    }
    public static List<string> ConflictLines(string label, List<Conflict.Event> conflicts,
                                             IDictionary<string, Trajectory.Built> trajectories) {
        List<string> lines = new();
        lines.Add("CONFLICTS plan=" + label + " count=" + conflicts.Count);
        Dictionary<string, int> geometry = new(), severity = new();
        double duration = 0, minimum = double.PositiveInfinity;
        for (int i = 0; i < conflicts.Count; i++) {
            Conflict.Event conflict = conflicts[i];
            Conflict.Piece piece = conflict.closest;
            Conflict.Loss loss = piece.loss;
            lines.Add("CONFLICT " + (i + 1) + " " + conflict.pair.name +
                      " start=" + F(conflict.start) + " end=" + F(conflict.end) + " duration=" +
                      F(conflict.end - conflict.start) + " outcome=" + conflict.outcome);
            lines.Add("  CPA t=" + F(loss.tc) + " dist=" + F(loss.distance) +
                      " vert=" + F(loss.vertical, 1) + " levels=" + F(conflict.levelA, 2) + "/" +
                      F(conflict.levelB, 2) + " tracks=" + F(conflict.trackA, 1) + "/" +
                      F(conflict.trackB, 1) + " angle=" + F(conflict.angle, 1));
            lines.Add("  TYPE geometry=" + conflict.geometry + " phases=" + piece.a.phase + "/" +
                      piece.b.phase + " segments=" + piece.a.number + "/" + piece.b.number +
                      " sector=" + conflict.sector + " severity=" + conflict.severity);
            foreach (Conflict.Piece part in conflict.pieces)
                lines.Add("  PIECE " + part.a.number + "/" + part.b.number + " " + F(part.loss.lo) +
                          " " + F(part.loss.hi));
            Add(geometry, conflict.geometry);
            Add(severity, conflict.severity);
            duration += conflict.end - conflict.start;
            minimum = Math.Min(minimum, loss.distance);
        }
        lines.Add("SUMMARY count=" + conflicts.Count + " total=" + F(duration) +
                  " min_dist=" + (conflicts.Count == 0 ? "-" : F(minimum)) +
                  " head_on=" + geometry.GetValueOrDefault("head_on", 0) +
                  " crossing=" + geometry.GetValueOrDefault("crossing", 0) +
                  " trailing=" + geometry.GetValueOrDefault("trailing", 0) +
                  " high=" + severity.GetValueOrDefault("HIGH", 0) +
                  " medium=" + severity.GetValueOrDefault("MEDIUM", 0) +
                  " low=" + severity.GetValueOrDefault("LOW", 0));
        SortedDictionary<string, List<Involvement>> involved = InvolvementMap(conflicts);
        foreach (var entry in involved) {
            SortedSet<string> partners = new SortedSet<string>(StringComparer.Ordinal);
            double first = double.PositiveInfinity;
            foreach (Involvement item in entry.Value) {
                partners.Add(item.partner);
                first = Math.Min(first, item.conflict.start);
            }
            lines.Add("FLIGHT " + entry.Key + " conflicts=" + entry.Value.Count +
                      " first=" + F(first) + " partners=" + string.Join(",", partners));
        }
        lines.Add("TIMELINE from=" + settings.sampleStart + " to=" + settings.sampleEnd +
                  " step=60");
        foreach (var entry in involved) {
            StringBuilder timeline = new StringBuilder();
            foreach (int time in samples) {
                if (Trajectory.Active(trajectories[entry.Key], time) == null)
                    timeline.Append('.');
                else {
                    bool conflict = false;
                    foreach (Involvement item in entry.Value)
                        if (Active(item.conflict, time))
                            conflict = true;
                    timeline.Append(conflict ? 'X' : '-');
                }
            }
            lines.Add(entry.Key + " " + timeline);
        }
        return lines;
    }
    public static List<string> ResolutionLines() {
        List<string> lines = new();
        int trialCount = 0, infeasible = 0, blocked = 0, accepted = 0, level = 0, speed = 0,
            delay = 0;
        foreach (Round round in rounds) {
            Conflict.Event target = round.target;
            lines.Add("ROUND " + round.number + " " + target.pair.name +
                      " start=" + F(target.start) + " end=" + F(target.end) +
                      " dist=" + F(target.closest.loss.distance));
            foreach (Trial trial in round.trials) {
                trialCount++;
                string line = "  TRY " + trial.aircraft + " " + trial.name + " " + trial.status;
                if (trial.status.Equals("infeasible"))
                    infeasible++;
                if (trial.status.Equals("blocked")) {
                    blocked++;
                    line += " " + trial.blocker.pair.name + " start=" + F(trial.blocker.start);
                }
                lines.Add(line);
            }
            if (round.accepted == null)
                lines.Add("  RESULT unresolved");
            else {
                Trial trial = round.accepted;
                accepted++;
                if (trial.name.StartsWith("level_"))
                    level++;
                else if (trial.name.Equals("speed_down"))
                    speed++;
                else
                    delay++;
                lines.Add("  RESULT resolved " + trial.aircraft + " " + trial.name);
            }
        }
        SortedDictionary<string, List<Involvement>> before = InvolvementMap(initialConflicts),
                                                    after = InvolvementMap(finalConflicts);
        double totalExtra = 0;
        long totalDelay = 0;
        foreach (string code in finalPlans.Keys) {
            FlightPlans.Plan old = initial[code], plan = finalPlans[code];
            Trajectory.Built first = trajectoriesInitial[code], last = trajectoriesFinal[code];
            double extra = last.arrival - first.arrival;
            totalExtra += extra;
            totalDelay += plan.delay;
            lines.Add(
                "FLIGHT " + code + " departure=" + (plan.departure + plan.delay) +
                " delay=" + plan.delay + " level=" + Report.Signed(plan.offset) +
                " speed=" + old.speed + "->" + plan.speed + " arrival=" + F(first.arrival) + "->" +
                F(last.arrival) + " extra=" + F(extra) + " length=" + F(last.length) +
                " conflicts=" + before.GetValueOrDefault(code, new List<Involvement>()).Count +
                "->" + after.GetValueOrDefault(code, new List<Involvement>()).Count +
                " manoeuvres=" + (plan.history.Count == 0 ? "-" : string.Join(",", plan.history)));
        }
        foreach (Conflict.Event conflict in unresolvedConflicts)
            lines.Add("UNRESOLVED " + conflict.pair.name + " start=" + F(conflict.start) +
                      " dist=" + F(conflict.closest.loss.distance));
        lines.Add("TOTAL rounds=" + rounds.Count + " resolved=" + accepted +
                  " unresolved=" + unresolvedConflicts.Count + " level=" + level +
                  " speed=" + speed + " delay=" + delay + " total_delay=" + totalDelay +
                  " total_extra=" + F(totalExtra) + " trials=" + trialCount +
                  " infeasible=" + infeasible + " blocked=" + blocked);
        return lines;
    }
    public static Interval Inside(Trajectory.Segment segment, FlightPlans.Sector sector) {
        double[] low = { sector.x1 / 10.0, sector.y1 / 10.0, sector.lower * 100.0 },
                 high = { sector.x2 / 10.0, sector.y2 / 10.0, sector.upper * 100.0 };
        double lo = segment.ts, hi = segment.te;
        for (int axis = 0; axis < 3; axis++) {
            double p = segment.start.Component(axis), v = segment.velocity.Component(axis);
            if (v == 0) {
                if (!(low[axis] <= p && p < high[axis]))
                    return null;
            } else {
                double r1 = (low[axis] - p) / v, r2 = (high[axis] - p) / v;
                lo = Math.Max(lo, segment.ts + Math.Min(r1, r2));
                hi = Math.Min(hi, segment.ts + Math.Max(r1, r2));
            }
        }
        return hi - lo > 1e-6 ? new Interval(lo, hi) : null;
    }
    public static List<Transit> Transits(IDictionary<string, Trajectory.Built> trajectories) {
        List<Transit> all = new();
        foreach (string code in new SortedSet<string>(trajectories.Keys, StringComparer.Ordinal)) {
            List<Transit> flight = new();
            foreach (FlightPlans.Sector sector in sectors) {
                List<Interval> combined = new();
                foreach (Trajectory.Segment segment in trajectories[code].segments) {
                    Interval interval = Inside(segment, sector);
                    if (interval == null)
                        continue;
                    if (combined.Count != 0 && interval.lo - combined[^1].hi <= 1e-6)
                        combined[combined.Count - 1] = new Interval(combined[^1].lo, interval.hi);
                    else
                        combined.Add(interval);
                }
                foreach (Interval interval in combined)
                    flight.Add(new Transit(code, sector.index, interval.lo, interval.hi));
            }
            flight =
                flight.OrderBy(transit => transit.entry).ThenBy(transit => transit.sector).ToList();
            for (int i = 0; i + 1 < flight.Count; i++) {
                Transit before = flight[i], after = flight[i + 1];
                if (Math.Abs(after.entry - before.exit) <= 1e-6) {
                    before.next = sectors[after.sector].name;
                    before.nextIndex = after.sector;
                    after.previous = sectors[before.sector].name;
                    after.previousIndex = before.sector;
                }
            }
            all.AddRange(flight);
        }
        return all;
    }
    public static List<string> TransitLines(List<Transit> transits) {
        List<string> lines = new();
        lines.Add("callsign,sector,entry,exit,duration,from,to");
        foreach (Transit transit in transits)
            lines.Add(transit.callsign + "," + sectors[transit.sector].name + "," +
                      F(transit.entry) + "," + F(transit.exit) + "," +
                      F(transit.exit - transit.entry) + "," + transit.previous + "," +
                      transit.next);
        return lines;
    }
    public static int[][] Occupancy(IDictionary<string, Trajectory.Built> trajectories) {
        int[][] values = Enumerable.Range(0, sectors.Count)
                             .Select(
                                 _ => new int[samples.Count])
                             .ToArray();
        for (int j = 0; j < samples.Count; j++)
            foreach (string code in new SortedSet<string>(trajectories.Keys,
                                                          StringComparer.Ordinal)) {
                Trajectory.Observed observed = Trajectory.Current(trajectories[code], samples[j]);
                if (observed == null)
                    continue;
                foreach (FlightPlans.Sector sector in sectors)
                    if (Contains(sector, observed.position))
                        values[sector.index][j]++;
            }
        return values;
    }
    public static List<Period> BuildPeriods(int[][] before, int[][] after, List<Transit> first,
                                            List<Transit> last) {
        List<Period> result = new();
        foreach (FlightPlans.Sector sector in sectors)
            for (int j = 0; j < samples.Count; j += 5) {
                int start = samples[j], end = start + 300, peakInitial = 0, peakFinal = 0, sum = 0,
                    entriesInitial = 0, entriesFinal = 0;
                for (int k = j; k < j + 5; k++) {
                    peakInitial = Math.Max(peakInitial, before[sector.index][k]);
                    peakFinal = Math.Max(peakFinal, after[sector.index][k]);
                    sum += after[sector.index][k];
                }
                foreach (Transit transit in first)
                    if (transit.sector == sector.index && start <= transit.entry &&
                        transit.entry < end)
                        entriesInitial++;
                foreach (Transit transit in last)
                    if (transit.sector == sector.index && start <= transit.entry &&
                        transit.entry < end)
                        entriesFinal++;
                string status = peakFinal > sector.capacity     ? "OVER"
                                : peakInitial > sector.capacity ? "RELIEVED"
                                                                : "OK";
                result.Add(new Period(sector.index, j / 5 + 1, start, end, entriesInitial,
                                      entriesFinal, peakInitial, peakFinal, sum / 5.0, status));
            }
        return result;
    }
    public static List<string> SectorLoad(List<Period> periods) {
        List<string> lines = new();
        lines.Add(
            "sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status");
        foreach (Period period in periods) {
            FlightPlans.Sector sector = sectors[period.sector];
            lines.Add(sector.name + "," + period.number + "," + period.start + "," + period.end +
                      "," + period.entriesInitial + "," + period.entriesFinal + "," +
                      period.peakInitial + "," + period.peakFinal + "," + F(period.meanFinal, 1) +
                      "," + sector.capacity + "," + period.status);
        }
        return lines;
    }
    public static SortedDictionary<int, Usage>
    LevelUsage(IDictionary<string, Trajectory.Built> trajectories) {
        SortedDictionary<int, Usage> result = new(Comparer<int>.Create((a, b) => b.CompareTo(a)));
        foreach (string code in new SortedSet<string>(trajectories.Keys, StringComparer.Ordinal))
            foreach (Trajectory.Segment segment in trajectories[code].segments)
                if (segment.phase.Equals("LVL")) {
                    int level = (int)(segment.start.z / 100);
                    Usage usage = result.GetOrAdd(level, key => new Usage());
                    usage.flights.Add(code);
                    usage.time += segment.te - segment.ts;
                }
        return result;
    }
    public static string SectorSummary(string label, int index, int[][] occupancy,
                                       List<Transit> transits, List<Conflict.Event> conflicts) {
        int entries = 0, peak = 0, over = 0, count = 0;
        double dwell = 0;
        foreach (Transit transit in transits)
            if (transit.sector == index) {
                entries++;
                dwell += transit.exit - transit.entry;
            }
        for (int j = 0; j < samples.Count; j += 5) {
            int periodPeak = 0;
            for (int k = j; k < j + 5; k++)
                periodPeak = Math.Max(periodPeak, occupancy[index][k]);
            peak = Math.Max(peak, periodPeak);
            if (periodPeak > sectors[index].capacity)
                over++;
        }
        foreach (Conflict.Event conflict in conflicts)
            if (conflict.sector.Equals(sectors[index].name))
                count++;
        return label + " entries=" + entries + " time=" + F(dwell) +
               " mean=" + (entries == 0 ? "-" : F(dwell / entries)) + " peak=" + peak +
               " over=" + over + " conflicts=" + count;
    }
    public static List<string> SectorReport(int[][] before, int[][] after, List<Transit> first,
                                            List<Transit> last) {
        List<string> lines = new();
        foreach (FlightPlans.Sector sector in sectors) {
            int index = sector.index;
            lines.Add("SECTOR " + sector.name + " x=" + sector.x1 + ".." + sector.x2 +
                      " y=" + sector.y1 + ".." + sector.y2 + " fl=" + sector.lower + ".." +
                      sector.upper + " capacity=" + sector.capacity);
            lines.Add(SectorSummary("INITIAL", index, before, first, initialConflicts));
            lines.Add(SectorSummary("FINAL", index, after, last, finalConflicts));
            int height = sector.capacity + 1;
            foreach (int value in after[index])
                height = Math.Max(height, value);
            List<string> rows = new();
            for (int level = height; level >= 1; level--) {
                StringBuilder row = new StringBuilder();
                foreach (int value in after[index])
                    row.Append(value >= level ? '#' : level == sector.capacity ? '-' : '.');
                rows.Add(row.ToString());
            }
            lines.AddRange(Report.Chart(rows));
        }
        SortedDictionary<int, Usage> initialUsage = LevelUsage(trajectoriesInitial),
                                     finalUsage = LevelUsage(trajectoriesFinal);
        SortedSet<int> levels = new(Comparer<int>.Create((a, b) => b.CompareTo(a)));
        levels.AddRange(initialUsage.Keys);
        levels.AddRange(finalUsage.Keys);
        lines.Add("LEVELS");
        foreach (int level in levels) {
            Usage old = initialUsage.GetValueOrDefault(level, new Usage()),
                  now = finalUsage.GetValueOrDefault(level, new Usage());
            lines.Add("LEVEL " + level + " flights=" + old.flights.Count + "->" +
                      now.flights.Count + " time=" + F(old.time) + "->" + F(now.time));
        }
        int[][] handoffs = Enumerable.Range(0, sectors.Count)
                               .Select(
                                   _ => new int[sectors.Count])
                               .ToArray();
        int count = 0;
        foreach (Transit transit in last)
            if (transit.nextIndex >= 0) {
                handoffs[transit.sector][transit.nextIndex]++;
                count++;
            }
        lines.Add("HANDOFFS plan=final count=" + count);
        for (int a = 0; a < sectors.Count; a++)
            for (int b = 0; b < sectors.Count; b++)
                if (handoffs[a][b] > 0)
                    lines.Add("HANDOFF " + sectors[a].name + " " + sectors[b].name + " " +
                              handoffs[a][b]);
        return lines;
    }
    public static List<string> AlertLines(string label,
                                          IDictionary<string, Trajectory.Built> trajectories,
                                          List<Conflict.Event> conflicts) {
        Dictionary<Conflict.Pair, List<Observation>> observations = new();
        foreach (int time in samples) {
            SortedDictionary<string, Trajectory.Observed> flying = new(StringComparer.Ordinal);
            foreach (string code in trajectories.Keys) {
                Trajectory.Observed observed = Trajectory.Current(trajectories[code], time);
                if (observed != null)
                    flying[code] = observed;
            }
            List<string> names = new(flying.Keys);
            for (int a = 0; a < names.Count; a++)
                for (int b = a + 1; b < names.Count; b++) {
                    string first = names[a], second = names[b];
                    Trajectory.Observed pa = flying[first], pb = flying[second];
                    Conflict.Loss loss =
                        Conflict.LossInterval(pa.position.Minus(pb.position),
                                              pa.segment.velocity.Minus(pb.segment.velocity), 0,
                                              settings.alert, settings.dh, settings.dv);
                    if (loss != null)
                        observations.GetOrAdd(new Conflict.Pair(first, second), key => new())
                            .Add(new Observation(time, time + loss.lo, loss.distance));
                }
        }
        List<Alert> alerts = new();
        foreach (var entry in observations) {
            Alert group = null;
            foreach (Observation observation in entry.Value) {
                if (group == null || observation.time - group.last != 60) {
                    group = new Alert(entry.Key, observation);
                    alerts.Add(group);
                } else {
                    group.last = observation.time;
                    group.count++;
                    group.minimum = Math.Min(group.minimum, observation.distance);
                }
            }
        }
        alerts = alerts.OrderBy(alert => alert.first)
                     .ThenBy(alert => alert.pair.first, StringComparer.Ordinal)
                     .ThenBy(alert => alert.pair.second, StringComparer.Ordinal)
                     .ToList();
        bool[] detected = new bool[conflicts.Count];
        foreach (Alert alert in alerts)
            for (int i = 0; i < conflicts.Count; i++) {
                Conflict.Event conflict = conflicts[i];
                if (conflict.pair.Equals(alert.pair) &&
                    conflict.start < alert.last + (double)settings.alert &&
                    conflict.end > alert.first) {
                    detected[i] = true;
                    if (alert.lead == null)
                        alert.lead = conflict.start - alert.first;
                }
            }
        List<string> lines = new();
        lines.Add("ALERTS plan=" + label + " horizon=" + settings.alert + " count=" + alerts.Count);
        int trueCount = 0, missed = 0;
        double leadSum = 0;
        for (int i = 0; i < alerts.Count; i++) {
            Alert alert = alerts[i];
            string status = "status=false lead=-";
            if (alert.lead != null) {
                trueCount++;
                leadSum += alert.lead.Value;
                status = "status=true lead=" + F(alert.lead.Value);
            }
            lines.Add("ALERT " + (i + 1) + " " + alert.pair.name + " first=" + alert.first +
                      " last=" + alert.last + " samples=" + alert.count + " predicted=" +
                      F(alert.predicted) + " min_dist=" + F(alert.minimum) + " " + status);
        }
        for (int i = 0; i < conflicts.Count; i++)
            if (!detected[i]) {
                missed++;
                Conflict.Event conflict = conflicts[i];
                lines.Add("MISSED " + conflict.pair.name + " start=" + F(conflict.start) +
                          " end=" + F(conflict.end));
            }
        lines.Add("SUMMARY alerts=" + alerts.Count + " true=" + trueCount +
                  " false=" + (alerts.Count - trueCount) + " missed=" + missed +
                  " mean_lead=" + (trueCount == 0 ? "-" : F(leadSum / trueCount)));
        return lines;
    }
    public static Cell ScreenCell(Trajectory.Vec position) {
        int[] r = settings.radar;
        double column = Math.Floor((10 * position.x - r[0]) * r[4] / (r[2] - r[0])),
               row = Math.Floor((10 * position.y - r[1]) * r[5] / (r[3] - r[1]));
        if (column < 0 || column >= r[4] || row < 0 || row >= r[5])
            return null;
        return new Cell((int)column, r[5] - 1 - (int)row);
    }
    public static List<string> GridRows(char[][] grid) {
        List<string> rows = new();
        foreach (char[] row in grid)
            rows.Add(new string(row));
        return rows;
    }
    public static List<string> RadarSnapshot(string label,
                                             IDictionary<string, Trajectory.Built> trajectories,
                                             List<Conflict.Event> conflicts, int time) {
        int width = settings.radar[4], height = settings.radar[5];
        char[][] grid = Enumerable.Range(0, height)
                            .Select(
                                _ => new char[width])
                            .ToArray();
        foreach (char[] row in grid)
            Array.Fill(row, '.');
        SortedDictionary<string, RadarPosition> positions = new(StringComparer.Ordinal);
        Dictionary<Cell, List<string>> placements = new();
        foreach (string code in new SortedSet<string>(trajectories.Keys, StringComparer.Ordinal)) {
            Trajectory.Observed observed = Trajectory.Current(trajectories[code], time);
            if (observed == null)
                continue;
            Cell cell = ScreenCell(observed.position);
            positions[code] = new RadarPosition(observed.position, observed.segment, cell);
            if (cell != null)
                placements.GetOrAdd(cell, key => new()).Add(code);
        }
        List<Conflict.Event> active = ActiveConflicts(conflicts, time);
        HashSet<string> conflicted = new();
        foreach (Conflict.Event conflict in active) {
            conflicted.Add(conflict.pair.first);
            conflicted.Add(conflict.pair.second);
        }
        foreach (var entry in placements) {
            List<string> names = entry.Value;
            string name = names[0];
            char value = names.Count > 1             ? (char)('0' + names.Count)
                         : conflicted.Contains(name) ? char.ToLowerInvariant(name[0])
                                                     : name[0];
            grid[entry.Key.row][entry.Key.column] = value;
        }
        foreach (string code in positions.Keys) {
            Trajectory.Observed predicted =
                Trajectory.Current(trajectories[code], time + (double)settings.leader);
            if (predicted == null)
                continue;
            Cell cell = ScreenCell(predicted.position);
            if (cell != null && grid[cell.row][cell.column] == '.')
                grid[cell.row][cell.column] = '*';
        }
        List<string> lines = new();
        lines.Add("RADAR plan=" + label + " t=" + time + " aircraft=" + positions.Count +
                  " conflicts=" + active.Count);
        lines.AddRange(Report.Chart(GridRows(grid)));
        foreach (var entry in positions) {
            RadarPosition value = entry.Value;
            Trajectory.Vec p = value.position;
            Cell c = value.cell;
            lines.Add(entry.Key + " x=" + F(p.x) + " y=" + F(p.y) + " fl=" + F(p.z / 100, 2) +
                      " track=" + F(Track(value.segment), 1) + " phase=" + value.segment.phase +
                      " cell=" + (c == null ? "outside" : c.column + "," + c.row));
        }
        foreach (Conflict.Event conflict in active) {
            Trajectory.Vec a = positions[conflict.pair.first].position,
                           b = positions[conflict.pair.second].position;
            double dx = a.x - b.x, dy = a.y - b.y;
            lines.Add("CONFLICT " + conflict.pair.name + " dist=" +
                      F(Math.Sqrt(dx * dx + dy * dy)) + " vert=" + F(Math.Abs(a.z - b.z), 1));
        }
        return lines;
    }
    public static List<string> Density(string label,
                                       IDictionary<string, Trajectory.Built> trajectories) {
        int width = settings.radar[4], height = settings.radar[5], maximum = 0;
        int[][] counts = Enumerable.Range(0, height)
                             .Select(
                                 _ => new int[width])
                             .ToArray();
        foreach (int time in samples)
            foreach (string code in new SortedSet<string>(trajectories.Keys,
                                                          StringComparer.Ordinal)) {
                Trajectory.Observed observed = Trajectory.Current(trajectories[code], time);
                if (observed == null)
                    continue;
                Cell cell = ScreenCell(observed.position);
                if (cell != null)
                    counts[cell.row][cell.column]++;
            }
        char[][] grid = Enumerable.Range(0, height)
                            .Select(
                                _ => new char[width])
                            .ToArray();
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++) {
                int count = counts[row][col];
                maximum = Math.Max(maximum, count);
                grid[row][col] = count == 0 ? '.' : count < 10 ? (char)('0' + count) : '#';
            }
        List<string> lines = new();
        lines.Add("DENSITY plan=" + label + " from=" + settings.sampleStart +
                  " to=" + settings.sampleEnd + " step=60 max=" + maximum);
        lines.AddRange(Report.Chart(GridRows(grid)));
        return lines;
    }
    public static List<string> Strips(List<Transit> transits) {
        List<string> lines = new();
        foreach (string code in initial.Keys) {
            FlightPlans.Plan plan = finalPlans[code];
            Trajectory.Built before = trajectoriesInitial[code], after = trajectoriesFinal[code];
            lines.Add("STRIP " + code + " type=" + plan.type + " waypoints=" +
                      plan.waypoints.Count + " length=" + F(after.length) + " manoeuvres=" +
                      (plan.history.Count == 0 ? "-" : string.Join(",", plan.history)));
            for (int k = 0; k < plan.waypoints.Count; k++) {
                FlightPlans.Waypoint point = plan.waypoints[k];
                Trajectory.Passing old = before.waypointTimes[k], now = after.waypointTimes[k];
                lines.Add("WPT " + k + " at=" + point.x + ":" + point.y + " eta=" + F(old.time) +
                          "->" + F(now.time) + " fl=" + old.level + "->" + now.level);
            }
            List<string> sequence = new();
            foreach (Transit transit in transits)
                if (transit.callsign.Equals(code))
                    sequence.Add(sectors[transit.sector].name + "@" + F(transit.entry));
            lines.Add("SECTORS " + (sequence.Count == 0 ? "-" : string.Join(",", sequence)));
        }
        return lines;
    }
    public static void Main(string[] args) {
        FlightPlans.Input input = FlightPlans.Read();
        initial = input.plans;
        types = input.types;
        sectors = input.sectors;
        settings = input.settings;
        foreach (var entry in initial)
            trajectoriesInitial[entry.Key] = Trajectory.Build(entry.Value, types);
        initialConflicts = Conflict.All(trajectoriesInitial, settings.dh, settings.dv);
        Resolve();
        finalConflicts = Conflict.All(trajectoriesFinal, settings.dh, settings.dv);
        HashSet<Conflict.Pair> finalPairs = new();
        foreach (Conflict.Event conflict in finalConflicts)
            finalPairs.Add(conflict.pair);
        Classify(initialConflicts, finalPairs, false);
        Classify(finalConflicts, finalPairs, true);
        for (int time = settings.sampleStart; time < settings.sampleEnd; time += 60)
            samples.Add(time);
        List<Transit> first = Transits(trajectoriesInitial), last = Transits(trajectoriesFinal);
        int[][] before = Occupancy(trajectoriesInitial), after = Occupancy(trajectoriesFinal);
        List<Period> periods = BuildPeriods(before, after, first, last);
        Report.Write("trajectories.csv", TrajectoriesCsv());
        List<string> conflicts = ConflictLines("initial", initialConflicts, trajectoriesInitial);
        conflicts.AddRange(ConflictLines("final", finalConflicts, trajectoriesFinal));
        Report.Write("conflicts.txt", conflicts);
        Report.Write("resolutions.txt", ResolutionLines());
        Report.Write("sector_transits.csv", TransitLines(last));
        Report.Write("sector_load.csv", SectorLoad(periods));
        Report.Write("sector_report.txt", SectorReport(before, after, first, last));
        List<string> alerts = AlertLines("initial", trajectoriesInitial, initialConflicts);
        alerts.AddRange(AlertLines("final", trajectoriesFinal, finalConflicts));
        Report.Write("alerts.txt", alerts);
        List<string> radar = new();
        foreach (int time in settings.snapshots) {
            radar.AddRange(RadarSnapshot("initial", trajectoriesInitial, initialConflicts, time));
            radar.AddRange(RadarSnapshot("final", trajectoriesFinal, finalConflicts, time));
        }
        radar.AddRange(Density("initial", trajectoriesInitial));
        radar.AddRange(Density("final", trajectoriesFinal));
        Report.Write("radar.txt", radar);
        Report.Write("strips.txt", Strips(last));
    }
}
