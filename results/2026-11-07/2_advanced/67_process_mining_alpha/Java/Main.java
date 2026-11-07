import java.util.*;
public final class Main {
    static Eventlog.Input input;
    static Conformance.Net reference;
    static List<Eventlog.Event> events = new ArrayList<>();
    static List<Eventlog.Case> cases;
    static List<String> activities, resources;
    static List<String> errors = new ArrayList<>();
    static List<Dfg.Trace> log = new ArrayList<>(), filtered = new ArrayList<>();
    static Map<Dfg.Pair, Long> counts;
    static List<Variant> variants = new ArrayList<>();
    static Map<String, Integer> variantIds = new HashMap<>();
    static int keptCases, keptEvents;
    static List<Conformance.Net> nets = new ArrayList<>();
    static final String[] NET_NAMES = {"reference", "alpha", "alpha_plus"};
    static Map<String, Conformance.Totals> referenceReplays = new HashMap<>();
    record Identity(String id, String activity, String timestamp) {}
    static final class Variant {
        int number;
        List<String> trace;
        List<Eventlog.Case> cases;
        boolean keep;
        Variant(List<String> trace, List<Eventlog.Case> cases) {
            this.trace = trace;
            this.cases = cases;
        }
    }
    static final class Discovery {
        Conformance.Net net;
        List<String> activities, starts, ends;
        String[][] relation;
        List<AlphaMiner.Candidate> maximal;
        int candidates, causal;
    }
    record Edge(int from, int transition, int to) {}
    static final class Reach {
        int markings, edges, unsafe, deadlocks, stuck;
        boolean terminal, sound;
        List<String> dead = new ArrayList<>();
        Map<Dfg.Pair, Long> follows = new HashMap<>();
    }
    static final class Prefix {
        long weight;
        TreeSet<String> followers = new TreeSet<>();
    }
    static long parameter(String name) { return Long.parseLong(input.parameters().get(name)); }
    static Report.Fraction threshold(String name) {
        return Report.parse(input.parameters().get(name));
    }
    static String fraction(long a, long b) { return Report.fraction(a, b); }
    static String fraction(Report.Fraction value) { return Report.fraction(value); }
    static String names(Collection<String> values) { return Report.names(values); }
    static String yes(boolean value) { return value ? "yes" : "no"; }
    static <K> void add(Map<K, Long> map, K key, long value) { map.merge(key, value, Long::sum); }
    static <K> long get(Map<K, Long> map, K key) { return map.getOrDefault(key, 0L); }
    static int compareTrace(List<String> a, List<String> b) {
        for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
            int c = a.get(i).compareTo(b.get(i));
            if (c != 0)
                return c;
        }
        return Integer.compare(a.size(), b.size());
    }
    static List<Dfg.Pair> pairOrder(Map<Dfg.Pair, Long> values, boolean frequency) {
        List<Dfg.Pair> pairs = new ArrayList<>(values.keySet());
        pairs.sort((a, b) -> {
            int c = frequency ? Long.compare(values.get(b), values.get(a)) : 0;
            return c != 0 ? c : Dfg.compare(a, b);
        });
        return pairs;
    }
    static List<String> nameOrder(Map<String, Long> values) {
        List<String> result = new ArrayList<>(values.keySet());
        result.sort((a, b) -> {
            int c = Long.compare(values.get(b), values.get(a));
            return c != 0 ? c : a.compareTo(b);
        });
        return result;
    }
    static <K> void waitValue(Map<K, List<Integer>> values, K key, int value) {
        values.computeIfAbsent(key, k -> new ArrayList<>()).add(value);
    }
    static long sum(List<Integer> values) {
        long total = 0;
        for (int value : values)
            total += value;
        return total;
    }
    static String mean(List<Integer> values) {
        return values.isEmpty() ? "-" : fraction(sum(values), values.size());
    }
    static void prepare() {
        Set<Identity> adopted = new HashSet<>();
        TreeSet<String> allActivities = new TreeSet<>(), allResources = new TreeSet<>();
        for (Eventlog.Row row : input.rows()) {
            int time = Eventlog.timestamp(row.timestamp());
            if (time < 0) {
                errors.add("line " + row.line() + ": bad timestamp " + row.timestamp());
                continue;
            }
            Identity identity = new Identity(row.caseId(), row.activity(), row.timestamp());
            if (!adopted.add(identity)) {
                errors.add("line " + row.line() + ": duplicate event " + row.caseId() + " " +
                           row.activity() + " " + row.timestamp());
                continue;
            }
            events.add(new Eventlog.Event(row.line(), row.caseId(), row.activity(), row.timestamp(),
                                          row.resource(), time));
            allActivities.add(row.activity());
            allResources.add(row.resource());
        }
        activities = new ArrayList<>(allActivities);
        resources = new ArrayList<>(allResources);
        cases = Eventlog.group(events);
        for (Eventlog.Case c : cases)
            log.add(new Dfg.Trace(c.trace, 1));
        counts = Dfg.counts(log);
        Map<List<String>, List<Eventlog.Case>> grouped = new HashMap<>();
        for (Eventlog.Case c : cases)
            grouped.computeIfAbsent(c.trace, k -> new ArrayList<>()).add(c);
        for (var entry : grouped.entrySet())
            variants.add(new Variant(entry.getKey(), entry.getValue()));
        variants.sort((a, b) -> {
            int order = Integer.compare(b.cases.size(), a.cases.size());
            return order != 0 ? order : compareTrace(a.trace, b.trace);
        });
        for (int i = 0; i < variants.size(); i++) {
            Variant v = variants.get(i);
            v.number = i + 1;
            v.keep = true;
            for (int j = 1; j < v.trace.size(); j++)
                if (Dfg.count(counts, v.trace.get(j - 1), v.trace.get(j)) <
                    parameter("filter_min_follows"))
                    v.keep = false;
            for (Eventlog.Case c : v.cases)
                variantIds.put(c.id, v.number);
            if (v.keep) {
                filtered.add(new Dfg.Trace(v.trace, v.cases.size()));
                keptCases += v.cases.size();
                keptEvents += v.trace.size() * v.cases.size();
            }
        }
    }
    static List<String> logSummary() {
        List<String> lines = new ArrayList<>();
        for (String error : errors)
            lines.add("ERROR " + error);
        Eventlog.Event earliest = events.getFirst(), latest = earliest;
        for (Eventlog.Event e : events) {
            if (e.time() < earliest.time())
                earliest = e;
            if (e.time() > latest.time())
                latest = e;
        }
        lines.add("LOG rows " + input.rows().size() + " adopted " + events.size() + " rejected " +
                  errors.size() + " cases " + cases.size() + " activities " + activities.size() +
                  " resources " + resources.size() + " first " + earliest.timestamp() + " last " +
                  latest.timestamp());
        Map<String, Long> eventCount = new HashMap<>(), caseCount = new HashMap<>(),
                          starts = new HashMap<>(), ends = new HashMap<>(),
                          rework = new HashMap<>();
        Map<String, List<Integer>> waits = new HashMap<>();
        Map<String, TreeSet<String>> workers = new HashMap<>();
        long[] weekdayEvents = new long[7], weekdayStarts = new long[7], weekdayEnds = new long[7];
        List<Integer> lengths = new ArrayList<>(), durations = new ArrayList<>();
        for (Eventlog.Case c : cases) {
            lengths.add(c.events.size());
            durations.add(c.duration);
            Map<String, Long> occurrences = new HashMap<>();
            for (String name : c.trace)
                add(occurrences, name, 1);
            for (var entry : occurrences.entrySet()) {
                add(caseCount, entry.getKey(), 1);
                if (entry.getValue() >= 2)
                    add(rework, entry.getKey(), 1);
            }
            add(starts, c.trace.getFirst(), 1);
            add(ends, c.trace.getLast(), 1);
            weekdayStarts[(c.events.getFirst().time() / 1440 + 3) % 7]++;
            weekdayEnds[(c.events.getLast().time() / 1440 + 3) % 7]++;
            for (int i = 0; i < c.events.size(); i++) {
                Eventlog.Event e = c.events.get(i);
                add(eventCount, e.activity(), 1);
                workers.computeIfAbsent(e.activity(), k -> new TreeSet<>()).add(e.resource());
                weekdayEvents[(e.time() / 1440 + 3) % 7]++;
                if (i > 0)
                    waitValue(waits, e.activity(), e.time() - c.events.get(i - 1).time());
            }
        }
        for (String name : activities)
            lines.add("ACTIVITY " + name + " events " + get(eventCount, name) + " cases " +
                      get(caseCount, name) + " start " + get(starts, name) + " end " +
                      get(ends, name) + " rework " + get(rework, name) + " wait " +
                      mean(waits.getOrDefault(name, List.of())) + " resources " +
                      workers.get(name).size() + " model " +
                      yes(reference.transitionIndex.containsKey(name)));
        for (int i = 0; i < 2; i++) {
            List<Integer> values = i == 0 ? lengths : durations;
            lines.add((i == 0 ? "LENGTH" : "DURATION") + " min " + Collections.min(values) +
                      " max " + Collections.max(values) + " mean " + mean(values) + " median " +
                      fraction(Eventlog.median(values)));
        }
        int maxDays = Collections.max(durations) / 1440;
        int[] days = new int[maxDays + 1];
        int late = 0;
        for (int duration : durations) {
            days[duration / 1440]++;
            if (duration > parameter("sla_minutes"))
                late++;
        }
        for (int d = 0; d < days.length; d++)
            lines.add("DAYS " + d + " cases " + days[d] + " share " +
                      Report.percentage(days[d], cases.size()));
        lines.add("SLA limit " + parameter("sla_minutes") + " late " + late + " share " +
                  Report.percentage(late, cases.size()));
        String[] weekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
        for (int i = 0; i < 7; i++)
            lines.add("WEEKDAY " + weekdays[i] + " events " + weekdayEvents[i] + " starts " +
                      weekdayStarts[i] + " ends " + weekdayEnds[i]);
        return lines;
    }
    static List<String> variantLines() {
        List<String> lines = new ArrayList<>();
        for (Variant v : variants) {
            List<Integer> durations = new ArrayList<>();
            int late = 0;
            for (Eventlog.Case c : v.cases) {
                durations.add(c.duration);
                if (c.duration > parameter("sla_minutes"))
                    late++;
            }
            lines.add("VARIANT " + v.number + " count " + v.cases.size() + " share " +
                      Report.percentage(v.cases.size(), cases.size()) + " length " +
                      v.trace.size() + " first " + v.cases.getFirst().id + " duration " +
                      mean(durations) + " late " + late + " fitness " +
                      fraction(referenceReplays.get(v.cases.getFirst().id).fitness()) + " " +
                      (v.keep ? "KEEP" : "DROP") + " " + names(v.trace));
        }
        lines.add("FILTER min_follows " + parameter("filter_min_follows") + " variants " +
                  filtered.size() + " of " + variants.size() + " cases " + keptCases + " of " +
                  cases.size() + " events " + keptEvents + " of " + events.size());
        return lines;
    }
    static String[][] relation(List<String> names, Map<Dfg.Pair, Long> counts,
                               Map<Dfg.Pair, Long> triangles) {
        String[][] result = new String[names.size()][names.size()];
        for (int i = 0; i < names.size(); i++)
            for (int j = 0; j < names.size(); j++)
                result[i][j] = triangles == null
                                   ? Dfg.basic(counts, names.get(i), names.get(j))
                                   : AlphaMiner.plus(counts, triangles, names.get(i), names.get(j));
        return result;
    }
    static List<String> dfgLines() {
        Map<String, Long> starts = new HashMap<>(), endCount = new HashMap<>();
        Map<String, List<Integer>> ends = new HashMap<>();
        Map<Dfg.Pair, List<Integer>> waiting = new HashMap<>();
        Map<Dfg.Pair, Long> edgeCases = new HashMap<>();
        for (Eventlog.Case c : cases) {
            add(starts, c.trace.getFirst(), 1);
            add(endCount, c.trace.getLast(), 1);
            waitValue(ends, c.trace.getLast(), c.duration);
            Set<Dfg.Pair> present = new HashSet<>();
            for (int i = 1; i < c.events.size(); i++) {
                Eventlog.Event a = c.events.get(i - 1), b = c.events.get(i);
                Dfg.Pair pair = new Dfg.Pair(a.activity(), b.activity());
                waitValue(waiting, pair, b.time() - a.time());
                present.add(pair);
            }
            for (Dfg.Pair pair : present)
                add(edgeCases, pair, 1);
        }
        List<String> lines = new ArrayList<>();
        for (String name : nameOrder(starts))
            lines.add("START " + name + " count " + get(starts, name));
        for (String name : nameOrder(endCount))
            lines.add("END " + name + " count " + get(endCount, name) + " duration " +
                      mean(ends.get(name)));
        for (Dfg.Pair pair : pairOrder(counts, true)) {
            List<Integer> values = waiting.get(pair);
            lines.add("EDGE " + pair.first() + " " + pair.second() + " count " + counts.get(pair) +
                      " cases " + get(edgeCases, pair) + " mean " + mean(values) + " min " +
                      Collections.min(values) + " max " + Collections.max(values));
        }
        lines.addAll(Dfg.footprint(activities, relation(activities, counts, null)));
        return lines;
    }
    static List<String> maskNames(int mask, List<String> names) {
        List<String> result = new ArrayList<>();
        for (int i = 0; i < names.size(); i++)
            if ((mask & (1 << i)) != 0)
                result.add(names.get(i));
        return result;
    }
    static Discovery discover(List<Dfg.Trace> log, List<String> names, String[][] relation) {
        Discovery d = new Discovery();
        d.activities = names;
        d.relation = relation;
        Set<AlphaMiner.Candidate> candidates = new HashSet<>();
        ArrayDeque<AlphaMiner.Candidate> queue = new ArrayDeque<>();
        for (int a = 0; a < names.size(); a++)
            for (int b = 0; b < names.size(); b++)
                if (relation[a][b].equals("->")) {
                    d.causal++;
                    if (relation[a][a].equals("#") && relation[b][b].equals("#")) {
                        AlphaMiner.Candidate pair = new AlphaMiner.Candidate(1 << a, 1 << b);
                        if (candidates.add(pair))
                            queue.add(pair);
                    }
                }
        while (!queue.isEmpty()) {
            AlphaMiner.Candidate pair = queue.removeFirst();
            for (int a = 0; a < names.size(); a++)
                for (int side = 0; side < 2; side++) {
                    AlphaMiner.Candidate extended = AlphaMiner.extend(pair, a, side, relation);
                    if (extended != null && candidates.add(extended))
                        queue.add(extended);
                }
        }
        d.candidates = candidates.size();
        d.maximal = new ArrayList<>();
        for (AlphaMiner.Candidate pair : candidates) {
            boolean extended = false;
            for (int a = 0; a < names.size(); a++)
                for (int side = 0; side < 2; side++)
                    if (AlphaMiner.extend(pair, a, side, relation) != null)
                        extended = true;
            if (!extended)
                d.maximal.add(pair);
        }
        d.maximal.sort(AlphaMiner::compare);
        TreeSet<String> starts = new TreeSet<>(), ends = new TreeSet<>();
        for (Dfg.Trace trace : log) {
            starts.add(trace.activities().getFirst());
            ends.add(trace.activities().getLast());
        }
        d.starts = new ArrayList<>(starts);
        d.ends = new ArrayList<>(ends);
        List<String> places = new ArrayList<>();
        places.add("start");
        for (int i = 1; i <= d.maximal.size(); i++)
            places.add("p" + i);
        places.add("end");
        d.net = new Conformance.Net(places, names, 0, places.size() - 1);
        for (String t : starts)
            d.net.arc("start", t);
        for (String t : ends)
            d.net.arc(t, "end");
        for (int i = 0; i < d.maximal.size(); i++) {
            AlphaMiner.Candidate pair = d.maximal.get(i);
            String place = "p" + (i + 1);
            for (String a : maskNames(pair.left(), names))
                d.net.arc(a, place);
            for (String b : maskNames(pair.right(), names))
                d.net.arc(place, b);
        }
        return d;
    }
    static String pairsLine(Discovery d) {
        return "PAIRS causal " + d.causal + " candidates " + d.candidates + " maximal " +
            d.maximal.size();
    }
    static List<String> netLines(Discovery d) {
        List<String> lines = new ArrayList<>();
        Conformance.Net net = d.net;
        lines.add("PLACE start - " + names(d.starts));
        for (int i = 0; i < d.maximal.size(); i++) {
            AlphaMiner.Candidate pair = d.maximal.get(i);
            lines.add("PLACE p" + (i + 1) + " " + names(maskNames(pair.left(), d.activities)) +
                      " " + names(maskNames(pair.right(), d.activities)));
        }
        lines.add("PLACE end " + names(d.ends) + " -");
        for (int t = 0; t < net.transitions.size(); t++) {
            List<String> ins = new ArrayList<>(), outs = new ArrayList<>();
            for (int p : net.inputs.get(t))
                ins.add(net.places.get(p));
            for (int p : net.outputs.get(t))
                outs.add(net.places.get(p));
            lines.add("TRANSITION " + net.transitions.get(t) + " in " + names(ins) + " out " +
                      names(outs));
        }
        lines.add("NET places " + net.places.size() + " transitions " + net.transitions.size() +
                  " arcs " + net.arcs());
        return lines;
    }
    static List<String> workflows() {
        Map<Dfg.Pair, Long> follows = Dfg.counts(filtered);
        TreeSet<String> used = new TreeSet<>();
        for (Dfg.Trace trace : filtered)
            used.addAll(trace.activities());
        List<String> names = new ArrayList<>(used), loops = new ArrayList<>();
        for (String name : names)
            if (Dfg.count(follows, name, name) > 0)
                loops.add(name);
        Discovery alpha = discover(filtered, names, relation(names, follows, null));
        List<String> lines = new ArrayList<>();
        lines.add("LOG variants " + filtered.size() + " cases " + keptCases + " activities " +
                  names(names));
        lines.add("LOOPS " + names(loops));
        lines.add("MINER alpha");
        lines.addAll(Dfg.footprint(names, alpha.relation));
        lines.add(pairsLine(alpha));
        lines.addAll(netLines(alpha));
        List<String> retained = new ArrayList<>(names);
        retained.removeAll(loops);
        List<Dfg.Trace> reduced = new ArrayList<>();
        for (Dfg.Trace trace : filtered) {
            List<String> sequence = new ArrayList<>();
            for (String name : trace.activities())
                if (!loops.contains(name))
                    sequence.add(name);
            reduced.add(new Dfg.Trace(sequence, trace.weight()));
        }
        Map<Dfg.Pair, Long> reducedCounts = Dfg.counts(reduced), triangles =
                                                                     AlphaMiner.triangles(reduced);
        Discovery plus = discover(reduced, retained, relation(retained, reducedCounts, triangles));
        lines.add("MINER alpha_plus");
        for (Dfg.Pair pair : pairOrder(triangles, false))
            lines.add("TRIANGLE " + pair.first() + " " + pair.second() + " count " +
                      triangles.get(pair));
        lines.addAll(Dfg.footprint(retained, plus.relation));
        lines.add(pairsLine(plus));
        Conformance.Net expanded =
            new Conformance.Net(plus.net.places, names, plus.net.initial, plus.net.finish);
        for (int t = 0; t < plus.net.transitions.size(); t++) {
            String transition = plus.net.transitions.get(t);
            for (int place : plus.net.inputs.get(t))
                expanded.arc(plus.net.places.get(place), transition);
            for (int place : plus.net.outputs.get(t))
                expanded.arc(transition, plus.net.places.get(place));
        }
        for (String loop : loops) {
            int before = 0, after = 0;
            for (int i = 0; i < retained.size(); i++) {
                if (Dfg.count(follows, retained.get(i), loop) > 0)
                    before |= 1 << i;
                if (Dfg.count(follows, loop, retained.get(i)) > 0)
                    after |= 1 << i;
            }
            String place = "-";
            for (int i = 0; i < plus.maximal.size(); i++) {
                AlphaMiner.Candidate pair = plus.maximal.get(i);
                if (pair.left() == before && pair.right() == after) {
                    place = "p" + (i + 1);
                    expanded.arc(place, loop);
                    expanded.arc(loop, place);
                    break;
                }
            }
            lines.add("LOOP " + loop + " before " + names(maskNames(before, retained)) + " after " +
                      names(maskNames(after, retained)) + " place " + place);
        }
        plus.net = expanded;
        lines.addAll(netLines(plus));
        nets.add(reference);
        nets.add(alpha.net);
        nets.add(plus.net);
        return lines;
    }
    static List<String> heuristic() {
        List<String> lines = new ArrayList<>();
        Set<String> loops1 = new HashSet<>();
        Set<Dfg.Pair> loops2 = new HashSet<>(), edges = new HashSet<>();
        Map<Dfg.Pair, Long> triangles = AlphaMiner.triangles(log);
        long minimum = parameter("positive_observations");
        for (String a : activities) {
            long count = Dfg.count(counts, a, a);
            if (count == 0)
                continue;
            Report.Fraction measure = HeuristicMiner.loop(count);
            boolean accepted =
                count >= minimum && measure.compareTo(threshold("loop1_threshold")) >= 0;
            if (accepted) {
                loops1.add(a);
                edges.add(new Dfg.Pair(a, a));
            }
            lines.add("L1 " + a + " count " + count + " measure " + fraction(measure) + " " +
                      (accepted ? "ACCEPT" : "REJECT"));
        }
        for (int i = 0; i < activities.size(); i++)
            for (int j = i + 1; j < activities.size(); j++) {
                String a = activities.get(i), b = activities.get(j);
                long count = Dfg.count(triangles, a, b) + Dfg.count(triangles, b, a);
                if (loops1.contains(a) || loops1.contains(b) || count == 0)
                    continue;
                Report.Fraction measure = HeuristicMiner.loop(count);
                boolean accepted =
                    count >= minimum && measure.compareTo(threshold("loop2_threshold")) >= 0;
                if (accepted)
                    loops2.add(new Dfg.Pair(a, b));
                lines.add("L2 " + a + " " + b + " count " + count + " measure " +
                          fraction(measure) + " " + (accepted ? "ACCEPT" : "REJECT"));
            }
        Map<Dfg.Pair, Report.Fraction> measures = new HashMap<>();
        Map<String, Report.Fraction> bestOut = new HashMap<>(), bestIn = new HashMap<>();
        for (Dfg.Pair pair : counts.keySet())
            if (!pair.first().equals(pair.second())) {
                Report.Fraction measure =
                    HeuristicMiner.dependency(counts, pair.first(), pair.second());
                measures.put(pair, measure);
                if (!bestOut.containsKey(pair.first()) ||
                    measure.compareTo(bestOut.get(pair.first())) > 0)
                    bestOut.put(pair.first(), measure);
                if (!bestIn.containsKey(pair.second()) ||
                    measure.compareTo(bestIn.get(pair.second())) > 0)
                    bestIn.put(pair.second(), measure);
            }
        List<Dfg.Pair> pairs = new ArrayList<>(measures.keySet());
        pairs.sort(Dfg::compare);
        for (Dfg.Pair pair : pairs) {
            String a = pair.first(), b = pair.second();
            Report.Fraction measure = measures.get(pair);
            Dfg.Pair canonical = a.compareTo(b) < 0 ? pair : new Dfg.Pair(b, a);
            String verdict;
            if (loops2.contains(canonical))
                verdict = "LOOP2";
            else if (counts.get(pair) < minimum)
                verdict = "REJECT_COUNT";
            else if (measure.compareTo(threshold("dependency_threshold")) < 0)
                verdict = "REJECT_MEASURE";
            else if (bestOut.get(a).subtract(measure).compareTo(threshold("relative_to_best")) >
                         0 &&
                     bestIn.get(b).subtract(measure).compareTo(threshold("relative_to_best")) > 0)
                verdict = "REJECT_BEST";
            else
                verdict = "ACCEPT";
            if (verdict.equals("LOOP2") || verdict.equals("ACCEPT"))
                edges.add(pair);
            lines.add("DEP " + a + " " + b + " count " + counts.get(pair) + " reverse " +
                      Dfg.count(counts, b, a) + " measure " + fraction(measure) + " " + verdict);
        }
        Map<String, List<String>> inputs = new HashMap<>(), outputs = new HashMap<>();
        for (String a : activities) {
            List<String> ins = new ArrayList<>(), outs = new ArrayList<>();
            for (String b : activities) {
                if (edges.contains(new Dfg.Pair(b, a)))
                    ins.add(b);
                if (edges.contains(new Dfg.Pair(a, b)))
                    outs.add(b);
            }
            inputs.put(a, ins);
            outputs.put(a, outs);
            lines.add("NODE " + a + " in " + names(ins) + " out " + names(outs));
        }
        for (String a : activities)
            for (int side = 0; side < 2; side++) {
                List<String> neighbors =
                    new ArrayList<>(side == 0 ? outputs.get(a) : inputs.get(a));
                neighbors.remove(a);
                for (int i = 0; i < neighbors.size(); i++)
                    for (int j = i + 1; j < neighbors.size(); j++) {
                        String b = neighbors.get(i), c = neighbors.get(j);
                        Report.Fraction measure = side == 0 ? HeuristicMiner.split(counts, a, b, c)
                                                            : HeuristicMiner.join(counts, a, b, c);
                        lines.add(
                            (side == 0 ? "SPLIT" : "JOIN") + " " + a + " " + b + " " + c +
                            " measure " + fraction(measure) + " " +
                            (measure.compareTo(threshold("and_threshold")) >= 0 ? "AND" : "XOR"));
                    }
            }
        lines.add("GRAPH activities " + activities.size() + " edges " + edges.size() + " loops1 " +
                  loops1.size() + " loops2 " + loops2.size());
        return lines;
    }
    static Reach explore(Conformance.Net net) {
        Reach result = new Reach();
        List<int[]> markings = new ArrayList<>();
        List<List<Integer>> reverse = new ArrayList<>();
        List<Edge> edges = new ArrayList<>();
        Map<String, Integer> indices = new HashMap<>();
        int[] first = net.initialMarking();
        markings.add(first);
        reverse.add(new ArrayList<>());
        indices.put(Arrays.toString(first), 0);
        boolean[] enabledEver = new boolean[net.transitions.size()];
        for (int index = 0; index < markings.size(); index++) {
            int[] marking = markings.get(index);
            boolean enabled = false;
            for (int t = 0; t < net.transitions.size(); t++)
                if (Conformance.enabled(net, marking, t)) {
                    enabled = true;
                    enabledEver[t] = true;
                    int[] after = Conformance.fire(net, marking, t);
                    boolean safe = true;
                    for (int count : after)
                        if (count > 1)
                            safe = false;
                    if (!safe) {
                        result.unsafe++;
                        continue;
                    }
                    String key = Arrays.toString(after);
                    Integer destination = indices.get(key);
                    if (destination == null) {
                        destination = markings.size();
                        indices.put(key, destination);
                        markings.add(after);
                        reverse.add(new ArrayList<>());
                    }
                    edges.add(new Edge(index, t, destination));
                    reverse.get(destination).add(index);
                }
            if (!enabled && !Arrays.equals(marking, net.finalMarking()))
                result.deadlocks++;
        }
        Integer terminal = indices.get(Arrays.toString(net.finalMarking()));
        result.terminal = terminal != null;
        boolean[] reachable = new boolean[markings.size()];
        ArrayDeque<Integer> queue = new ArrayDeque<>();
        if (terminal != null) {
            reachable[terminal] = true;
            queue.add(terminal);
        }
        while (!queue.isEmpty()) {
            int at = queue.removeFirst();
            for (int before : reverse.get(at))
                if (!reachable[before]) {
                    reachable[before] = true;
                    queue.add(before);
                }
        }
        for (boolean value : reachable)
            if (!value)
                result.stuck++;
        for (int t = 0; t < enabledEver.length; t++)
            if (!enabledEver[t])
                result.dead.add(net.transitions.get(t));
        for (Edge edge : edges)
            for (int t = 0; t < net.transitions.size(); t++)
                if (Conformance.enabled(net, markings.get(edge.to()), t))
                    result.follows.put(new Dfg.Pair(net.transitions.get(edge.transition()),
                                                    net.transitions.get(t)),
                                       1L);
        result.markings = markings.size();
        result.edges = edges.size();
        result.sound = result.unsafe == 0 && result.stuck == 0 && result.dead.isEmpty();
        return result;
    }
    static String reachLine(String name, Reach r) {
        return "REACHABILITY " + name + " markings " + r.markings + " edges " + r.edges +
            " unsafe " + r.unsafe + " deadlocks " + r.deadlocks + " stuck " + r.stuck + " final " +
            yes(r.terminal) + " dead " + names(r.dead) + " sound " + yes(r.sound);
    }
    static List<String> footprintLines(String name, Conformance.Net net, Reach reach) {
        TreeSet<String> union = new TreeSet<>(activities);
        union.addAll(net.transitions);
        List<String> names = new ArrayList<>(union), differences = new ArrayList<>();
        int differing = 0;
        for (String a : names)
            for (String b : names) {
                String observed = Dfg.basic(counts, a, b), model = Dfg.basic(reach.follows, a, b);
                if (!observed.equals(model)) {
                    differing++;
                    if (name.equals("reference") && a.compareTo(b) <= 0)
                        differences.add("DIFF " + a + " " + b + " log " + observed + " model " +
                                        model);
                }
            }
        int cells = names.size() * names.size();
        List<String> lines = new ArrayList<>();
        lines.add("FOOTPRINT " + name + " activities " + names.size() + " cells " + cells +
                  " differing " + differing + " fitness " + fraction(cells - differing, cells));
        lines.addAll(differences);
        return lines;
    }
    static Map<List<String>, Prefix> prefixes() {
        Map<List<String>, Prefix> result = new HashMap<>();
        for (Eventlog.Case c : cases)
            for (int length = 0; length <= c.trace.size(); length++) {
                List<String> key = List.copyOf(c.trace.subList(0, length));
                Prefix prefix = result.computeIfAbsent(key, k -> new Prefix());
                prefix.weight++;
                if (length < c.trace.size())
                    prefix.followers.add(c.trace.get(length));
            }
        return result;
    }
    static List<String> precision(String name, Conformance.Net net,
                                  Map<List<String>, Prefix> prefixes) {
        long fitting = 0, allowed = 0, escaping = 0;
        Map<String, Long> escapeWeights = new HashMap<>();
        List<List<String>> order = new ArrayList<>(prefixes.keySet());
        order.sort(Main::compareTrace);
        Map<List<String>, int[]> states = new HashMap<>();
        for (List<String> prefix : order) {
            int[] marking = net.initialMarking();
            if (!prefix.isEmpty()) {
                marking = states.get(prefix.subList(0, prefix.size() - 1));
                Integer t = net.transitionIndex.get(prefix.getLast());
                if (marking != null && t != null && Conformance.enabled(net, marking, t))
                    marking = Conformance.fire(net, marking, t);
                else
                    marking = null;
            }
            states.put(prefix, marking);
            if (marking == null)
                continue;
            fitting++;
            Prefix value = prefixes.get(prefix);
            for (int t = 0; t < net.transitions.size(); t++)
                if (Conformance.enabled(net, marking, t)) {
                    allowed += value.weight;
                    String transition = net.transitions.get(t);
                    if (!value.followers.contains(transition)) {
                        escaping += value.weight;
                        add(escapeWeights, transition, value.weight);
                    }
                }
        }
        List<String> lines = new ArrayList<>();
        lines.add("PRECISION " + name + " prefixes " + fitting + " allowed " + allowed +
                  " escaping " + escaping + " precision " +
                  fraction(allowed == 0 ? 1 : allowed - escaping, allowed == 0 ? 1 : allowed));
        for (String transition : nameOrder(escapeWeights))
            lines.add("ESCAPE " + name + " " + transition + " weight " +
                      escapeWeights.get(transition));
        return lines;
    }
    static Conformance.Totals replayCase(Conformance.Net net, Eventlog.Case c) {
        Conformance.Totals r = new Conformance.Totals(net.places.size(), net.transitions.size());
        List<ArrayDeque<Integer>> tokens = new ArrayList<>();
        for (String place : net.places)
            tokens.add(new ArrayDeque<>());
        tokens.get(net.initial).add(c.events.getFirst().time());
        r.produced = 1;
        for (Eventlog.Event event : c.events) {
            Integer transition = net.transitionIndex.get(event.activity());
            if (transition == null) {
                r.skipped++;
                continue;
            }
            for (int place : net.inputs.get(transition)) {
                r.consumed++;
                if (!tokens.get(place).isEmpty()) {
                    int produced = tokens.get(place).removeFirst(), wait = event.time() - produced;
                    r.waitingCount[place]++;
                    r.waitingSum[place] += wait;
                    r.waitingMax[place] = Math.max(r.waitingMax[place], wait);
                    r.routes[place][transition]++;
                } else {
                    r.missing++;
                    r.placeMissing[place]++;
                }
            }
            for (int place : net.outputs.get(transition)) {
                tokens.get(place).add(event.time());
                r.produced++;
            }
        }
        r.consumed++;
        if (!tokens.get(net.finish).isEmpty())
            tokens.get(net.finish).removeFirst();
        else {
            r.missing++;
            r.placeMissing[net.finish]++;
        }
        for (int place = 0; place < net.places.size(); place++) {
            long remaining = tokens.get(place).size();
            r.placeRemaining[place] = remaining;
            r.remaining += remaining;
            r.deviating[place] = r.placeMissing[place] > 0 || remaining > 0 ? 1 : 0;
        }
        return r;
    }
    static List<String> replayLines(String name, Conformance.Net net) {
        Conformance.Totals total =
            new Conformance.Totals(net.places.size(), net.transitions.size());
        int fitting = 0;
        for (Eventlog.Case c : cases) {
            Conformance.Totals r = replayCase(net, c);
            if (name.equals("reference"))
                referenceReplays.put(c.id, r);
            if (r.missing == 0 && r.remaining == 0)
                fitting++;
            total.missing += r.missing;
            total.remaining += r.remaining;
            total.consumed += r.consumed;
            total.produced += r.produced;
            total.skipped += r.skipped;
            for (int place = 0; place < net.places.size(); place++) {
                total.placeMissing[place] += r.placeMissing[place];
                total.placeRemaining[place] += r.placeRemaining[place];
                total.deviating[place] += r.deviating[place];
                total.waitingCount[place] += r.waitingCount[place];
                total.waitingSum[place] += r.waitingSum[place];
                total.waitingMax[place] = Math.max(total.waitingMax[place], r.waitingMax[place]);
                for (int t = 0; t < net.transitions.size(); t++)
                    total.routes[place][t] += r.routes[place][t];
            }
        }
        List<String> lines = new ArrayList<>();
        lines.add("REPLAY " + name + " cases " + cases.size() + " fitting " + fitting +
                  " skipped " + total.skipped + " missing " + total.missing + " remaining " +
                  total.remaining + " consumed " + total.consumed + " produced " + total.produced +
                  " fitness " + fraction(total.fitness()));
        for (int p = 0; p < net.places.size(); p++)
            lines.add(
                "PLACE " + name + " " + net.places.get(p) + " missing " + total.placeMissing[p] +
                " remaining " + total.placeRemaining[p] + " deviating " + total.deviating[p] +
                " tokens " + total.waitingCount[p] + " mean " +
                (total.waitingCount[p] == 0
                     ? "-"
                     : fraction(total.waitingSum[p], total.waitingCount[p])) +
                " max " + (total.waitingCount[p] == 0 ? "-" : Long.toString(total.waitingMax[p])));
        for (int p = 0; p < net.places.size(); p++) {
            List<String> routes = new ArrayList<>();
            for (int t = 0; t < net.transitions.size(); t++)
                if (net.inputs.get(t).contains(p))
                    routes.add(net.transitions.get(t) + "=" + total.routes[p][t]);
            if (routes.size() >= 2)
                lines.add("ROUTE " + name + " " + net.places.get(p) + " " +
                          String.join(",", routes));
        }
        return lines;
    }
    static List<String> conformance() {
        List<String> lines = new ArrayList<>();
        lines.add("MODEL places " + reference.places.size() + " transitions " +
                  reference.transitions.size() + " arcs " + reference.arcs());
        List<Reach> reaches = new ArrayList<>();
        for (int i = 0; i < 3; i++) {
            Reach r = explore(nets.get(i));
            reaches.add(r);
            lines.add(reachLine(NET_NAMES[i], r));
        }
        for (int i = 0; i < 3; i++)
            lines.addAll(footprintLines(NET_NAMES[i], nets.get(i), reaches.get(i)));
        Map<List<String>, Prefix> prefixes = prefixes();
        for (int i = 0; i < 3; i++)
            lines.addAll(precision(NET_NAMES[i], nets.get(i), prefixes));
        for (int i = 0; i < 3; i++)
            lines.addAll(replayLines(NET_NAMES[i], nets.get(i)));
        return lines;
    }
    static List<String> csv() {
        List<String> lines = new ArrayList<>();
        lines.add("case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness");
        for (Eventlog.Case c : cases) {
            Conformance.Totals r = referenceReplays.get(c.id);
            lines.add(c.id + "," + variantIds.get(c.id) + "," + c.events.size() + "," + r.skipped +
                      "," + r.missing + "," + r.remaining + "," + r.consumed + "," + r.produced +
                      "," + fraction(r.fitness()));
        }
        return lines;
    }
    static List<String> resourceLines() {
        Map<String, Long> eventCount = new HashMap<>(), caseCount = new HashMap<>();
        Map<Dfg.Pair, Long> work = new HashMap<>(), handovers = new HashMap<>(),
                            handoverCases = new HashMap<>(), subcontracts = new HashMap<>(),
                            together = new HashMap<>();
        for (Eventlog.Case c : cases) {
            TreeSet<String> present = new TreeSet<>();
            Set<Dfg.Pair> pairs = new HashSet<>();
            for (int i = 0; i < c.events.size(); i++) {
                Eventlog.Event e = c.events.get(i);
                present.add(e.resource());
                add(eventCount, e.resource(), 1);
                add(work, new Dfg.Pair(e.resource(), e.activity()), 1);
                if (i > 0) {
                    Dfg.Pair pair = new Dfg.Pair(c.events.get(i - 1).resource(), e.resource());
                    add(handovers, pair, 1);
                    pairs.add(pair);
                }
                if (i > 1) {
                    String a = c.events.get(i - 2).resource(), b = c.events.get(i - 1).resource();
                    if (a.equals(e.resource()) && !a.equals(b))
                        add(subcontracts, new Dfg.Pair(a, b), 1);
                }
            }
            for (String worker : present)
                add(caseCount, worker, 1);
            for (Dfg.Pair pair : pairs)
                add(handoverCases, pair, 1);
            List<String> workers = new ArrayList<>(present);
            for (int i = 0; i < workers.size(); i++)
                for (int j = i + 1; j < workers.size(); j++)
                    add(together, new Dfg.Pair(workers.get(i), workers.get(j)), 1);
        }
        List<String> lines = new ArrayList<>();
        for (int i = 0; i < resources.size(); i++) {
            String resource = resources.get(i);
            List<String> tasks = new ArrayList<>();
            for (String activity : activities) {
                long count = Dfg.count(work, resource, activity);
                if (count > 0)
                    tasks.add(activity + "=" + count);
            }
            lines.add("RESOURCE " + (i + 1) + " " + resource + " events " +
                      get(eventCount, resource) + " cases " + get(caseCount, resource) + " work " +
                      String.join(",", tasks));
        }
        for (Dfg.Pair pair : pairOrder(handovers, true))
            if (!pair.first().equals(pair.second()))
                lines.add("HANDOVER " + pair.first() + " " + pair.second() + " count " +
                          handovers.get(pair) + " cases " + get(handoverCases, pair));
        List<List<String>> rows = new ArrayList<>();
        for (String a : resources) {
            List<String> row = new ArrayList<>();
            for (String b : resources)
                row.add(Long.toString(Dfg.count(handovers, a, b)));
            rows.add(row);
        }
        lines.addAll(Dfg.table(rows, 5));
        for (Dfg.Pair pair : pairOrder(subcontracts, true))
            lines.add("SUBCONTRACT " + pair.first() + " " + pair.second() + " count " +
                      subcontracts.get(pair));
        for (Dfg.Pair pair : pairOrder(together, true))
            lines.add("TOGETHER " + pair.first() + " " + pair.second() + " cases " +
                      together.get(pair));
        long total = 0, own = 0;
        for (var entry : handovers.entrySet()) {
            total += entry.getValue();
            if (entry.getKey().first().equals(entry.getKey().second()))
                own += entry.getValue();
        }
        lines.add("TOTAL handovers " + total + " self " + own + " other " + (total - own));
        return lines;
    }
    public static void main(String[] args) throws Exception {
        input = Eventlog.read();
        reference = Conformance.read();
        prepare();
        List<String> workflow = workflows(), checks = conformance();
        Report.write("log_summary.txt", logSummary());
        Report.write("variants.txt", variantLines());
        Report.write("dfg.txt", dfgLines());
        Report.write("alpha_net.txt", workflow);
        Report.write("heuristic_net.txt", heuristic());
        Report.write("conformance.csv", csv());
        Report.write("conformance.txt", checks);
        Report.write("resources.txt", resourceLines());
    }
}
