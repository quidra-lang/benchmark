import java.io.*;
import java.util.*;
import java.util.stream.Collectors;

public class Main {
    static final String[] KINDS = {"granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"};
    static class Process {
        int id, created;
        int[] max, allocation;
        Process(int id, int[] max, int created) {
            this.id = id; this.max = max.clone(); this.created = created;
            allocation = new int[max.length];
        }
        Process copy() {
            Process p = new Process(id, max, created);
            p.allocation = allocation.clone();
            return p;
        }
        int[] need() { return sub(max, allocation); }
    }
    record Waiting(int id, int[] vector, int since) {}
    record Event(int command, String kind, int id, int[] vector, int waited) {}
    static class State {
        int[] total, available;
        TreeMap<Integer, Process> processes = new TreeMap<>();
        List<Waiting> queue = new ArrayList<>();
        List<Event> history = new ArrayList<>();
        State(int[] total) { this.total = total.clone(); available = total.clone(); }
        State copy() {
            State s = new State(total);
            s.available = available.clone();
            for (Process p : processes.values()) s.processes.put(p.id, p.copy());
            for (Waiting w : queue) s.queue.add(new Waiting(w.id, w.vector.clone(), w.since));
            for (Event e : history) s.history.add(new Event(e.command, e.kind, e.id, e.vector.clone(), e.waited));
            return s;
        }
    }
    record Check(List<Integer> sequence, List<Integer> remaining) {}
    record Decision(String reason, List<Integer> sequence) {}
    static State state = new State(new int[0]);
    static String mode = "AVOID", policy = "ALLOC";
    static boolean trace, autodetect;
    static int command;
    static Map<String, State> snapshots = new HashMap<>();
    static StringBuilder output = new StringBuilder();
    static void emit(String line) { output.append(line.stripTrailing()).append('\n'); }
    static String pname(int id) { return "P" + id; }
    static String plist(List<Integer> ids) { return ids.stream().map(Main::pname).collect(Collectors.joining(" ")); }
    static String vector(int[] v) { return "(" + Arrays.stream(v).mapToObj(Integer::toString).collect(Collectors.joining(",")) + ")"; }
    static String type(int i) { return Character.toString((char) ('A' + i)); }
    static int[] add(int[] a, int[] b) {
        int[] v = a.clone();
        for (int i = 0; i < v.length; i++) v[i] += b[i];
        return v;
    }
    static int[] sub(int[] a, int[] b) {
        int[] v = a.clone();
        for (int i = 0; i < v.length; i++) v[i] -= b[i];
        return v;
    }
    static boolean fits(int[] a, int[] b) {
        for (int i = 0; i < a.length; i++) if (a[i] > b[i]) return false;
        return true;
    }
    static int sum(int[] v) { return Arrays.stream(v).sum(); }
    static boolean zero(int[] v) { return sum(v) == 0; }
    static void fail(String message) { throw new IllegalArgumentException(message); }
    static Waiting waiting(int id) {
        for (Waiting w : state.queue) if (w.id == id) return w;
        return null;
    }
    static Process require(int id, boolean unblocked) {
        Process p = state.processes.get(id);
        if (p == null) fail("unknown process " + pname(id));
        if (unblocked && waiting(id) != null) fail("process " + pname(id) + " is blocked");
        return p;
    }
    static int[] requestOf(int id) {
        Waiting w = waiting(id);
        return w == null ? new int[state.total.length] : w.vector;
    }
    static int[] parseVector(String[] words, int start) {
        if (words.length - start != state.total.length) fail("wrong vector length");
        int[] v = new int[words.length - start];
        for (int i = 0; i < v.length; i++) v[i] = Integer.parseInt(words[start + i]);
        return v;
    }
    static Check check(int[] available, boolean detecting, boolean traced, Set<Integer> excluded) {
        int[] work = available.clone();
        List<Integer> remaining = new ArrayList<>(), idle = new ArrayList<>(), sequence = new ArrayList<>();
        for (Process p : state.processes.values()) {
            if (excluded.contains(p.id)) work = add(work, p.allocation);
            else if (detecting && zero(p.allocation)) idle.add(p.id);
            else remaining.add(p.id);
        }
        String prefix = detecting ? "[detect]" : "[safety]";
        if (traced) emit(prefix + " start work=" + vector(work) + (idle.isEmpty() ? "" : " idle " + plist(idle)));
        while (true) {
            Integer chosen = null;
            for (int id : remaining) {
                Process p = state.processes.get(id);
                if (fits(detecting ? requestOf(id) : p.need(), work)) { chosen = id; break; }
            }
            if (chosen == null) break;
            work = add(work, state.processes.get(chosen).allocation);
            remaining.remove(chosen); sequence.add(chosen);
            if (traced) emit(prefix + " " + pname(chosen) + " can finish, work=" + vector(work));
        }
        if (traced && !remaining.isEmpty()) emit(prefix + " stuck work=" + vector(work) + " remaining " + plist(remaining));
        return new Check(sequence, remaining);
    }
    static Check safety(int[] available, boolean traced) { return check(available, false, traced, Set.of()); }
    static List<Integer> detect(boolean traced) { return check(state.available, true, traced, Set.of()).remaining; }
    static String rejection(Process p, int[] v) {
        if (waiting(p.id) != null) return "process " + pname(p.id) + " is blocked";
        if (zero(v)) return "zero vector";
        if (!fits(v, p.need())) return "request exceeds need";
        if (mode.equals("ORDER")) {
            int last = -1;
            for (int i = 0; i < v.length; i++) if (p.allocation[i] > 0) last = i;
            for (int i = 0; i <= last; i++) if (v[i] > 0) return "resource order violation";
        }
        return null;
    }
    static Decision decision(Process p, int[] v, boolean traced) {
        if (!fits(v, state.available)) return new Decision("insufficient resources", List.of());
        if (!mode.equals("AVOID")) return new Decision(null, List.of());
        int[] old = p.allocation;
        p.allocation = add(old, v);
        Check c = safety(sub(state.available, v), traced);
        p.allocation = old;
        return new Decision(c.remaining.isEmpty() ? null : "unsafe state", c.sequence);
    }
    static void allocate(Process p, int[] v) { p.allocation = add(p.allocation, v); state.available = sub(state.available, v); }
    static void record(String kind, int id, int[] v, int waited) { state.history.add(new Event(command, kind, id, v.clone(), waited)); }
    static void retry() {
        List<Waiting> kept = new ArrayList<>();
        for (Waiting w : state.queue) {
            Process p = state.processes.get(w.id);
            if (decision(p, w.vector, trace).reason == null) {
                allocate(p, w.vector);
                emit("unblocked " + pname(w.id) + " " + vector(w.vector));
                record("unblocked", w.id, w.vector, command - w.since);
            } else kept.add(w);
        }
        state.queue = kept;
    }
    static void terminate(int id, String kind) {
        Process p = state.processes.remove(id);
        state.queue.removeIf(w -> w.id == id);
        state.available = add(state.available, p.allocation);
        emit(kind + " " + pname(id) + " released " + vector(p.allocation));
        record(kind, id, p.allocation, 0);
    }
    static int sequences(List<Integer> ids, List<Integer> path, int[] work, int limit, List<String> found) {
        if (path.size() == ids.size()) {
            if (found.size() < limit) found.add(plist(path));
            return 1;
        }
        int count = 0;
        for (int id : ids) {
            Process p = state.processes.get(id);
            if (!path.contains(id) && fits(p.need(), work)) {
                path.add(id);
                count += sequences(ids, path, add(work, p.allocation), limit, found);
                path.remove(path.size() - 1);
            }
        }
        return count;
    }
    static int compareLists(List<Integer> a, List<Integer> b) {
        for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
            int c = Integer.compare(a.get(i), b.get(i));
            if (c != 0) return c;
        }
        return Integer.compare(a.size(), b.size());
    }
    record Edge(int destination, int resource) {}
    static void cycles(int start, int current, Map<Integer, List<Edge>> edges, Set<Integer> visited,
                       List<Integer> key, List<String> labels, List<List<Integer>> keys, List<String> lines, boolean resourceGraph) {
        for (Edge edge : edges.get(current)) {
            int next = edge.destination;
            if (next < start) continue;
            List<Integer> newKey = new ArrayList<>(key);
            List<String> newLabels = new ArrayList<>(labels);
            if (resourceGraph) { newKey.add(edge.resource); newLabels.add(type(edge.resource)); }
            newKey.add(next); newLabels.add(pname(next));
            if (next == start) {
                if (resourceGraph || visited.size() > 1) { keys.add(newKey); lines.add("cycle: " + String.join(" -> ", newLabels)); }
            } else if (!visited.contains(next)) {
                visited.add(next);
                cycles(start, next, edges, visited, newKey, newLabels, keys, lines, resourceGraph);
                visited.remove(next);
            }
        }
    }
    static void graph(boolean resources) {
        int m = state.total.length;
        if (resources && Arrays.stream(state.total).anyMatch(x -> x != 1)) fail("not single-instance");
        Map<Integer, List<Edge>> edges = new TreeMap<>();
        for (int id : state.processes.keySet()) edges.put(id, new ArrayList<>());
        boolean any = false;
        if (!resources) {
            for (Process p : state.processes.values()) {
                int[] req = requestOf(p.id);
                for (Process q : state.processes.values()) {
                    if (p.id == q.id) continue;
                    List<String> labels = new ArrayList<>();
                    for (int i = 0; i < m; i++) if (req[i] > state.available[i] && q.allocation[i] > 0) labels.add(type(i));
                    if (!labels.isEmpty()) {
                        edges.get(p.id).add(new Edge(q.id, -1)); any = true;
                        emit(pname(p.id) + " -> " + pname(q.id) + " on " + String.join(",", labels));
                    }
                }
            }
            if (!any) emit("no wait edges");
        } else {
            int[] holders = new int[m]; Arrays.fill(holders, -1);
            for (Process p : state.processes.values()) for (int i = 0; i < m; i++) if (p.allocation[i] > 0) holders[i] = p.id;
            for (int i = 0; i < m; i++) if (holders[i] >= 0) emit("assign " + type(i) + " -> " + pname(holders[i]));
            for (Process p : state.processes.values()) {
                int[] req = requestOf(p.id);
                for (int i = 0; i < m; i++) if (req[i] > 0) {
                    emit("request " + pname(p.id) + " -> " + type(i));
                    if (holders[i] >= 0) edges.get(p.id).add(new Edge(holders[i], i));
                }
            }
            for (Process p : state.processes.values()) {
                int[] req = requestOf(p.id), need = p.need();
                for (int i = 0; i < m; i++) if (need[i] > 0 && req[i] == 0) emit("claim " + pname(p.id) + " -> " + type(i));
            }
        }
        List<List<Integer>> keys = new ArrayList<>(); List<String> lines = new ArrayList<>();
        for (int start : state.processes.keySet()) cycles(start, start, edges, new HashSet<>(Set.of(start)), List.of(start), List.of(pname(start)), keys, lines, resources);
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < keys.size(); i++) order.add(i);
        order.sort((a, b) -> compareLists(keys.get(a), keys.get(b)));
        for (int i : order) emit(lines.get(i));
        if (order.isEmpty()) emit("no cycles");
    }
    static String table(int[] v) {
        List<String> parts = new ArrayList<>();
        for (int i = 0; i < v.length; i++) parts.add(String.format(Locale.ROOT, "%" + Integer.toString(state.total[i]).length() + "d", v[i]));
        return String.join(" ", parts);
    }
    static void row(String heading, String[] contents, int[] widths) {
        StringBuilder line = new StringBuilder(String.format("%-9s", heading));
        for (int i = 0; i < 4; i++) line.append("  ").append(String.format("%-" + widths[i] + "s", contents[i]));
        emit(line.toString());
    }
    static void showState() {
        List<String> names = new ArrayList<>();
        for (int i = 0; i < state.total.length; i++) names.add(String.format("%" + Integer.toString(state.total[i]).length() + "s", type(i)));
        String name = String.join(" ", names);
        String[] headings = {"Allocation", "Max", "Need", "Request"};
        int[] widths = Arrays.stream(headings).mapToInt(h -> Math.max(h.length(), name.length())).toArray();
        row("Process", headings, widths); row("", new String[]{name, name, name, name}, widths);
        for (Process p : state.processes.values()) row(pname(p.id), new String[]{table(p.allocation), table(p.max), table(p.need()), table(requestOf(p.id))}, widths);
        row("Available", new String[]{table(state.available), "", "", ""}, widths);
        row("Total", new String[]{table(state.total), "", "", ""}, widths);
        List<String> queue = new ArrayList<>();
        for (Waiting w : state.queue) queue.add(pname(w.id) + " " + vector(w.vector) + " since t=" + w.since);
        emit("blocked queue: " + (queue.isEmpty() ? "empty" : String.join(", ", queue)));
    }
    static void stats() {
        for (int i = 0; i < state.total.length; i++) {
            int total = state.total[i], used = total - state.available[i], requested = 0;
            for (Waiting w : state.queue) requested += w.vector[i];
            int percent = used * 1000 / total;
            emit(type(i) + ": allocated " + used + "/" + total + " (" + percent / 10 + "." + percent % 10 + "%), requested " + requested);
        }
        List<String> counts = new ArrayList<>(); int waits = 0, totalWait = 0;
        for (String kind : KINDS) counts.add(kind + " " + state.history.stream().filter(e -> e.kind.equals(kind)).count());
        emit("events: " + String.join(", ", counts));
        for (Event e : state.history) if (e.kind.equals("unblocked")) { waits++; totalWait += e.waited; }
        if (waits == 0) emit("waits: none");
        else {
            int average = totalWait * 100 / waits;
            emit("waits: " + waits + " unblocked, total " + totalWait + ", average " + average / 100 + "." + String.format(Locale.ROOT, "%02d", average % 100));
        }
    }
    static void execute(String[] w) {
        String c = w[0];
        if (Set.of("MODE", "POLICY", "TRACE", "AUTODETECT").contains(c)) {
            switch (c) {
                case "MODE" -> mode = w[1];
                case "POLICY" -> policy = w[1];
                case "TRACE" -> trace = w[1].equals("ON");
                case "AUTODETECT" -> autodetect = w[1].equals("ON");
            }
            emit(c.toLowerCase(Locale.ROOT) + " " + w[1]); return;
        }
        if (c.equals("RESOURCES")) {
            int[] v = Arrays.stream(w).skip(1).mapToInt(Integer::parseInt).toArray();
            state = new State(v); emit("resources " + vector(v)); return;
        }
        if (Set.of("PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE").contains(c)) {
            int id = Integer.parseInt(w[1]); int[] v = parseVector(w, 2); String name = pname(id);
            if (c.equals("PROCESS")) {
                if (state.processes.containsKey(id)) fail("duplicate process " + name);
                if (!fits(v, state.total)) fail("max exceeds total");
                state.processes.put(id, new Process(id, v, command)); emit("process " + name + " max " + vector(v)); return;
            }
            Process p = require(id, c.equals("CLAIM") || c.equals("RELEASE"));
            if (c.equals("CLAIM")) {
                if (!fits(p.allocation, v)) fail("claim below allocation");
                if (!fits(v, state.total)) fail("max exceeds total");
                int[] old = p.max; p.max = v;
                boolean unsafe = mode.equals("AVOID") && !safety(state.available, trace).remaining.isEmpty();
                p.max = old;
                if (unsafe) fail("claim makes state unsafe");
                p.max = v; emit("claim " + name + " max " + vector(v)); retry(); return;
            }
            if (c.equals("RELEASE")) {
                if (zero(v)) fail("zero vector");
                if (!fits(v, p.allocation)) fail("release exceeds allocation");
                p.allocation = sub(p.allocation, v); state.available = add(state.available, v);
                emit("released " + name + " " + vector(v)); record("released", id, v, 0); retry(); return;
            }
            String reject = rejection(p, v), prefix = "whatif " + name + " " + vector(v);
            if (reject != null) {
                if (c.equals("REQUEST")) fail(reject);
                emit(prefix + ": rejected (" + reject + ")"); return;
            }
            Decision d = decision(p, v, trace);
            if (c.equals("WHATIF")) {
                if (d.reason != null) emit(prefix + ": blocked (" + d.reason + ")");
                else emit(prefix + ": granted" + (mode.equals("AVOID") ? ", safe sequence " + plist(d.sequence) : ""));
            } else if (d.reason == null) {
                allocate(p, v); emit("granted " + name + " " + vector(v)); record("granted", id, v, 0);
            } else {
                state.queue.add(new Waiting(id, v, command)); emit("blocked " + name + " " + vector(v) + ": " + d.reason); record("blocked", id, v, 0);
                if (autodetect) { List<Integer> dead = detect(trace); if (!dead.isEmpty()) emit("deadlock detected: " + plist(dead)); }
            }
            return;
        }
        if (c.equals("ADD") || c.equals("REMOVE")) {
            int[] v = parseVector(w, 1);
            if (zero(v)) fail("zero vector");
            if (c.equals("ADD")) {
                state.total = add(state.total, v); state.available = add(state.available, v);
                emit("added " + vector(v) + " total " + vector(state.total)); retry();
            } else {
                if (!fits(v, state.available)) fail("remove exceeds available");
                int[] total = sub(state.total, v), available = sub(state.available, v);
                if (Arrays.stream(total).anyMatch(x -> x == 0)) fail("total must stay positive");
                for (Process p : state.processes.values()) if (!fits(p.max, total)) fail("max exceeds total");
                if (mode.equals("AVOID") && !safety(available, trace).remaining.isEmpty()) fail("removal makes state unsafe");
                state.total = total; state.available = available; emit("removed " + vector(v) + " total " + vector(total));
            }
            return;
        }
        switch (c) {
            case "FINISH", "ABORT" -> { int id = Integer.parseInt(w[1]); require(id, c.equals("FINISH")); terminate(id, c.equals("FINISH") ? "finished" : "aborted"); retry(); }
            case "CANCEL" -> {
                int id = Integer.parseInt(w[1]); require(id, false); Waiting entry = waiting(id);
                if (entry == null) fail("process " + pname(id) + " is not blocked");
                state.queue.remove(entry); emit("cancelled " + pname(id) + " " + vector(entry.vector)); record("cancelled", id, entry.vector, 0);
            }
            case "MAXGRANT" -> {
                int id = Integer.parseInt(w[1]); Process p = require(id, true); int[] result = new int[state.total.length];
                for (int i = 0; i < result.length; i++) {
                    int[] v = new int[result.length];
                    for (int amount = p.need()[i]; amount > 0; amount--) {
                        v[i] = amount;
                        if (rejection(p, v) == null && decision(p, v, false).reason == null) { result[i] = amount; break; }
                    }
                }
                emit("maxgrant " + pname(id) + ": " + vector(result));
            }
            case "SAFE" -> {
                if (state.processes.isEmpty()) emit("safe: no processes");
                else { Check r = safety(state.available, trace); emit(r.remaining.isEmpty() ? "safe: " + plist(r.sequence) : "unsafe: " + plist(r.remaining) + " cannot finish"); }
            }
            case "SEQUENCES" -> {
                if (state.processes.isEmpty()) emit("safe sequences: no processes");
                else { List<String> found = new ArrayList<>(); int n = sequences(new ArrayList<>(state.processes.keySet()), new ArrayList<>(), state.available, Integer.parseInt(w[1]), found); emit("safe sequences: " + n); for (String line : found) emit(line); }
            }
            case "DEFICIT" -> {
                List<String> results = new ArrayList<>();
                for (int i = 0; i < state.total.length; i++) {
                    int limit = 0; for (Process p : state.processes.values()) limit += p.need()[i];
                    String result = "-";
                    for (int x = 0; x <= limit; x++) { int[] work = state.available.clone(); work[i] += x; if (safety(work, false).remaining.isEmpty()) { result = Integer.toString(x); break; } }
                    results.add(result);
                }
                emit("deficit: (" + String.join(",", results) + ")");
            }
            case "STATE" -> showState();
            case "STATS" -> stats();
            case "DETECT" -> { List<Integer> dead = detect(trace); emit(dead.isEmpty() ? "no deadlock" : "deadlocked: " + plist(dead)); }
            case "VICTIMS" -> {
                List<Integer> dead = detect(false);
                if (dead.isEmpty()) { emit("no deadlock"); break; }
                List<List<Integer>> groups = new ArrayList<>();
                for (int mask = 1; mask < (1 << dead.size()); mask++) { List<Integer> g = new ArrayList<>(); for (int i = 0; i < dead.size(); i++) if ((mask & (1 << i)) != 0) g.add(dead.get(i)); groups.add(g); }
                groups.sort((a, b) -> { int cmp = Integer.compare(a.size(), b.size()); if (cmp == 0) cmp = Integer.compare(a.stream().mapToInt(id -> sum(state.processes.get(id).allocation)).sum(), b.stream().mapToInt(id -> sum(state.processes.get(id).allocation)).sum()); return cmp != 0 ? cmp : compareLists(a, b); });
                for (List<Integer> group : groups) if (check(state.available, true, false, new HashSet<>(group)).remaining.isEmpty()) { emit("victims: " + plist(group)); break; }
            }
            case "RECOVER" -> {
                List<Integer> dead = detect(trace); int count = 0;
                if (w.length > 1) {
                    for (int id : dead) { terminate(id, "aborted"); count++; }
                    if (count > 0) retry();
                } else while (!dead.isEmpty()) {
                    int victim = dead.get(0);
                    for (int id : dead) {
                        Process a = state.processes.get(id), b = state.processes.get(victim);
                        boolean better = switch (policy) {
                            case "ALLOC" -> sum(a.allocation) < sum(b.allocation) || (sum(a.allocation) == sum(b.allocation) && id > victim);
                            case "NEED" -> sum(a.need()) > sum(b.need()) || (sum(a.need()) == sum(b.need()) && id > victim);
                            default -> a.created > b.created;
                        };
                        if (better) victim = id;
                    }
                    terminate(victim, "aborted"); retry(); count++; dead = detect(trace);
                }
                emit(count == 0 ? "no deadlock" : "recovered: " + count + " aborted");
            }
            case "WAITGRAPH" -> graph(false);
            case "GRAPH" -> graph(true);
            case "HISTORY" -> {
                boolean any = false;
                for (Event e : state.history) {
                    if (w.length > 1 && !(Character.isDigit(w[1].charAt(0)) ? e.id == Integer.parseInt(w[1]) : e.kind.equals(w[1]))) continue;
                    emit("t=" + e.command + " " + e.kind + " " + pname(e.id) + " " + vector(e.vector) + (e.kind.equals("unblocked") ? " waited " + e.waited : "")); any = true;
                }
                if (!any) emit("no events");
            }
            case "SNAPSHOT" -> { snapshots.put(w[1], state.copy()); emit("saved " + w[1]); }
            case "RESTORE" -> { if (!snapshots.containsKey(w[1])) fail("unknown snapshot " + w[1]); state = snapshots.get(w[1]).copy(); emit("restored " + w[1]); }
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(reader.readLine());
        for (command = 1; command <= n; command++) {
            try { execute(reader.readLine().split(" ")); }
            catch (IllegalArgumentException e) { emit("error: " + e.getMessage()); }
        }
        System.out.print(output);
    }
}
