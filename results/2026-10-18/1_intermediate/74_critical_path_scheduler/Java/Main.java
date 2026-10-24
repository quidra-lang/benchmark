import java.io.*;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super("error: " + message);
        }
    }

    static void fail(String message) {
        throw new Problem(message);
    }

    static String signed(int value) {
        return value >= 0 ? "+" + value : Integer.toString(value);
    }

    static String decimal(long numerator, long denominator) {
        long hundredths = numerator * 100 / denominator;
        return hundredths / 100 + "." + String.format(Locale.ROOT, "%02d", hundredths % 100);
    }

    static String names(Collection<String> names) {
        return names.isEmpty() ? "none" : String.join(" ", names);
    }

    static class Task {
        String name, resource;
        int base, units, notBefore, crashed;
        Integer crashLimit, crashCost;
        int[] estimate;
        Task(String name, int duration, String resource, int units) {
            this.name = name;
            this.base = duration;
            this.resource = resource;
            this.units = units;
        }
        int duration() {
            return base - crashed;
        }
    }

    record Dependency(String a, String b, String kind, int lag) { }

    static class Timing {
        int duration, es, ef, ls, lf, tf, free;
    }

    static class Schedule {
        TreeMap<String, Timing> times = new TreeMap<>();
        int total;
        List<String> critical() {
            return times.entrySet().stream().filter(e -> e.getValue().tf == 0).map(Map.Entry::getKey).toList();
        }
    }

    record Baseline(int total, Map<String, int[]> times) { }

    TreeMap<String, Task> tasks = new TreeMap<>();
    List<Dependency> dependencies = new ArrayList<>();
    TreeMap<String, Integer> capacities = new TreeMap<>();
    TreeSet<LocalDate> holidays = new TreeSet<>();
    LocalDate start, deadline;
    Baseline baseline;

    Task task(String name) {
        Task t = tasks.get(name);
        if (t == null) fail("unknown task " + name);
        return t;
    }

    List<Dependency> incoming(String name) {
        return dependencies.stream().filter(d -> d.b.equals(name)).sorted(Comparator.comparing(Dependency::a)).toList();
    }

    List<Dependency> outgoing(String name) {
        return dependencies.stream().filter(d -> d.a.equals(name)).sorted(Comparator.comparing(Dependency::b)).toList();
    }

    List<String> topological() {
        List<String> result = new ArrayList<>();
        Set<String> remaining = new TreeSet<>(tasks.keySet());
        while (true) {
            String next = null;
            for (String name : remaining) if (incoming(name).stream().noneMatch(d -> remaining.contains(d.a))) {
                next = name;
                break;
            }
            if (next == null) break;
            result.add(next);
            remaining.remove(next);
        }
        return result;
    }

    String cycle() {
        TreeSet<String> remaining = new TreeSet<>(tasks.keySet());
        remaining.removeAll(topological());
        if (remaining.isEmpty()) return null;
        List<String> chain = new ArrayList<>();
        String current = remaining.first();
        while (!chain.contains(current)) {
            chain.add(current);
            current = incoming(current).stream().filter(d -> remaining.contains(d.a)).findFirst().orElseThrow().a;
        }
        int begin = chain.indexOf(current);
        List<String> cycle = new ArrayList<>(List.of(current));
        for (int i = chain.size() - 1; i > begin; i--) cycle.add(chain.get(i));
        int minimum = cycle.indexOf(Collections.min(cycle));
        Collections.rotate(cycle, -minimum);
        cycle.add(cycle.getFirst());
        return String.join(" -> ", cycle);
    }

    Schedule schedule(String changed, int duration) {
        Schedule s = new Schedule();
        List<String> order = topological();
        for (String name : order) {
            Task t = tasks.get(name);
            Timing x = new Timing();
            x.duration = name.equals(changed) ? duration : t.duration();
            x.es = t.notBefore;
            for (Dependency d : incoming(name)) {
                Timing a = s.times.get(d.a);
                int bound = switch (d.kind) {
                    case "FS" -> a.ef + d.lag;
                    case "SS" -> a.es + d.lag;
                    default -> a.ef + d.lag - x.duration;
                };
                x.es = Math.max(x.es, bound);
            }
            x.ef = x.es + x.duration;
            s.total = Math.max(s.total, x.ef);
            s.times.put(name, x);
        }
        for (int i = order.size() - 1; i >= 0; i--) {
            String name = order.get(i);
            Timing x = s.times.get(name);
            x.lf = s.total;
            for (Dependency d : outgoing(name)) {
                Timing b = s.times.get(d.b);
                int bound = switch (d.kind) {
                    case "FS" -> b.ls - d.lag;
                    case "SS" -> b.ls - d.lag + x.duration;
                    default -> b.lf - d.lag;
                };
                x.lf = Math.min(x.lf, bound);
            }
            x.ls = x.lf - x.duration;
            x.tf = x.ls - x.es;
            x.free = s.total - x.ef;
            for (Dependency d : outgoing(name)) x.free = Math.min(x.free, margin(s, d));
        }
        return s;
    }

    int margin(Schedule s, Dependency d) {
        Timing a = s.times.get(d.a), b = s.times.get(d.b);
        return (d.kind.equals("FF") ? b.ef : b.es) - (d.kind.equals("SS") ? a.es : a.ef) - d.lag;
    }

    List<List<String>> criticalPaths(Schedule s) {
        List<List<String>> paths = new ArrayList<>();
        Map<String, List<String>> successors = new TreeMap<>();
        Set<String> hasPredecessor = new HashSet<>();
        for (String name : s.critical()) successors.put(name, new ArrayList<>());
        for (Dependency d : dependencies) if (successors.containsKey(d.a) && successors.containsKey(d.b) && margin(s, d) == 0) {
            successors.get(d.a).add(d.b);
            hasPredecessor.add(d.b);
        }
        for (List<String> list : successors.values()) Collections.sort(list);
        class Walk {
            void visit(String name, List<String> path) {
                path.add(name);
                if (successors.get(name).isEmpty()) paths.add(new ArrayList<>(path));
                else for (String next : successors.get(name)) visit(next, path);
                path.removeLast();
            }
        }
        Walk walk = new Walk();
        for (String name : successors.keySet()) if (!hasPredecessor.contains(name)) walk.visit(name, new ArrayList<>());
        return paths;
    }

    LocalDate parseDate(String text) {
        try {
            return LocalDate.of(Integer.parseInt(text.substring(0, 4)), Integer.parseInt(text.substring(5, 7)), Integer.parseInt(text.substring(8, 10)));
        } catch (DateTimeException e) {
            fail("invalid date " + text);
            return null;
        }
    }

    static String date(LocalDate d) {
        return d.format(DateTimeFormatter.ofPattern("uuuu-MM-dd EEE", Locale.ENGLISH));
    }

    static boolean weekday(LocalDate d) {
        return d.getDayOfWeek().getValue() <= 5;
    }

    boolean working(LocalDate d) {
        return weekday(d) && !holidays.contains(d);
    }

    List<LocalDate> calendar(int total) {
        List<LocalDate> days = new ArrayList<>();
        for (LocalDate d = start; days.size() < total; d = d.plusDays(1)) if (working(d)) days.add(d);
        return days;
    }

    int workingBetween(LocalDate a, LocalDate b) {
        int count = 0;
        for (LocalDate d = a.plusDays(1); !d.isAfter(b); d = d.plusDays(1)) if (working(d)) count++;
        return count;
    }

    TreeMap<String, int[]> usage(Schedule s) {
        TreeMap<String, int[]> result = new TreeMap<>();
        for (Task t : tasks.values()) {
            int[] load = result.computeIfAbsent(t.resource, r -> new int[s.total]);
            Timing x = s.times.get(t.name);
            for (int k = x.es; k < x.ef; k++) load[k] += t.units;
        }
        return result;
    }

    List<String> command(String line) {
        String[] w = line.split(" ");
        String c = w[0];
        List<String> out = new ArrayList<>();
        Set<String> analyses = Set.of("CPM", "CRITICAL", "SLACK", "DRAG", "STATS", "CALENDAR", "GANTT", "LEVEL", "LOAD", "PERTSUM", "CRASH", "WHATIF", "BASELINE", "VARIANCE");
        if (analyses.contains(c)) {
            if (tasks.isEmpty()) fail("no tasks");
            String cycle = cycle();
            if (cycle != null) fail("cycle " + cycle);
        }
        switch (c) {
            case "TASK" -> {
                if (tasks.containsKey(w[1])) fail("task " + w[1] + " already exists");
                tasks.put(w[1], new Task(w[1], Integer.parseInt(w[2]), w[3], Integer.parseInt(w[4])));
                out.add("task " + w[1] + " added");
            }
            case "DEP", "UNDEP" -> {
                task(w[1]);
                task(w[2]);
                Dependency old = dependencies.stream().filter(d -> d.a.equals(w[1]) && d.b.equals(w[2])).findFirst().orElse(null);
                if (c.equals("DEP")) {
                    if (w[1].equals(w[2])) fail("self dependency " + w[1]);
                    if (old != null) fail("dependency " + w[1] + " -> " + w[2] + " already exists");
                    int lag = Integer.parseInt(w[4]);
                    dependencies.add(new Dependency(w[1], w[2], w[3], lag));
                    out.add("dependency " + w[1] + " -> " + w[2] + " " + w[3] + signed(lag) + " added");
                } else {
                    if (old == null) fail("no dependency " + w[1] + " -> " + w[2]);
                    dependencies.remove(old);
                    out.add("dependency " + w[1] + " -> " + w[2] + " removed");
                }
            }
            case "REMOVE" -> {
                task(w[1]);
                int before = dependencies.size();
                dependencies.removeIf(d -> d.a.equals(w[1]) || d.b.equals(w[1]));
                tasks.remove(w[1]);
                out.add("task " + w[1] + " removed with " + (before - dependencies.size()) + " dependencies");
            }
            case "NOTBEFORE", "CRASHCOST", "UNCRASH", "PERT" -> {
                Task t = task(w[1]);
                if (c.equals("NOTBEFORE")) {
                    t.notBefore = Integer.parseInt(w[2]);
                    out.add("notbefore " + t.name + " " + t.notBefore);
                } else if (c.equals("CRASHCOST")) {
                    int limit = Integer.parseInt(w[2]);
                    if (limit >= t.base) fail("crash limit too large for " + t.name);
                    if (limit < t.crashed) fail("crash limit below used days for " + t.name);
                    t.crashLimit = limit;
                    t.crashCost = Integer.parseInt(w[3]);
                    out.add("crash " + t.name + " max " + limit + " cost " + t.crashCost);
                } else if (c.equals("UNCRASH")) {
                    out.add("uncrash " + t.name + " restored " + t.crashed + " days");
                    t.crashed = 0;
                } else {
                    int o = Integer.parseInt(w[2]), m = Integer.parseInt(w[3]), p = Integer.parseInt(w[4]);
                    if (o > m || m > p) fail("invalid estimate");
                    t.estimate = new int[]{o, m, p};
                    out.add("pert " + t.name + " expected " + decimal(o + 4L * m + p, 6) + " variance " + decimal((long)(p - o) * (p - o), 36));
                }
            }
            case "CAPACITY" -> {
                capacities.put(w[1], Integer.parseInt(w[2]));
                out.add("capacity " + w[1] + " " + w[2]);
            }
            case "START", "HOLIDAY", "DEADLINE" -> {
                LocalDate d = parseDate(w[1]);
                if (c.equals("HOLIDAY") && holidays.contains(d)) fail("duplicate holiday " + w[1]);
                if (c.equals("START")) start = d;
                else if (c.equals("DEADLINE")) deadline = d;
                else holidays.add(d);
                out.add(c.toLowerCase(Locale.ROOT) + " " + date(d));
            }
            case "LIST" -> {
                out.add("tasks " + tasks.size() + ", dependencies " + dependencies.size() + ", holidays " + holidays.size());
                for (Task t : tasks.values()) out.add(t.name + " duration " + t.duration() + " resource " + t.resource + " units " + t.units + " preds " + names(incoming(t.name).stream().map(Dependency::a).toList()));
            }
            case "SHOW" -> {
                Task t = task(w[1]);
                out.add("task " + t.name + " duration " + t.duration() + " resource " + t.resource + " units " + t.units + (t.notBefore == 0 ? "" : " notbefore " + t.notBefore));
                for (boolean predecessors : new boolean[]{true, false}) {
                    List<String> parts = new ArrayList<>();
                    for (Dependency d : predecessors ? incoming(t.name) : outgoing(t.name)) parts.add((predecessors ? d.a : d.b) + " " + d.kind + signed(d.lag));
                    out.add((predecessors ? "preds: " : "succs: ") + (parts.isEmpty() ? "none" : String.join(", ", parts)));
                }
                out.add(t.crashLimit == null ? "crash: none" : "crash: max " + t.crashLimit + " used " + t.crashed + " cost " + t.crashCost);
                out.add(t.estimate == null ? "pert: none" : "pert: " + t.estimate[0] + " " + t.estimate[1] + " " + t.estimate[2]);
                if (cycle() != null) out.add("schedule: unavailable");
                else {
                    Timing x = schedule(null, 0).times.get(t.name);
                    out.add("schedule: ES " + x.es + " EF " + x.ef + " LS " + x.ls + " LF " + x.lf + " TF " + x.tf + " FF " + x.free + (x.tf == 0 ? " critical" : ""));
                }
            }
            case "IMPACT" -> {
                task(w[1]);
                Set<String> seen = new TreeSet<>();
                ArrayDeque<String> queue = new ArrayDeque<>(List.of(w[1]));
                seen.add(w[1]);
                while (!queue.isEmpty()) for (Dependency d : outgoing(queue.remove())) if (seen.add(d.b)) queue.add(d.b);
                seen.remove(w[1]);
                out.add("impact " + w[1] + ": " + names(seen));
            }
            default -> {
                if (c.equals("CALENDAR") && start == null) fail("no start date");
                if (c.equals("WHATIF")) task(w[1]);
                if (c.equals("VARIANCE") && baseline == null) fail("no baseline");
                if (c.equals("LOAD") && tasks.values().stream().noneMatch(t -> t.resource.equals(w[1]))) fail("unknown resource " + w[1]);
                if (c.equals("LEVEL")) for (Task t : tasks.values()) {
                    int cap = capacities.getOrDefault(t.resource, Integer.parseInt(w[1]));
                    if (t.units > cap) fail("capacity " + cap + " too small for " + t.name);
                }
                Schedule s = schedule(null, 0);
                switch (c) {
                    case "CPM" -> {
                        int width = Math.max(4, tasks.lastKey().length());
                        for (String name : tasks.keySet()) width = Math.max(width, name.length());
                        out.add(String.format(Locale.ROOT, "%-" + width + "s%5s%5s%5s%5s%5s%5s%5s", "TASK", "DUR", "ES", "EF", "LS", "LF", "TF", "FF"));
                        for (var e : s.times.entrySet()) {
                            Timing x = e.getValue();
                            out.add(String.format(Locale.ROOT, "%-" + width + "s%5d%5d%5d%5d%5d%5d%5d", e.getKey(), x.duration, x.es, x.ef, x.ls, x.lf, x.tf, x.free) + (x.tf == 0 ? " *" : ""));
                        }
                        out.add("project duration " + s.total);
                    }
                    case "CRITICAL", "PERTSUM" -> {
                        List<List<String>> paths = criticalPaths(s);
                        if (c.equals("CRITICAL")) out.add("critical paths: " + paths.size());
                        for (List<String> path : paths) {
                            String text = String.join(" -> ", path);
                            if (c.equals("PERTSUM")) {
                                long expected = 0, variance = 0;
                                for (String name : path) {
                                    Task t = tasks.get(name);
                                    int d = t.duration();
                                    int[] p = t.estimate == null ? new int[]{d, d, d} : t.estimate;
                                    expected += p[0] + 4L * p[1] + p[2];
                                    variance += (long)(p[2] - p[0]) * (p[2] - p[0]);
                                }
                                text += ": expected " + decimal(expected, 6) + " variance " + decimal(variance, 36);
                            }
                            out.add(text);
                        }
                    }
                    case "SLACK" -> {
                        TreeMap<Integer, List<String>> groups = new TreeMap<>();
                        for (var e : s.times.entrySet()) groups.computeIfAbsent(e.getValue().tf, k -> new ArrayList<>()).add(e.getKey());
                        for (var e : groups.entrySet()) out.add("float " + e.getKey() + ": " + names(e.getValue()));
                    }
                    case "DRAG" -> {
                        for (String name : s.critical()) out.add(name + " drag " + (s.total - schedule(name, 0).total));
                    }
                    case "STATS" -> {
                        int critical = s.critical().size(), totalFloat = s.times.values().stream().mapToInt(x -> x.tf).sum();
                        out.add("tasks " + tasks.size() + ", critical " + critical + ", dependencies " + dependencies.size() + " (FS " + dependencies.stream().filter(d -> d.kind.equals("FS")).count() + ", SS " + dependencies.stream().filter(d -> d.kind.equals("SS")).count() + ", FF " + dependencies.stream().filter(d -> d.kind.equals("FF")).count() + ")");
                        TreeMap<String, Integer> work = new TreeMap<>();
                        for (Task t : tasks.values()) work.merge(t.resource, t.duration() * t.units, Integer::sum);
                        out.add("work " + String.join(", ", work.entrySet().stream().map(e -> e.getKey() + " " + e.getValue()).toList()));
                        out.add("float total " + totalFloat + ", average " + decimal(totalFloat, tasks.size()));
                        out.add("duration " + s.total + ", critical share " + decimal(100L * critical, tasks.size()) + "%");
                    }
                    case "CALENDAR" -> {
                        List<LocalDate> days = calendar(s.total);
                        for (String name : startOrder(s)) {
                            Timing x = s.times.get(name);
                            out.add(name + " " + date(days.get(x.es)) + " - " + date(days.get(x.ef - 1)));
                        }
                        LocalDate first = days.getFirst(), last = days.getLast();
                        out.add("project " + date(first) + " - " + date(last) + ", " + s.total + " working days, " + (last.toEpochDay() - first.toEpochDay() + 1) + " calendar days");
                        if (deadline != null) out.add("deadline " + date(deadline) + (!last.isAfter(deadline) ? " met, " + workingBetween(last, deadline) + " working days to spare" : " missed by " + workingBetween(deadline, last) + " working days"));
                        List<String> span = holidays.stream().filter(d -> weekday(d) && !d.isBefore(first) && !d.isAfter(last)).map(Main::date).toList();
                        out.add("holidays in span: " + (span.isEmpty() ? "none" : String.join(", ", span)));
                    }
                    case "GANTT" -> {
                        if (s.total > 60) fail("chart too wide (" + s.total + " days)");
                        int width = tasks.keySet().stream().mapToInt(String::length).max().orElseThrow();
                        StringBuilder axis = new StringBuilder(" ".repeat(width) + " |");
                        for (int k = 0; k < s.total; k++) axis.append(k % 10);
                        out.add(axis + "|");
                        for (String name : startOrder(s)) {
                            Timing x = s.times.get(name);
                            StringBuilder bar = new StringBuilder(String.format(Locale.ROOT, "%-" + width + "s |", name));
                            for (int k = 0; k < s.total; k++) bar.append(x.es <= k && k < x.ef ? (x.tf == 0 ? '=' : '-') : x.ef <= k && k < x.lf ? '.' : ' ');
                            out.add(bar + "|");
                        }
                    }
                    case "LEVEL" -> out.addAll(level(s, Integer.parseInt(w[1])));
                    case "LOAD" -> {
                        int[] load = usage(s).get(w[1]);
                        int peak = Arrays.stream(load).max().orElseThrow(), day = 0;
                        while (load[day] != peak) day++;
                        out.add("load " + w[1] + ": " + String.join(" ", Arrays.stream(load).mapToObj(Integer::toString).toList()));
                        out.add("peak " + peak + " on day " + day);
                        if (capacities.containsKey(w[1])) out.add("capacity " + capacities.get(w[1]) + " exceeded on " + Arrays.stream(load).filter(x -> x > capacities.get(w[1])).count() + " days");
                    }
                    case "CRASH" -> {
                        int remaining = Integer.parseInt(w[1]), initial = s.total, steps = 0;
                        String reason;
                        while (true) {
                            Task candidate = null;
                            for (String name : s.critical()) {
                                Task t = tasks.get(name);
                                if (t.crashLimit != null && t.crashed < t.crashLimit && schedule(name, t.duration() - 1).total < s.total && (candidate == null || t.crashCost < candidate.crashCost)) candidate = t;
                            }
                            if (candidate == null) {
                                reason = "no candidate";
                                break;
                            }
                            if (candidate.crashCost > remaining) {
                                reason = "insufficient budget";
                                break;
                            }
                            int before = candidate.duration();
                            candidate.crashed++;
                            remaining -= candidate.crashCost;
                            s = schedule(null, 0);
                            out.add("step " + (++steps) + ": " + candidate.name + " " + before + " -> " + candidate.duration() + ", cost " + candidate.crashCost + ", project " + s.total);
                        }
                        out.add("crash done: " + steps + " days, cost " + (Integer.parseInt(w[1]) - remaining) + ", project " + initial + " -> " + s.total + ", budget left " + remaining + ", " + reason);
                    }
                    case "WHATIF" -> {
                        Schedule after = schedule(w[1], Integer.parseInt(w[2]));
                        out.add("whatif " + w[1] + " " + tasks.get(w[1]).duration() + " -> " + w[2] + ": project " + s.total + " -> " + after.total);
                        for (String name : tasks.keySet()) {
                            Timing a = s.times.get(name), b = after.times.get(name);
                            String text = name + (a.es != b.es ? " ES " + a.es + "->" + b.es : "") + (a.ef != b.ef ? " EF " + a.ef + "->" + b.ef : "") + (a.tf != b.tf ? " TF " + a.tf + "->" + b.tf : "");
                            if (!text.equals(name)) out.add(text);
                        }
                        if (!s.critical().equals(after.critical())) out.add("critical " + names(s.critical()) + " -> " + names(after.critical()));
                    }
                    case "BASELINE" -> {
                        Map<String, int[]> times = new TreeMap<>();
                        for (var e : s.times.entrySet()) times.put(e.getKey(), new int[]{e.getValue().es, e.getValue().ef});
                        baseline = new Baseline(s.total, times);
                        out.add("baseline saved: " + tasks.size() + " tasks, duration " + s.total);
                    }
                    case "VARIANCE" -> {
                        out.add("variance: duration " + baseline.total + " -> " + s.total + " (" + signed(s.total - baseline.total) + ")");
                        TreeSet<String> union = new TreeSet<>(tasks.keySet());
                        union.addAll(baseline.times.keySet());
                        for (String name : union) {
                            if (!tasks.containsKey(name)) out.add(name + " removed");
                            else if (!baseline.times.containsKey(name)) out.add(name + " new");
                            else {
                                Timing x = s.times.get(name);
                                int[] old = baseline.times.get(name);
                                if (x.es != old[0] || x.ef != old[1]) out.add(name + " start " + signed(x.es - old[0]) + " finish " + signed(x.ef - old[1]));
                            }
                        }
                        if (out.size() == 1) out.add("no task changes");
                    }
                    default -> throw new IllegalStateException();
                }
            }
        }
        return out;
    }

    List<String> startOrder(Schedule s) {
        return tasks.keySet().stream().sorted(Comparator.<String>comparingInt(n -> s.times.get(n).es).thenComparing(Comparator.naturalOrder())).toList();
    }

    List<String> level(Schedule s, int limit) {
        Map<String, int[]> decided = new HashMap<>();
        TreeMap<String, Map<Integer, Integer>> loads = new TreeMap<>();
        for (Task t : tasks.values()) loads.computeIfAbsent(t.resource, r -> new HashMap<>());
        List<String> order = new ArrayList<>();
        int total = 0;
        while (decided.size() < tasks.size()) {
            String name = tasks.keySet().stream().filter(n -> !decided.containsKey(n) && incoming(n).stream().allMatch(d -> decided.containsKey(d.a))).min(Comparator.<String>comparingInt(n -> s.times.get(n).ls).thenComparing(Comparator.naturalOrder())).orElseThrow();
            Task t = tasks.get(name);
            int begin = t.notBefore, duration = t.duration(), capacity = capacities.getOrDefault(t.resource, limit);
            for (Dependency d : incoming(name)) {
                int[] a = decided.get(d.a);
                begin = Math.max(begin, (d.kind.equals("SS") ? a[0] : a[1]) + d.lag - (d.kind.equals("FF") ? duration : 0));
            }
            Map<Integer, Integer> load = loads.get(t.resource);
            while (true) {
                boolean fits = true;
                for (int k = begin; k < begin + duration; k++) if (load.getOrDefault(k, 0) + t.units > capacity) {
                    fits = false;
                    break;
                }
                if (fits) break;
                begin++;
            }
            int finish = begin + duration;
            for (int k = begin; k < finish; k++) load.merge(k, t.units, Integer::sum);
            decided.put(name, new int[]{begin, finish});
            order.add(name);
            total = Math.max(total, finish);
        }
        List<String> out = new ArrayList<>(List.of("level capacity " + limit + ": duration " + s.total + " -> " + total));
        for (String name : order) {
            int[] t = decided.get(name);
            out.add(name + " start " + t[0] + " finish " + t[1] + " shift " + (t[0] - s.times.get(name).es));
        }
        TreeMap<String, int[]> original = usage(s);
        for (String resource : loads.keySet()) out.add("resource " + resource + " capacity " + capacities.getOrDefault(resource, limit) + " peak " + Arrays.stream(original.get(resource)).max().orElseThrow() + " -> " + loads.get(resource).values().stream().mapToInt(Integer::intValue).max().orElse(0));
        return out;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main project = new Main();
        int n = Integer.parseInt(reader.readLine());
        for (int i = 0; i < n; i++) {
            try {
                for (String line : project.command(reader.readLine())) System.out.println(line);
            } catch (Problem e) {
                System.out.println(e.getMessage());
            }
        }
    }
}
