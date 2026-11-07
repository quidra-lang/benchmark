using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Program {
    public static Eventlog.Input input;
    public static Conformance.Net reference;
    public static List<Eventlog.Event> events = new();
    public static List<Eventlog.Case> cases;
    public static List<string> activities, resources;
    public static List<string> errors = new();
    public static List<Dfg.Trace> log = new(), filtered = new();
    public static Dictionary<Dfg.Pair, long> counts;
    public static List<Variant> variants = new();
    public static Dictionary<string, int> variantIds = new();
    public static int keptCases, keptEvents;
    public static List<Conformance.Net> nets = new();
    public static readonly string[] NET_NAMES = { "reference", "alpha", "alpha_plus" };
    public static Dictionary<string, Conformance.Totals> referenceReplays = new();
    public record Identity(string id, string activity, string timestamp) {}
    public sealed class Variant {
        public int number;
        public List<string> trace;
        public List<Eventlog.Case> cases;
        public bool keep;
        public Variant(List<string> trace, List<Eventlog.Case> cases) {
            this.trace = trace;
            this.cases = cases;
        }
    }
    public sealed class Discovery {
        public Conformance.Net net;
        public List<string> activities, starts, ends;
        public string[][] relation;
        public List<AlphaMiner.Candidate> maximal;
        public int candidates, causal;
    }
    public record Edge(int from, int transition, int to) {}
    public sealed class Reach {
        public int markings, edges, unsafeCount, deadlocks, stuck;
        public bool terminal, sound;
        public List<string> dead = new();
        public Dictionary<Dfg.Pair, long> follows = new();
    }
    public sealed class Prefix {
        public long weight;
        public SortedSet<string> followers = new SortedSet<string>(StringComparer.Ordinal);
    }
    public static long Parameter(string name) { return long.Parse(input.parameters[name]); }
    public static Report.Fraction Threshold(string name) {
        return Report.Parse(input.parameters[name]);
    }
    public static string Fraction(long a, long b) { return Report.Format(a, b); }
    public static string Fraction(Report.Fraction value) { return Report.Format(value); }
    public static string Names(IEnumerable<string> values) { return Report.Names(values); }
    public static string Yes(bool value) { return value ? "yes" : "no"; }
    public static void Add<K>(Dictionary<K, long> map, K key, long value) {
        map.AddCount(key, value);
    }
    public static long Get<K>(Dictionary<K, long> map, K key) {
        return map.GetValueOrDefault(key, 0L);
    }
    public static int CompareTrace(List<string> a, List<string> b) {
        for (int i = 0; i < Math.Min(a.Count, b.Count); i++) {
            int c = string.CompareOrdinal(a[i], b[i]);
            if (c != 0)
                return c;
        }
        return (a.Count).CompareTo(b.Count);
    }
    public static List<Dfg.Pair> PairOrder(Dictionary<Dfg.Pair, long> values, bool frequency) {
        List<Dfg.Pair> pairs = new(values.Keys);
        pairs.Sort((a, b) => {
            int c = frequency ? values[b].CompareTo(values[a]) : 0;
            return c != 0 ? c : Dfg.Compare(a, b);
        });
        return pairs;
    }
    public static List<string> NameOrder(Dictionary<string, long> values) {
        List<string> result = new(values.Keys);
        result.Sort((a, b) => {
            int c = values[b].CompareTo(values[a]);
            return c != 0 ? c : string.CompareOrdinal(a, b);
        });
        return result;
    }
    public static void WaitValue<K>(Dictionary<K, List<int>> values, K key, int value) {
        values.GetOrAdd(key, k => new()).Add(value);
    }
    public static long Sum(List<int> values) {
        long total = 0;
        foreach (int value in values)
            total += value;
        return total;
    }
    public static string Mean(List<int> values) {
        return values.Count == 0 ? "-" : Fraction(Sum(values), values.Count);
    }
    public static void Prepare() {
        HashSet<Identity> adopted = new();
        SortedSet<string> allActivities = new SortedSet<string>(StringComparer.Ordinal),
                          allResources = new SortedSet<string>(StringComparer.Ordinal);
        foreach (Eventlog.Row row in input.rows) {
            int time = Eventlog.Timestamp(row.timestamp);
            if (time < 0) {
                errors.Add("line " + row.line + ": bad timestamp " + row.timestamp);
                continue;
            }
            Identity identity = new Identity(row.caseId, row.activity, row.timestamp);
            if (!adopted.Add(identity)) {
                errors.Add("line " + row.line + ": duplicate event " + row.caseId + " " +
                           row.activity + " " + row.timestamp);
                continue;
            }
            events.Add(new Eventlog.Event(row.line, row.caseId, row.activity, row.timestamp,
                                          row.resource, time));
            allActivities.Add(row.activity);
            allResources.Add(row.resource);
        }
        activities = new(allActivities);
        resources = new(allResources);
        cases = Eventlog.Group(events);
        foreach (Eventlog.Case c in cases)
            log.Add(new Dfg.Trace(c.trace, 1));
        counts = Dfg.Counts(log);
        Dictionary<List<string>, List<Eventlog.Case>> grouped = new(new Eventlog.TraceComparer());
        foreach (Eventlog.Case c in cases)
            grouped.GetOrAdd(c.trace, k => new()).Add(c);
        foreach (var entry in grouped)
            variants.Add(new Variant(entry.Key, entry.Value));
        variants.Sort((a, b) => {
            int order = (b.cases.Count).CompareTo(a.cases.Count);
            return order != 0 ? order : CompareTrace(a.trace, b.trace);
        });
        for (int i = 0; i < variants.Count; i++) {
            Variant v = variants[i];
            v.number = i + 1;
            v.keep = true;
            for (int j = 1; j < v.trace.Count; j++)
                if (Dfg.Count(counts, v.trace[j - 1], v.trace[j]) < Parameter("filter_min_follows"))
                    v.keep = false;
            foreach (Eventlog.Case c in v.cases)
                variantIds[c.id] = v.number;
            if (v.keep) {
                filtered.Add(new Dfg.Trace(v.trace, v.cases.Count));
                keptCases += v.cases.Count;
                keptEvents += v.trace.Count * v.cases.Count;
            }
        }
    }
    public static List<string> LogSummary() {
        List<string> lines = new();
        foreach (string error in errors)
            lines.Add("ERROR " + error);
        Eventlog.Event earliest = events[0], latest = earliest;
        foreach (Eventlog.Event e in events) {
            if (e.time < earliest.time)
                earliest = e;
            if (e.time > latest.time)
                latest = e;
        }
        lines.Add("LOG rows " + input.rows.Count + " adopted " + events.Count + " rejected " +
                  errors.Count + " cases " + cases.Count + " activities " + activities.Count +
                  " resources " + resources.Count + " first " + earliest.timestamp + " last " +
                  latest.timestamp);
        Dictionary<string, long> eventCount = new(), caseCount = new(), starts = new(),
                                 ends = new(), rework = new();
        Dictionary<string, List<int>> waits = new();
        Dictionary<string, SortedSet<string>> workers = new();
        long[] weekdayEvents = new long[7], weekdayStarts = new long[7], weekdayEnds = new long[7];
        List<int> lengths = new(), durations = new();
        foreach (Eventlog.Case c in cases) {
            lengths.Add(c.events.Count);
            durations.Add(c.duration);
            Dictionary<string, long> occurrences = new();
            foreach (string name in c.trace)
                Add(occurrences, name, 1);
            foreach (var entry in occurrences) {
                Add(caseCount, entry.Key, 1);
                if (entry.Value >= 2)
                    Add(rework, entry.Key, 1);
            }
            Add(starts, c.trace[0], 1);
            Add(ends, c.trace[^1], 1);
            weekdayStarts[(c.events[0].time / 1440 + 3) % 7]++;
            weekdayEnds[(c.events[^1].time / 1440 + 3) % 7]++;
            for (int i = 0; i < c.events.Count; i++) {
                Eventlog.Event e = c.events[i];
                Add(eventCount, e.activity, 1);
                workers.GetOrAdd(e.activity, k => new SortedSet<string>(StringComparer.Ordinal))
                    .Add(e.resource);
                weekdayEvents[(e.time / 1440 + 3) % 7]++;
                if (i > 0)
                    WaitValue(waits, e.activity, e.time - c.events[i - 1].time);
            }
        }
        foreach (string name in activities)
            lines.Add("ACTIVITY " + name + " events " + Get(eventCount, name) + " cases " +
                      Get(caseCount, name) + " start " + Get(starts, name) + " end " +
                      Get(ends, name) + " rework " + Get(rework, name) + " wait " +
                      Mean(waits.GetValueOrDefault(name, new List<int>())) + " resources " +
                      workers[name].Count + " model " +
                      Yes(reference.transitionIndex.ContainsKey(name)));
        for (int i = 0; i < 2; i++) {
            List<int> values = i == 0 ? lengths : durations;
            lines.Add((i == 0 ? "LENGTH" : "DURATION") + " min " + values.Min() + " max " +
                      values.Max() + " mean " + Mean(values) + " median " +
                      Fraction(Eventlog.Median(values)));
        }
        int maxDays = durations.Max() / 1440;
        int[] days = new int[maxDays + 1];
        int late = 0;
        foreach (int duration in durations) {
            days[duration / 1440]++;
            if (duration > Parameter("sla_minutes"))
                late++;
        }
        for (int d = 0; d < days.Length; d++)
            lines.Add("DAYS " + d + " cases " + days[d] + " share " +
                      Report.Percentage(days[d], cases.Count));
        lines.Add("SLA limit " + Parameter("sla_minutes") + " late " + late + " share " +
                  Report.Percentage(late, cases.Count));
        string[] weekdays = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        for (int i = 0; i < 7; i++)
            lines.Add("WEEKDAY " + weekdays[i] + " events " + weekdayEvents[i] + " starts " +
                      weekdayStarts[i] + " ends " + weekdayEnds[i]);
        return lines;
    }
    public static List<string> VariantLines() {
        List<string> lines = new();
        foreach (Variant v in variants) {
            List<int> durations = new();
            int late = 0;
            foreach (Eventlog.Case c in v.cases) {
                durations.Add(c.duration);
                if (c.duration > Parameter("sla_minutes"))
                    late++;
            }
            lines.Add("VARIANT " + v.number + " count " + v.cases.Count + " share " +
                      Report.Percentage(v.cases.Count, cases.Count) + " length " + v.trace.Count +
                      " first " + v.cases[0].id + " duration " + Mean(durations) + " late " + late +
                      " fitness " + Fraction(referenceReplays[v.cases[0].id].Fitness()) + " " +
                      (v.keep ? "KEEP" : "DROP") + " " + Names(v.trace));
        }
        lines.Add("FILTER min_follows " + Parameter("filter_min_follows") + " variants " +
                  filtered.Count + " of " + variants.Count + " cases " + keptCases + " of " +
                  cases.Count + " events " + keptEvents + " of " + events.Count);
        return lines;
    }
    public static string[][] Relation(List<string> names, Dictionary<Dfg.Pair, long> counts,
                                      Dictionary<Dfg.Pair, long> triangles) {
        string[][] result = Enumerable.Range(0, names.Count)
                                .Select(
                                    _ => new string[names.Count])
                                .ToArray();
        for (int i = 0; i < names.Count; i++)
            for (int j = 0; j < names.Count; j++)
                result[i][j] = triangles == null
                                   ? Dfg.Basic(counts, names[i], names[j])
                                   : AlphaMiner.Plus(counts, triangles, names[i], names[j]);
        return result;
    }
    public static List<string> DfgLines() {
        Dictionary<string, long> starts = new(), endCount = new();
        Dictionary<string, List<int>> ends = new();
        Dictionary<Dfg.Pair, List<int>> waiting = new();
        Dictionary<Dfg.Pair, long> edgeCases = new();
        foreach (Eventlog.Case c in cases) {
            Add(starts, c.trace[0], 1);
            Add(endCount, c.trace[^1], 1);
            WaitValue(ends, c.trace[^1], c.duration);
            HashSet<Dfg.Pair> present = new();
            for (int i = 1; i < c.events.Count; i++) {
                Eventlog.Event a = c.events[i - 1], b = c.events[i];
                Dfg.Pair pair = new Dfg.Pair(a.activity, b.activity);
                WaitValue(waiting, pair, b.time - a.time);
                present.Add(pair);
            }
            foreach (Dfg.Pair pair in present)
                Add(edgeCases, pair, 1);
        }
        List<string> lines = new();
        foreach (string name in NameOrder(starts))
            lines.Add("START " + name + " count " + Get(starts, name));
        foreach (string name in NameOrder(endCount))
            lines.Add("END " + name + " count " + Get(endCount, name) + " duration " +
                      Mean(ends[name]));
        foreach (Dfg.Pair pair in PairOrder(counts, true)) {
            List<int> values = waiting[pair];
            lines.Add("EDGE " + pair.first + " " + pair.second + " count " + counts[pair] +
                      " cases " + Get(edgeCases, pair) + " mean " + Mean(values) + " min " +
                      values.Min() + " max " + values.Max());
        }
        lines.AddRange(Dfg.Footprint(activities, Relation(activities, counts, null)));
        return lines;
    }
    public static List<string> MaskNames(int mask, List<string> names) {
        List<string> result = new();
        for (int i = 0; i < names.Count; i++)
            if ((mask & (1 << i)) != 0)
                result.Add(names[i]);
        return result;
    }
    public static Discovery Discover(List<Dfg.Trace> log, List<string> names, string[][] relation) {
        Discovery d = new Discovery();
        d.activities = names;
        d.relation = relation;
        HashSet<AlphaMiner.Candidate> candidates = new();
        Queue<AlphaMiner.Candidate> queue = new();
        for (int a = 0; a < names.Count; a++)
            for (int b = 0; b < names.Count; b++)
                if (relation[a][b].Equals("->")) {
                    d.causal++;
                    if (relation[a][a].Equals("#") && relation[b][b].Equals("#")) {
                        AlphaMiner.Candidate pair = new AlphaMiner.Candidate(1 << a, 1 << b);
                        if (candidates.Add(pair))
                            queue.Enqueue(pair);
                    }
                }
        while (queue.Count != 0) {
            AlphaMiner.Candidate pair = queue.Dequeue();
            for (int a = 0; a < names.Count; a++)
                for (int side = 0; side < 2; side++) {
                    AlphaMiner.Candidate extended = AlphaMiner.Extend(pair, a, side, relation);
                    if (extended != null && candidates.Add(extended))
                        queue.Enqueue(extended);
                }
        }
        d.candidates = candidates.Count;
        d.maximal = new();
        foreach (AlphaMiner.Candidate pair in candidates) {
            bool extended = false;
            for (int a = 0; a < names.Count; a++)
                for (int side = 0; side < 2; side++)
                    if (AlphaMiner.Extend(pair, a, side, relation) != null)
                        extended = true;
            if (!extended)
                d.maximal.Add(pair);
        }
        d.maximal.Sort(AlphaMiner.Compare);
        SortedSet<string> starts = new SortedSet<string>(StringComparer.Ordinal),
                          ends = new SortedSet<string>(StringComparer.Ordinal);
        foreach (Dfg.Trace trace in log) {
            starts.Add(trace.activities[0]);
            ends.Add(trace.activities[^1]);
        }
        d.starts = new(starts);
        d.ends = new(ends);
        List<string> places = new();
        places.Add("start");
        for (int i = 1; i <= d.maximal.Count; i++)
            places.Add("p" + i);
        places.Add("end");
        d.net = new Conformance.Net(places, names, 0, places.Count - 1);
        foreach (string t in starts)
            d.net.Arc("start", t);
        foreach (string t in ends)
            d.net.Arc(t, "end");
        for (int i = 0; i < d.maximal.Count; i++) {
            AlphaMiner.Candidate pair = d.maximal[i];
            string place = "p" + (i + 1);
            foreach (string a in MaskNames(pair.left, names))
                d.net.Arc(a, place);
            foreach (string b in MaskNames(pair.right, names))
                d.net.Arc(place, b);
        }
        return d;
    }
    public static string PairsLine(Discovery d) {
        return "PAIRS causal " + d.causal + " candidates " + d.candidates + " maximal " +
               d.maximal.Count;
    }
    public static List<string> NetLines(Discovery d) {
        List<string> lines = new();
        Conformance.Net net = d.net;
        lines.Add("PLACE start - " + Names(d.starts));
        for (int i = 0; i < d.maximal.Count; i++) {
            AlphaMiner.Candidate pair = d.maximal[i];
            lines.Add("PLACE p" + (i + 1) + " " + Names(MaskNames(pair.left, d.activities)) + " " +
                      Names(MaskNames(pair.right, d.activities)));
        }
        lines.Add("PLACE end " + Names(d.ends) + " -");
        for (int t = 0; t < net.transitions.Count; t++) {
            List<string> ins = new(), outs = new();
            foreach (int p in net.inputs[t])
                ins.Add(net.places[p]);
            foreach (int p in net.outputs[t])
                outs.Add(net.places[p]);
            lines.Add("TRANSITION " + net.transitions[t] + " in " + Names(ins) + " out " +
                      Names(outs));
        }
        lines.Add("NET places " + net.places.Count + " transitions " + net.transitions.Count +
                  " arcs " + net.Arcs());
        return lines;
    }
    public static List<string> Workflows() {
        Dictionary<Dfg.Pair, long> follows = Dfg.Counts(filtered);
        SortedSet<string> used = new SortedSet<string>(StringComparer.Ordinal);
        foreach (Dfg.Trace trace in filtered)
            used.UnionWith(trace.activities);
        List<string> names = new(used), loops = new();
        foreach (string name in names)
            if (Dfg.Count(follows, name, name) > 0)
                loops.Add(name);
        Discovery alpha = Discover(filtered, names, Relation(names, follows, null));
        List<string> lines = new();
        lines.Add("LOG variants " + filtered.Count + " cases " + keptCases + " activities " +
                  Names(names));
        lines.Add("LOOPS " + Names(loops));
        lines.Add("MINER alpha");
        lines.AddRange(Dfg.Footprint(names, alpha.relation));
        lines.Add(PairsLine(alpha));
        lines.AddRange(NetLines(alpha));
        List<string> retained = new(names);
        retained.RemoveAll(loops.Contains);
        List<Dfg.Trace> reduced = new();
        foreach (Dfg.Trace trace in filtered) {
            List<string> sequence = new();
            foreach (string name in trace.activities)
                if (!loops.Contains(name))
                    sequence.Add(name);
            reduced.Add(new Dfg.Trace(sequence, trace.weight));
        }
        Dictionary<Dfg.Pair, long> reducedCounts = Dfg.Counts(reduced),
                                   triangles = AlphaMiner.Triangles(reduced);
        Discovery plus = Discover(reduced, retained, Relation(retained, reducedCounts, triangles));
        lines.Add("MINER alpha_plus");
        foreach (Dfg.Pair pair in PairOrder(triangles, false))
            lines.Add("TRIANGLE " + pair.first + " " + pair.second + " count " + triangles[pair]);
        lines.AddRange(Dfg.Footprint(retained, plus.relation));
        lines.Add(PairsLine(plus));
        Conformance.Net expanded =
            new Conformance.Net(plus.net.places, names, plus.net.initial, plus.net.finish);
        for (int t = 0; t < plus.net.transitions.Count; t++) {
            string transition = plus.net.transitions[t];
            foreach (int place in plus.net.inputs[t])
                expanded.Arc(plus.net.places[place], transition);
            foreach (int place in plus.net.outputs[t])
                expanded.Arc(transition, plus.net.places[place]);
        }
        foreach (string loop in loops) {
            int before = 0, after = 0;
            for (int i = 0; i < retained.Count; i++) {
                if (Dfg.Count(follows, retained[i], loop) > 0)
                    before |= 1 << i;
                if (Dfg.Count(follows, loop, retained[i]) > 0)
                    after |= 1 << i;
            }
            string place = "-";
            for (int i = 0; i < plus.maximal.Count; i++) {
                AlphaMiner.Candidate pair = plus.maximal[i];
                if (pair.left == before && pair.right == after) {
                    place = "p" + (i + 1);
                    expanded.Arc(place, loop);
                    expanded.Arc(loop, place);
                    break;
                }
            }
            lines.Add("LOOP " + loop + " before " + Names(MaskNames(before, retained)) + " after " +
                      Names(MaskNames(after, retained)) + " place " + place);
        }
        plus.net = expanded;
        lines.AddRange(NetLines(plus));
        nets.Add(reference);
        nets.Add(alpha.net);
        nets.Add(plus.net);
        return lines;
    }
    public static List<string> Heuristic() {
        List<string> lines = new();
        HashSet<string> loops1 = new();
        HashSet<Dfg.Pair> loops2 = new(), edges = new();
        Dictionary<Dfg.Pair, long> triangles = AlphaMiner.Triangles(log);
        long minimum = Parameter("positive_observations");
        foreach (string a in activities) {
            long count = Dfg.Count(counts, a, a);
            if (count == 0)
                continue;
            Report.Fraction measure = HeuristicMiner.Loop(count);
            bool accepted =
                count >= minimum && measure.CompareTo(Threshold("loop1_threshold")) >= 0;
            if (accepted) {
                loops1.Add(a);
                edges.Add(new Dfg.Pair(a, a));
            }
            lines.Add("L1 " + a + " count " + count + " measure " + Fraction(measure) + " " +
                      (accepted ? "ACCEPT" : "REJECT"));
        }
        for (int i = 0; i < activities.Count; i++)
            for (int j = i + 1; j < activities.Count; j++) {
                string a = activities[i], b = activities[j];
                long count = Dfg.Count(triangles, a, b) + Dfg.Count(triangles, b, a);
                if (loops1.Contains(a) || loops1.Contains(b) || count == 0)
                    continue;
                Report.Fraction measure = HeuristicMiner.Loop(count);
                bool accepted =
                    count >= minimum && measure.CompareTo(Threshold("loop2_threshold")) >= 0;
                if (accepted)
                    loops2.Add(new Dfg.Pair(a, b));
                lines.Add("L2 " + a + " " + b + " count " + count + " measure " +
                          Fraction(measure) + " " + (accepted ? "ACCEPT" : "REJECT"));
            }
        Dictionary<Dfg.Pair, Report.Fraction> measures = new();
        Dictionary<string, Report.Fraction> bestOut = new(), bestIn = new();
        foreach (Dfg.Pair pair in counts.Keys)
            if (!pair.first.Equals(pair.second)) {
                Report.Fraction measure =
                    HeuristicMiner.Dependency(counts, pair.first, pair.second);
                measures[pair] = measure;
                if (!bestOut.ContainsKey(pair.first) || measure.CompareTo(bestOut[pair.first]) > 0)
                    bestOut[pair.first] = measure;
                if (!bestIn.ContainsKey(pair.second) || measure.CompareTo(bestIn[pair.second]) > 0)
                    bestIn[pair.second] = measure;
            }
        List<Dfg.Pair> pairs = new(measures.Keys);
        pairs.Sort(Dfg.Compare);
        foreach (Dfg.Pair pair in pairs) {
            string a = pair.first, b = pair.second;
            Report.Fraction measure = measures[pair];
            Dfg.Pair canonical = string.CompareOrdinal(a, b) < 0 ? pair : new Dfg.Pair(b, a);
            string verdict;
            if (loops2.Contains(canonical))
                verdict = "LOOP2";
            else if (counts[pair] < minimum)
                verdict = "REJECT_COUNT";
            else if (measure.CompareTo(Threshold("dependency_threshold")) < 0)
                verdict = "REJECT_MEASURE";
            else if (bestOut[a].Subtract(measure).CompareTo(Threshold("relative_to_best")) > 0 &&
                     bestIn[b].Subtract(measure).CompareTo(Threshold("relative_to_best")) > 0)
                verdict = "REJECT_BEST";
            else
                verdict = "ACCEPT";
            if (verdict.Equals("LOOP2") || verdict.Equals("ACCEPT"))
                edges.Add(pair);
            lines.Add("DEP " + a + " " + b + " count " + counts[pair] + " reverse " +
                      Dfg.Count(counts, b, a) + " measure " + Fraction(measure) + " " + verdict);
        }
        Dictionary<string, List<string>> inputs = new(), outputs = new();
        foreach (string a in activities) {
            List<string> ins = new(), outs = new();
            foreach (string b in activities) {
                if (edges.Contains(new Dfg.Pair(b, a)))
                    ins.Add(b);
                if (edges.Contains(new Dfg.Pair(a, b)))
                    outs.Add(b);
            }
            inputs[a] = ins;
            outputs[a] = outs;
            lines.Add("NODE " + a + " in " + Names(ins) + " out " + Names(outs));
        }
        foreach (string a in activities)
            for (int side = 0; side < 2; side++) {
                List<string> neighbors = new(side == 0 ? outputs[a] : inputs[a]);
                neighbors.Remove(a);
                for (int i = 0; i < neighbors.Count; i++)
                    for (int j = i + 1; j < neighbors.Count; j++) {
                        string b = neighbors[i], c = neighbors[j];
                        Report.Fraction measure = side == 0 ? HeuristicMiner.Split(counts, a, b, c)
                                                            : HeuristicMiner.Join(counts, a, b, c);
                        lines.Add(
                            (side == 0 ? "SPLIT" : "JOIN") + " " + a + " " + b + " " + c +
                            " measure " + Fraction(measure) + " " +
                            (measure.CompareTo(Threshold("and_threshold")) >= 0 ? "AND" : "XOR"));
                    }
            }
        lines.Add("GRAPH activities " + activities.Count + " edges " + edges.Count + " loops1 " +
                  loops1.Count + " loops2 " + loops2.Count);
        return lines;
    }
    public static Reach Explore(Conformance.Net net) {
        Reach result = new();
        List<int[]> markings = new() { net.InitialMarking() };
        List<List<int>> reverse = new() { new() };
        List<Edge> edges = new();
        Dictionary<string, int> indices = new() { [string.Join(",", markings[0])] = 0 };
        bool[] enabledEver = new bool[net.transitions.Count];
        for (int index = 0; index < markings.Count; index++) {
            int[] marking = markings[index];
            bool enabled = false;
            for (int t = 0; t < net.transitions.Count; t++)
                if (Conformance.Enabled(net, marking, t)) {
                    enabled = true;
                    enabledEver[t] = true;
                    int[] after = Conformance.Fire(net, marking, t);
                    bool safe = true;
                    foreach (int count in after)
                        if (count > 1)
                            safe = false;
                    if (!safe) {
                        result.unsafeCount++;
                        continue;
                    }
                    string key = string.Join(",", after);
                    if (!indices.TryGetValue(key, out int destination)) {
                        destination = markings.Count;
                        indices[key] = destination;
                        markings.Add(after);
                        reverse.Add(new());
                    }
                    edges.Add(new Edge(index, t, destination));
                    reverse[destination].Add(index);
                }
            if (!enabled && !marking.SequenceEqual(net.FinalMarking()))
                result.deadlocks++;
        }
        bool final = indices.TryGetValue(string.Join(",", net.FinalMarking()), out int terminal);
        result.terminal = final;
        bool[] reachable = new bool[markings.Count];
        Queue<int> queue = new();
        if (final) {
            reachable[terminal] = true;
            queue.Enqueue(terminal);
        }
        while (queue.Count != 0) {
            int at = queue.Dequeue();
            foreach (int before in reverse[at])
                if (!reachable[before]) {
                    reachable[before] = true;
                    queue.Enqueue(before);
                }
        }
        foreach (bool value in reachable)
            if (!value)
                result.stuck++;
        for (int t = 0; t < enabledEver.Length; t++)
            if (!enabledEver[t])
                result.dead.Add(net.transitions[t]);
        foreach (Edge edge in edges)
            for (int t = 0; t < net.transitions.Count; t++)
                if (Conformance.Enabled(net, markings[edge.to], t))
                    result.follows[new Dfg.Pair(net.transitions[edge.transition],
                                                net.transitions[t])] = 1;
        result.markings = markings.Count;
        result.edges = edges.Count;
        result.sound = result.unsafeCount == 0 && result.stuck == 0 && result.dead.Count == 0;
        return result;
    }
    public static string ReachLine(string name, Reach r) {
        return "REACHABILITY " + name + " markings " + r.markings + " edges " + r.edges +
               " unsafe " + r.unsafeCount + " deadlocks " + r.deadlocks + " stuck " + r.stuck +
               " final " + Yes(r.terminal) + " dead " + Names(r.dead) + " sound " + Yes(r.sound);
    }
    public static List<string> FootprintLines(string name, Conformance.Net net, Reach reach) {
        SortedSet<string> union
        = new SortedSet<string>(activities, StringComparer.Ordinal);
        union
        .UnionWith(net.transitions);
        List<string> names = new(union), differences = new();
        int differing = 0;
        foreach (string a in names)
            foreach (string b in names) {
                string observed = Dfg.Basic(counts, a, b), model = Dfg.Basic(reach.follows, a, b);
                if (!observed.Equals(model)) {
                    differing++;
                    if (name.Equals("reference") && string.CompareOrdinal(a, b) <= 0)
                        differences.Add("DIFF " + a + " " + b + " log " + observed + " model " +
                                        model);
                }
            }
        int cells = names.Count * names.Count;
        List<string> lines = new();
        lines.Add("FOOTPRINT " + name + " activities " + names.Count + " cells " + cells +
                  " differing " + differing + " fitness " + Fraction(cells - differing, cells));
        lines.AddRange(differences);
        return lines;
    }
    public static Dictionary<List<string>, Prefix> Prefixes() {
        Dictionary<List<string>, Prefix> result = new(new Eventlog.TraceComparer());
        foreach (Eventlog.Case c in cases)
            for (int length = 0; length <= c.trace.Count; length++) {
                List<string> key = c.trace.GetRange(0, length - 0).ToList();
                Prefix prefix = result.GetOrAdd(key, k => new Prefix());
                prefix.weight++;
                if (length < c.trace.Count)
                    prefix.followers.Add(c.trace[length]);
            }
        return result;
    }
    public static List<string> Precision(string name, Conformance.Net net,
                                         Dictionary<List<string>, Prefix> prefixes) {
        long fitting = 0, allowed = 0, escaping = 0;
        Dictionary<string, long> escapeWeights = new();
        List<List<string>> order = new(prefixes.Keys);
        order.Sort(CompareTrace);
        Dictionary<List<string>, int[]> states = new(new Eventlog.TraceComparer());
        foreach (List<string> prefix in order) {
            int[] marking = net.InitialMarking();
            if (prefix.Count != 0) {
                marking = states[prefix.GetRange(0, prefix.Count - 1 - 0)];
                int t = net.transitionIndex.GetValueOrDefault(prefix[^1], -1);
                if (marking != null && t >= 0 && Conformance.Enabled(net, marking, t))
                    marking = Conformance.Fire(net, marking, t);
                else
                    marking = null;
            }
            states[prefix] = marking;
            if (marking == null)
                continue;
            fitting++;
            Prefix value = prefixes[prefix];
            for (int t = 0; t < net.transitions.Count; t++)
                if (Conformance.Enabled(net, marking, t)) {
                    allowed += value.weight;
                    string transition = net.transitions[t];
                    if (!value.followers.Contains(transition)) {
                        escaping += value.weight;
                        Add(escapeWeights, transition, value.weight);
                    }
                }
        }
        List<string> lines = new();
        lines.Add("PRECISION " + name + " prefixes " + fitting + " allowed " + allowed +
                  " escaping " + escaping + " precision " +
                  Fraction(allowed == 0 ? 1 : allowed - escaping, allowed == 0 ? 1 : allowed));
        foreach (string transition in NameOrder(escapeWeights))
            lines.Add("ESCAPE " + name + " " + transition + " weight " + escapeWeights[transition]);
        return lines;
    }
    public static Conformance.Totals ReplayCase(Conformance.Net net, Eventlog.Case c) {
        Conformance.Totals r = new Conformance.Totals(net.places.Count, net.transitions.Count);
        List<Queue<int>> tokens = new();
        foreach (string place in net.places)
            tokens.Add(new());
        tokens[net.initial].Enqueue(c.events[0].time);
        r.produced = 1;
        foreach (Eventlog.Event eventInfo in c.events) {
            int transition = net.transitionIndex.GetValueOrDefault(eventInfo.activity, -1);
            if (transition < 0) {
                r.skipped++;
                continue;
            }
            foreach (int place in net.inputs[transition]) {
                r.consumed++;
                if (tokens[place].Count != 0) {
                    int produced = tokens[place].Dequeue(), wait = eventInfo.time - produced;
                    r.waitingCount[place]++;
                    r.waitingSum[place] += wait;
                    r.waitingMax[place] = Math.Max(r.waitingMax[place], wait);
                    r.routes[place][transition]++;
                } else {
                    r.missing++;
                    r.placeMissing[place]++;
                }
            }
            foreach (int place in net.outputs[transition]) {
                tokens[place].Enqueue(eventInfo.time);
                r.produced++;
            }
        }
        r.consumed++;
        if (tokens[net.finish].Count != 0)
            tokens[net.finish].Dequeue();
        else {
            r.missing++;
            r.placeMissing[net.finish]++;
        }
        for (int place = 0; place < net.places.Count; place++) {
            long remaining = tokens[place].Count;
            r.placeRemaining[place] = remaining;
            r.remaining += remaining;
            r.deviating[place] = r.placeMissing[place] > 0 || remaining > 0 ? 1 : 0;
        }
        return r;
    }
    public static List<string> ReplayLines(string name, Conformance.Net net) {
        Conformance.Totals total = new Conformance.Totals(net.places.Count, net.transitions.Count);
        int fitting = 0;
        foreach (Eventlog.Case c in cases) {
            Conformance.Totals r = ReplayCase(net, c);
            if (name.Equals("reference"))
                referenceReplays[c.id] = r;
            if (r.missing == 0 && r.remaining == 0)
                fitting++;
            total.missing += r.missing;
            total.remaining += r.remaining;
            total.consumed += r.consumed;
            total.produced += r.produced;
            total.skipped += r.skipped;
            for (int place = 0; place < net.places.Count; place++) {
                total.placeMissing[place] += r.placeMissing[place];
                total.placeRemaining[place] += r.placeRemaining[place];
                total.deviating[place] += r.deviating[place];
                total.waitingCount[place] += r.waitingCount[place];
                total.waitingSum[place] += r.waitingSum[place];
                total.waitingMax[place] = Math.Max(total.waitingMax[place], r.waitingMax[place]);
                for (int t = 0; t < net.transitions.Count; t++)
                    total.routes[place][t] += r.routes[place][t];
            }
        }
        List<string> lines = new();
        lines.Add("REPLAY " + name + " cases " + cases.Count + " fitting " + fitting + " skipped " +
                  total.skipped + " missing " + total.missing + " remaining " + total.remaining +
                  " consumed " + total.consumed + " produced " + total.produced + " fitness " +
                  Fraction(total.Fitness()));
        for (int p = 0; p < net.places.Count; p++)
            lines.Add("PLACE " + name + " " + net.places[p] + " missing " + total.placeMissing[p] +
                      " remaining " + total.placeRemaining[p] + " deviating " + total.deviating[p] +
                      " tokens " + total.waitingCount[p] + " mean " +
                      (total.waitingCount[p] == 0
                           ? "-"
                           : Fraction(total.waitingSum[p], total.waitingCount[p])) +
                      " max " +
                      (total.waitingCount[p] == 0 ? "-" : Convert.ToString(total.waitingMax[p])));
        for (int p = 0; p < net.places.Count; p++) {
            List<string> routes = new();
            for (int t = 0; t < net.transitions.Count; t++)
                if (net.inputs[t].Contains(p))
                    routes.Add(net.transitions[t] + "=" + total.routes[p][t]);
            if (routes.Count >= 2)
                lines.Add("ROUTE " + name + " " + net.places[p] + " " + string.Join(",", routes));
        }
        return lines;
    }
    public static List<string> BuildConformanceReport() {
        List<string> lines = new();
        lines.Add("MODEL places " + reference.places.Count + " transitions " +
                  reference.transitions.Count + " arcs " + reference.Arcs());
        List<Reach> reaches = new();
        for (int i = 0; i < 3; i++) {
            Reach r = Explore(nets[i]);
            reaches.Add(r);
            lines.Add(ReachLine(NET_NAMES[i], r));
        }
        for (int i = 0; i < 3; i++)
            lines.AddRange(FootprintLines(NET_NAMES[i], nets[i], reaches[i]));
        Dictionary<List<string>, Prefix> prefixes = Prefixes();
        for (int i = 0; i < 3; i++)
            lines.AddRange(Precision(NET_NAMES[i], nets[i], prefixes));
        for (int i = 0; i < 3; i++)
            lines.AddRange(ReplayLines(NET_NAMES[i], nets[i]));
        return lines;
    }
    public static List<string> Csv() {
        List<string> lines = new();
        lines.Add("case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness");
        foreach (Eventlog.Case c in cases) {
            Conformance.Totals r = referenceReplays[c.id];
            lines.Add(c.id + "," + variantIds[c.id] + "," + c.events.Count + "," + r.skipped + "," +
                      r.missing + "," + r.remaining + "," + r.consumed + "," + r.produced + "," +
                      Fraction(r.Fitness()));
        }
        return lines;
    }
    public static List<string> ResourceLines() {
        Dictionary<string, long> eventCount = new(), caseCount = new();
        Dictionary<Dfg.Pair, long> work = new(), handovers = new(), handoverCases = new(),
                                   subcontracts = new(), together = new();
        foreach (Eventlog.Case c in cases) {
            SortedSet<string> present = new SortedSet<string>(StringComparer.Ordinal);
            HashSet<Dfg.Pair> pairs = new();
            for (int i = 0; i < c.events.Count; i++) {
                Eventlog.Event e = c.events[i];
                present.Add(e.resource);
                Add(eventCount, e.resource, 1);
                Add(work, new Dfg.Pair(e.resource, e.activity), 1);
                if (i > 0) {
                    Dfg.Pair pair = new Dfg.Pair(c.events[i - 1].resource, e.resource);
                    Add(handovers, pair, 1);
                    pairs.Add(pair);
                }
                if (i > 1) {
                    string a = c.events[i - 2].resource, b = c.events[i - 1].resource;
                    if (a.Equals(e.resource) && !a.Equals(b))
                        Add(subcontracts, new Dfg.Pair(a, b), 1);
                }
            }
            foreach (string worker in present)
                Add(caseCount, worker, 1);
            foreach (Dfg.Pair pair in pairs)
                Add(handoverCases, pair, 1);
            List<string> workers = new(present);
            for (int i = 0; i < workers.Count; i++)
                for (int j = i + 1; j < workers.Count; j++)
                    Add(together, new Dfg.Pair(workers[i], workers[j]), 1);
        }
        List<string> lines = new();
        for (int i = 0; i < resources.Count; i++) {
            string resource = resources[i];
            List<string> tasks = new();
            foreach (string activity in activities) {
                long count = Dfg.Count(work, resource, activity);
                if (count > 0)
                    tasks.Add(activity + "=" + count);
            }
            lines.Add("RESOURCE " + (i + 1) + " " + resource + " events " +
                      Get(eventCount, resource) + " cases " + Get(caseCount, resource) + " work " +
                      string.Join(",", tasks));
        }
        foreach (Dfg.Pair pair in PairOrder(handovers, true))
            if (!pair.first.Equals(pair.second))
                lines.Add("HANDOVER " + pair.first + " " + pair.second + " count " +
                          handovers[pair] + " cases " + Get(handoverCases, pair));
        List<List<string>> rows = new();
        foreach (string a in resources) {
            List<string> row = new();
            foreach (string b in resources)
                row.Add(Convert.ToString(Dfg.Count(handovers, a, b)));
            rows.Add(row);
        }
        lines.AddRange(Dfg.Table(rows, 5));
        foreach (Dfg.Pair pair in PairOrder(subcontracts, true))
            lines.Add("SUBCONTRACT " + pair.first + " " + pair.second + " count " +
                      subcontracts[pair]);
        foreach (Dfg.Pair pair in PairOrder(together, true))
            lines.Add("TOGETHER " + pair.first + " " + pair.second + " cases " + together[pair]);
        long total = 0, own = 0;
        foreach (var entry in handovers) {
            total += entry.Value;
            if (entry.Key.first.Equals(entry.Key.second))
                own += entry.Value;
        }
        lines.Add("TOTAL handovers " + total + " self " + own + " other " + (total - own));
        return lines;
    }
    public static void Main(string[] args) {
        input = Eventlog.Read();
        reference = Conformance.Read();
        Prepare();
        List<string> workflow = Workflows(), checks = BuildConformanceReport();
        Report.Write("log_summary.txt", LogSummary());
        Report.Write("variants.txt", VariantLines());
        Report.Write("dfg.txt", DfgLines());
        Report.Write("alpha_net.txt", workflow);
        Report.Write("heuristic_net.txt", Heuristic());
        Report.Write("conformance.csv", Csv());
        Report.Write("conformance.txt", checks);
        Report.Write("resources.txt", ResourceLines());
    }
}
