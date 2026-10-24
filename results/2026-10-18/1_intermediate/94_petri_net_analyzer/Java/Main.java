import java.io.*;
import java.util.*;

public class Main {
    static final BufferedReader INPUT = new BufferedReader(new InputStreamReader(System.in));
    static void out(String s) { System.out.println(s); }
    static String yes(boolean b) { return b ? "yes" : "no"; }
    static String listed(List<String> a) { return a.isEmpty() ? "none" : String.join(" ", a); }
    static void bad(String reason) { throw new IllegalArgumentException(reason); }
    static long number(String s, long lo, long hi) {
        if (!s.matches("0|[1-9][0-9]{0,9}")) return -1;
        long n = Long.parseLong(s); return n >= lo && n <= hi ? n : -1;
    }
    static String mark(long[] a) { List<String> r = new ArrayList<>(); for (long x : a) r.add(x < 0 ? "w" : Long.toString(x)); return "(" + String.join(",", r) + ")"; }
    static boolean[] visit(List<List<Integer>> adj, int start) {
        boolean[] seen = new boolean[adj.size()]; List<Integer> q = new ArrayList<>(); q.add(start); seen[start] = true;
        for (int i = 0; i < q.size(); ++i) for (int v : adj.get(q.get(i))) if (!seen[v]) { seen[v] = true; q.add(v); }
        return seen;
    }
    static List<List<Integer>> adjacency(int n) { List<List<Integer>> a = new ArrayList<>(); for (int i = 0; i < n; ++i) a.add(new ArrayList<>()); return a; }
    static boolean all(boolean[] a) { for (boolean v : a) if (!v) return false; return true; }
    static int count(boolean[] a) { int n = 0; for (boolean b : a) if (b) ++n; return n; }
    static long gcd(long a, long b) { while (b != 0) { long c = a % b; a = b; b = c; } return Math.abs(a); }
    static List<long[]> flows(long[][] a) {
        int n = a.length, m = a[0].length; List<long[]> rows = new ArrayList<>();
        for (int i = 0; i < n; ++i) { long[] r = Arrays.copyOf(a[i], m + n); r[m + i] = 1; rows.add(r); }
        for (int j = 0; j < m; ++j) {
            Map<String,long[]> unique = new LinkedHashMap<>();
            for (long[] r : rows) if (r[j] == 0) unique.put(Arrays.toString(r), r);
            for (long[] r : rows) if (r[j] > 0) for (long[] s : rows) if (s[j] < 0) {
                long[] v = new long[m + n]; long d = 0;
                for (int k = 0; k < v.length; ++k) { v[k] = -s[j] * r[k] + r[j] * s[k]; d = gcd(d, v[k]); }
                for (int k = 0; k < v.length; ++k) v[k] /= d;
                unique.put(Arrays.toString(v), v);
            }
            List<long[]> candidates = new ArrayList<>(unique.values()); int[] supports = new int[candidates.size()];
            for (int i = 0; i < candidates.size(); ++i) for (int k = 0; k < n; ++k) if (candidates.get(i)[m + k] > 0) supports[i] |= 1 << k;
            rows = new ArrayList<>();
            for (int i = 0; i < candidates.size(); ++i) { boolean minimal = true; for (int s : supports) if (s != supports[i] && (s & supports[i]) == s) { minimal = false; break; } if (minimal) rows.add(candidates.get(i)); }
        }
        List<long[]> result = new ArrayList<>(); for (long[] r : rows) result.add(Arrays.copyOfRange(r, m, m + n)); result.sort((x,y) -> Arrays.compare(y,x)); return result;
    }
    record Edge(int transition, int target) {}
    static class Graph {
        List<long[]> states = new ArrayList<>(); List<Integer> parent = new ArrayList<>(), via = new ArrayList<>(); List<List<Edge>> edges = new ArrayList<>(); int found = -1; boolean aborted;
        void add(long[] m, int p, int t) { states.add(m); parent.add(p); via.add(t); edges.add(new ArrayList<>()); }
    }
    static class Net {
        String name; List<String> places = new ArrayList<>(), transitions = new ArrayList<>(); List<Long> initial = new ArrayList<>(), capacities = new ArrayList<>(), priorities = new ArrayList<>();
        long[][] pre = new long[16][16], post = new long[16][16], inhibitor = new long[16][16]; long[] current; List<long[]> history = new ArrayList<>(); int arcs, inhibitors;
        Net(String name) { this.name = name; }
        int p(String s) { return places.indexOf(s); } int t(String s) { return transitions.indexOf(s); }
        void define(String[] w) {
            String cmd = w[0]; int n = w.length - 1;
            if (!Set.of("place","transition","arc","inhibit").contains(cmd)) bad("unknown definition " + cmd);
            if (!(cmd.equals("place") ? n == 2 || n == 3 : cmd.equals("transition") ? n == 1 || n == 2 : n == 3)) bad("wrong number of arguments");
            String a = w[1];
            if (cmd.equals("place") || cmd.equals("transition")) {
                if (p(a) >= 0 || t(a) >= 0) bad("duplicate name " + a);
                if (cmd.equals("place")) { if (n == 3 && Long.parseLong(w[2]) > Long.parseLong(w[3])) bad("tokens exceed capacity of " + a); places.add(a); initial.add(Long.parseLong(w[2])); capacities.add(n == 3 ? Long.parseLong(w[3]) : 0L); }
                else { transitions.add(a); priorities.add(n == 2 ? Long.parseLong(w[2]) : 0L); }
            } else if (cmd.equals("arc")) {
                String b = w[2]; for (String x : List.of(a,b)) if (p(x) < 0 && t(x) < 0) bad("unknown node " + x);
                int pa = p(a), pb = p(b); if ((pa >= 0) == (pb >= 0)) bad("arc must connect a place and a transition"); int pi = pa >= 0 ? pa : pb, ti = t(pa >= 0 ? b : a); long[][] matrix = pa >= 0 ? pre : post;
                if (matrix[pi][ti] != 0) bad("duplicate arc " + a + " " + b); matrix[pi][ti] = Long.parseLong(w[3]); ++arcs;
            } else {
                int pi = p(a), ti = t(w[2]); if (pi < 0) bad("unknown place " + a); if (ti < 0) bad("unknown transition " + w[2]); if (inhibitor[pi][ti] != 0) bad("duplicate inhibitor " + a + " " + w[2]); inhibitor[pi][ti] = Long.parseLong(w[3]); ++inhibitors;
            }
        }
        long[] initialMarking() { long[] m = new long[places.size()]; for (int i = 0; i < m.length; ++i) m[i] = initial.get(i); return m; }
        String reason(long[] m, int t) {
            for (int p = 0; p < m.length; ++p) if (m[p] >= 0 && m[p] < pre[p][t]) return "insufficient tokens in " + places.get(p);
            for (int p = 0; p < m.length; ++p) if (inhibitor[p][t] > 0 && (m[p] < 0 || m[p] >= inhibitor[p][t])) return "inhibited by " + places.get(p);
            for (int p = 0; p < m.length; ++p) if (capacities.get(p) > 0 && (m[p] < 0 || m[p] - pre[p][t] + post[p][t] > capacities.get(p))) return "capacity of " + places.get(p) + " exceeded";
            return "";
        }
        List<Integer> enabled(long[] m) { List<Integer> r = new ArrayList<>(); for (int t = 0; t < transitions.size(); ++t) if (reason(m,t).isEmpty()) r.add(t); return r; }
        long[] fire(long[] m, int t) { long[] r = m.clone(); for (int p = 0; p < r.length; ++p) if (r[p] >= 0) r[p] += post[p][t] - pre[p][t]; return r; }
        void commit(int t) { history.add(current); current = fire(current,t); }
        List<String> names(List<Integer> ts) { List<String> r = new ArrayList<>(); for (int t : ts) r.add(transitions.get(t)); return r; }
        boolean matches(long[] m, long[][] target) { if (target == null) return false; for (int p = 0; p < m.length; ++p) if (m[p] < target[p][0] || target[p][1] >= 0 && m[p] != target[p][1]) return false; return true; }
        Graph graph(long[] start, int limit, long[][] target) {
            Graph g = new Graph(); g.add(start.clone(), -1, -1); Map<String,Integer> index = new HashMap<>(); index.put(Arrays.toString(start),0);
            if (matches(start,target)) { g.found = 0; return g; }
            for (int q = 0; q < g.states.size(); ++q) for (int t : enabled(g.states.get(q))) {
                long[] m = fire(g.states.get(q),t); String key = Arrays.toString(m); Integer k = index.get(key);
                if (k == null) { if (g.states.size() == limit) { g.aborted = true; return g; } k = g.states.size(); index.put(key,k); g.add(m,q,t); if (matches(m,target)) { g.found = k; return g; } }
                g.edges.get(q).add(new Edge(t,k));
            }
            return g;
        }
        List<Integer> path(Graph g, int k) { List<Integer> a = new ArrayList<>(); while (g.parent.get(k) >= 0) { a.add(g.via.get(k)); k = g.parent.get(k); } Collections.reverse(a); return a; }
        void reach(int limit, boolean display) {
            Graph g = graph(current,limit,null); if (g.aborted) { out("reachability graph limit " + limit + " exceeded"); return; } int n = g.states.size();
            if (display) { for (int i = 0; i < n; ++i) { List<String> a = new ArrayList<>(); for (Edge e : g.edges.get(i)) a.add(transitions.get(e.transition()) + "->M" + e.target()); out("M" + i + " " + mark(g.states.get(i)) + ": " + (a.isEmpty() ? "dead" : String.join(" ",a))); } return; }
            List<List<Integer>> adj = adjacency(n); for (int i = 0; i < n; ++i) for (Edge e : g.edges.get(i)) adj.get(i).add(e.target()); boolean[][] closure = new boolean[n][]; for (int i = 0; i < n; ++i) closure[i] = visit(adj,i);
            int[] comp = new int[n]; Arrays.fill(comp,-1); int components = 0;
            for (int i = 0; i < n; ++i) if (comp[i] < 0) { for (int j = i; j < n; ++j) if (closure[i][j] && closure[j][i]) comp[j] = components; ++components; }
            boolean[] terminal = new boolean[components], home = new boolean[n]; Arrays.fill(terminal,true); Arrays.fill(home,true); long[] max = new long[places.size()]; List<Integer> dead = new ArrayList<>(); int edgeCount = 0; boolean persistent = true;
            for (int i = 0; i < n; ++i) { if (g.edges.get(i).isEmpty()) dead.add(i); edgeCount += g.edges.get(i).size(); for (int p = 0; p < max.length; ++p) max[p] = Math.max(max[p],g.states.get(i)[p]); for (int j = 0; j < n; ++j) home[j] &= closure[i][j]; for (Edge e : g.edges.get(i)) { if (comp[i] != comp[e.target()]) terminal[comp[i]] = false; for (Edge other : g.edges.get(i)) if (e.transition() != other.transition() && !reason(g.states.get(e.target()),other.transition()).isEmpty()) persistent = false; } }
            out("reachable markings: " + n); out("edges: " + edgeCount); out("components: " + components + " (terminal " + count(terminal) + ")"); out("dead markings: " + dead.size());
            for (int i : dead) { List<String> a = names(path(g,i)); out("  M" + i + " " + mark(g.states.get(i)) + " path " + (a.isEmpty() ? "empty" : String.join(" ",a))); }
            long bound = Arrays.stream(max).max().orElse(0); out("max tokens: " + mark(max)); out("bound: " + bound); out("safe: " + yes(bound <= 1)); out("home markings: " + count(home)); out("reversible: " + yes(home[0])); out("persistent: " + yes(persistent));
            List<String> levels = new ArrayList<>();
            for (int t = 0; t < transitions.size(); ++t) { boolean[] present = new boolean[components]; boolean used = false, cycle = false; for (int i = 0; i < n; ++i) for (Edge e : g.edges.get(i)) if (e.transition() == t) { used = true; present[comp[i]] = true; if (comp[i] == comp[e.target()]) cycle = true; } boolean live = true; for (int c = 0; c < components; ++c) if (terminal[c] && !present[c]) live = false; levels.add(transitions.get(t) + "=" + (live ? "L4" : cycle ? "L3" : used ? "L1" : "L0")); }
            out("liveness: " + String.join(" ",levels));
        }
        long rank(long v) { return v < 0 ? Long.MAX_VALUE : v; }
        void cover(int limit) {
            Graph g = new Graph(); g.add(current.clone(),-1,-1); List<Boolean> old = new ArrayList<>(), dead = new ArrayList<>(); old.add(false); dead.add(false); Set<String> seen = new HashSet<>(); seen.add(Arrays.toString(current));
            for (int q = 0; q < g.states.size(); ++q) { if (old.get(q)) continue; List<Integer> es = enabled(g.states.get(q)); dead.set(q,es.isEmpty()); List<Integer> ancestors = new ArrayList<>(); for (int a = q; a >= 0; a = g.parent.get(a)) ancestors.add(a); Collections.reverse(ancestors);
                for (int t : es) { long[] m = fire(g.states.get(q),t); for (int a : ancestors) { boolean ge = true, gt = false; for (int p = 0; p < m.length; ++p) { ge &= rank(m[p]) >= rank(g.states.get(a)[p]); gt |= rank(m[p]) > rank(g.states.get(a)[p]); } if (ge && gt) for (int p = 0; p < m.length; ++p) if (capacities.get(p) == 0 && rank(m[p]) > rank(g.states.get(a)[p])) m[p] = -1; } if (g.states.size() == limit) { out("coverability tree limit " + limit + " exceeded"); return; } old.add(!seen.add(Arrays.toString(m))); dead.add(false); g.add(m,q,t); }
            }
            out("coverability tree nodes: " + g.states.size()); long[] max = new long[places.size()];
            for (int i = 0; i < g.states.size(); ++i) { out("  " + i + " " + mark(g.states.get(i)) + " " + (i == 0 ? "root" : "<- " + g.parent.get(i) + " " + transitions.get(g.via.get(i))) + (old.get(i) ? " old" : "") + (dead.get(i) ? " dead" : "")); for (int p = 0; p < max.length; ++p) if (rank(g.states.get(i)[p]) > rank(max[p])) max[p] = g.states.get(i)[p]; }
            List<String> unbounded = new ArrayList<>(); for (int p = 0; p < max.length; ++p) if (max[p] < 0) unbounded.add(places.get(p)); out("bounds: " + mark(max)); out("unbounded: " + listed(unbounded));
        }
        List<Integer> bits(int mask) { List<Integer> a = new ArrayList<>(); for (int p = 0; p < places.size(); ++p) if ((mask & 1 << p) != 0) a.add(p); return a; }
        List<Integer> sets(boolean trap) {
            List<Integer> found = new ArrayList<>(); for (int mask = 1; mask < 1 << places.size(); ++mask) { boolean valid = true; for (int t = 0; t < transitions.size(); ++t) { boolean in = false, out = false; for (int p = 0; p < places.size(); ++p) if ((mask & 1 << p) != 0) { in |= post[p][t] > 0; out |= pre[p][t] > 0; } if (trap ? out && !in : in && !out) { valid = false; break; } } if (valid) found.add(mask); }
            List<Integer> result = new ArrayList<>(); for (int m : found) { boolean minimal = true; for (int s : found) if (s != m && (s & m) == s) { minimal = false; break; } if (minimal) result.add(m); }
            result.sort((a,b) -> { int c = Integer.compare(Integer.bitCount(a),Integer.bitCount(b)); if (c != 0) return c; List<Integer> x = bits(a), y = bits(b); for (int i = 0; i < x.size(); ++i) if (!x.get(i).equals(y.get(i))) return Integer.compare(x.get(i),y.get(i)); return 0; }); return result;
        }
        String setText(int mask) { List<String> a = new ArrayList<>(); for (int p : bits(mask)) a.add(places.get(p)); return "{" + String.join(",",a) + "}"; }
        List<Integer> realize(long[] counts) {
            long[] used = new long[counts.length]; List<long[]> stack = new ArrayList<>(); stack.add(current); List<Integer> choices = new ArrayList<>(), path = new ArrayList<>(); choices.add(0); Set<String> seen = new HashSet<>(); long total = Arrays.stream(counts).sum();
            while (!stack.isEmpty()) { int d = path.size(); if (d == total) return path; int chosen = -1; for (int t = choices.get(d); t < counts.length; ++t) { choices.set(d,t+1); if (used[t] >= counts[t] || !reason(stack.get(d),t).isEmpty()) continue; ++used[t]; boolean fresh = seen.add(Arrays.toString(used)); --used[t]; if (fresh) { chosen = t; break; } } if (chosen >= 0) { ++used[chosen]; path.add(chosen); stack.add(fire(stack.get(d),chosen)); choices.add(0); } else { stack.removeLast(); choices.removeLast(); if (!path.isEmpty()) --used[path.removeLast()]; } }
            return null;
        }
        void invariants(boolean transpose) {
            long[][] a = new long[transpose ? transitions.size() : places.size()][transpose ? places.size() : transitions.size()]; for (int p = 0; p < places.size(); ++p) for (int t = 0; t < transitions.size(); ++t) { if (transpose) a[t][p] = post[p][t]-pre[p][t]; else a[p][t] = post[p][t]-pre[p][t]; }
            List<long[]> f = flows(a); List<String> ns = transpose ? transitions : places; boolean[] covered = new boolean[ns.size()]; long[] bounds = new long[ns.size()]; Arrays.fill(bounds,-1); out((transpose ? "T" : "P") + "-semiflows: " + f.size());
            for (long[] c : f) { List<String> terms = new ArrayList<>(); long value = 0; for (int i = 0; i < c.length; ++i) if (c[i] > 0) { covered[i] = true; terms.add((c[i] == 1 ? "" : c[i] + "*") + ns.get(i)); if (!transpose) value += c[i] * current[i]; } String text = "  " + String.join(" + ",terms); if (transpose) { List<Integer> path = realize(c); out(text + ": " + (path == null ? "not realizable" : "realizable " + String.join(" ",names(path)))); } else { out(text + " = " + value); for (int p = 0; p < c.length; ++p) if (c[p] > 0) bounds[p] = bounds[p] < 0 ? value/c[p] : Math.min(bounds[p],value/c[p]); } }
            if (!transpose) { List<String> b = new ArrayList<>(); for (long x : bounds) b.add(x < 0 ? "-" : Long.toString(x)); out("bounds: (" + String.join(",",b) + ")"); } out((transpose ? "consistent: " : "conservative: ") + yes(all(covered)));
        }
        void classify() {
            int P = places.size(), T = transitions.size(); List<List<Integer>> inputs = adjacency(T), outputs = adjacency(P); boolean ordinary = true, pure = true, sm = true, mg = true, fc = true, efc = true;
            for (int p = 0; p < P; ++p) for (int t = 0; t < T; ++t) { ordinary &= pre[p][t] <= 1 && post[p][t] <= 1; pure &= pre[p][t] == 0 || post[p][t] == 0; if (pre[p][t] > 0) { inputs.get(t).add(p); outputs.get(p).add(t); } }
            for (int t = 0; t < T; ++t) { int count = 0; for (int p = 0; p < P; ++p) if (post[p][t] > 0) ++count; sm &= inputs.get(t).size() == 1 && count == 1; }
            for (int p = 0; p < P; ++p) { int count = 0; for (int t = 0; t < T; ++t) if (post[p][t] > 0) ++count; mg &= outputs.get(p).size() == 1 && count == 1; for (int t : outputs.get(p)) if (outputs.get(p).size() != 1 && inputs.get(t).size() != 1) fc = false; for (int q = 0; q < P; ++q) for (int t : outputs.get(p)) if (pre[q][t] > 0 && !outputs.get(p).equals(outputs.get(q))) efc = false; }
            sm &= ordinary; mg &= ordinary; fc &= ordinary; efc &= ordinary;
            String[] labels = {"ordinary","pure","state machine","marked graph","free choice","extended free choice"}; boolean[] values = {ordinary,pure,sm,mg,fc,efc}; for (int i = 0; i < labels.length; ++i) out(labels[i] + ": " + yes(values[i]));
            String verdict = !fc ? "not applicable" : P > 12 ? "too many places" : "holds"; if (fc && P <= 12) { List<Integer> traps = sets(true); for (int s : sets(false)) { boolean holds = false; for (int q : traps) if ((s & q) == q) for (int p : bits(q)) if (current[p] > 0) holds = true; if (!holds) { verdict = "fails at " + setText(s); break; } } } out("commoner: " + verdict);
        }
        void workflow(int limit) {
            int P = places.size(), T = transitions.size(); List<Integer> sources = new ArrayList<>(), sinks = new ArrayList<>(); for (int p = 0; p < P; ++p) { boolean in = false, out = false; for (int t = 0; t < T; ++t) { in |= post[p][t] > 0; out |= pre[p][t] > 0; } if (!in) sources.add(p); if (!out) sinks.add(p); }
            if (sources.size() != 1) { out("workflow: no (" + sources.size() + " source places)"); return; } if (sinks.size() != 1) { out("workflow: no (" + sinks.size() + " sink places)"); return; } int i = sources.getFirst(), o = sinks.getFirst(); List<String> ns = new ArrayList<>(places); ns.addAll(transitions); List<List<Integer>> adj = adjacency(P+T), rev = adjacency(P+T);
            for (int p = 0; p < P; ++p) for (int t = 0; t < T; ++t) { if (pre[p][t] > 0) { adj.get(p).add(P+t); rev.get(P+t).add(p); } if (post[p][t] > 0) { adj.get(P+t).add(p); rev.get(p).add(P+t); } } boolean[] f = visit(adj,i), b = visit(rev,o); for (int v = 0; v < ns.size(); ++v) if (!f[v] || !b[v]) { out("workflow: no (" + ns.get(v) + " is not on a path from " + places.get(i) + " to " + places.get(o) + ")"); return; }
            out("workflow: source " + places.get(i) + " sink " + places.get(o)); long[] start = new long[P], goal = new long[P]; start[i] = 1; goal[o] = 1; Graph g = graph(start,limit,null); if (g.aborted) { out("reachability graph limit " + limit + " exceeded"); return; }
            int finish = -1; rev = adjacency(g.states.size()); boolean[] used = new boolean[T]; boolean proper = true; for (int u = 0; u < g.states.size(); ++u) { long[] m = g.states.get(u); if (Arrays.equals(m,goal)) finish = u; if (m[o] >= 1 && !Arrays.equals(m,goal)) proper = false; for (Edge e : g.edges.get(u)) { rev.get(e.target()).add(u); used[e.transition()] = true; } } boolean option = finish >= 0 && all(visit(rev,finish)), live = all(used); out("option to complete: " + yes(option)); out("proper completion: " + yes(proper)); out("no dead transitions: " + yes(live)); out("sound: " + yes(option && proper && live));
        }
        void execute(String[] w) {
            Map<String,Integer> arity = Map.ofEntries(Map.entry("MARKING",0),Map.entry("RESET",0),Map.entry("SET",2),Map.entry("ENABLED",0),Map.entry("FIRE",-1),Map.entry("UNDO",1),Map.entry("SIMULATE",3),Map.entry("CONFLICTS",0),Map.entry("REACH",1),Map.entry("GRAPH",1),Map.entry("COVER",1),Map.entry("PATH",2),Map.entry("INCIDENCE",0),Map.entry("PINV",0),Map.entry("TINV",0),Map.entry("SIPHONS",0),Map.entry("TRAPS",0),Map.entry("CLASSIFY",0),Map.entry("WORKFLOW",1),Map.entry("SHOW",0));
            String cmd = w[0]; if (!arity.containsKey(cmd)) bad("unknown command " + cmd); int expected = arity.get(cmd); if (expected < 0 ? w.length < 2 : w.length != expected+1) bad("wrong number of arguments"); int limit = 0; if (Set.of("REACH","GRAPH","COVER","PATH","WORKFLOW").contains(cmd)) { limit = (int)number(w[1],1,2000); if (limit < 0) bad("invalid limit " + w[1]); }
            switch (cmd) {
                case "MARKING", "RESET" -> { if (cmd.equals("RESET")) { current = initialMarking(); history.clear(); } out("marking " + mark(current)); }
                case "SET" -> { int p = p(w[1]); if (p < 0) bad("unknown place " + w[1]); long v = number(w[2],0,999); if (v < 0) bad("invalid tokens " + w[2]); if (capacities.get(p) > 0 && v > capacities.get(p)) bad("tokens exceed capacity of " + w[1]); current = current.clone(); current[p] = v; history.clear(); out("marking " + mark(current)); }
                case "ENABLED" -> out("enabled: " + listed(names(enabled(current))));
                case "FIRE" -> { List<Integer> ts = new ArrayList<>(); for (int i = 1; i < w.length; ++i) { int t = t(w[i]); if (t < 0) bad("unknown transition " + w[i]); ts.add(t); } for (int i = 0; i < ts.size(); ++i) { int t = ts.get(i); String reason = reason(current,t); if (!reason.isEmpty()) { out("step " + (i+1) + ": " + transitions.get(t) + " not enabled (" + reason + ") at " + mark(current)); return; } commit(t); } out("fired " + ts.size() + " -> " + mark(current)); }
                case "UNDO" -> { int k = (int)number(w[1],1,1000); if (k < 0) bad("invalid count " + w[1]); if (k > history.size()) bad("cannot undo " + k + ": history size " + history.size()); current = history.get(history.size()-k); history.subList(history.size()-k,history.size()).clear(); out("marking " + mark(current)); }
                case "SIMULATE" -> { int steps = (int)number(w[1],1,1000); long x = number(w[2],1,2147483646); if (steps < 0) bad("invalid steps " + w[1]); if (x < 0) bad("invalid seed " + w[2]); if (!Set.of("PRIORITY","RANDOM").contains(w[3])) bad("invalid mode " + w[3]); int[] counts = new int[transitions.size()]; int done = 0; for (; done < steps; ++done) { List<Integer> es = enabled(current); if (es.isEmpty()) { out("dead (steps=" + done + ")"); break; } int t = es.getFirst(); if (w[3].equals("RANDOM")) { x = x*48271%2147483647; t = es.get((int)(x%es.size())); } else for (int u : es) if (priorities.get(u) > priorities.get(t)) t = u; commit(t); ++counts[t]; out("step " + (done+1) + ": " + transitions.get(t) + " -> " + mark(current)); } if (done == steps) out("completed (steps=" + steps + ")"); List<String> a = new ArrayList<>(); for (int t = 0; t < counts.length; ++t) a.add(transitions.get(t) + "=" + counts[t]); out("counts: " + String.join(" ",a)); }
                case "CONFLICTS" -> { List<String> s = new ArrayList<>(), e = new ArrayList<>(); for (int u = 0; u < transitions.size(); ++u) for (int v = u+1; v < transitions.size(); ++v) { String pair = transitions.get(u) + "/" + transitions.get(v); boolean conflict = false; for (int p = 0; p < places.size(); ++p) if (pre[p][u] > 0 && pre[p][v] > 0) conflict = true; if (conflict) s.add(pair); if (reason(current,u).isEmpty() && reason(current,v).isEmpty() && (!reason(fire(current,u),v).isEmpty() || !reason(fire(current,v),u).isEmpty())) e.add(pair); } out("structural: " + listed(s)); out("effective: " + listed(e)); }
                case "REACH", "GRAPH" -> reach(limit,cmd.equals("GRAPH")); case "COVER" -> cover(limit);
                case "PATH" -> { String[] entries = w[2].split(",",-1); if (entries.length != places.size()) bad("target needs " + places.size() + " entries"); long[][] target = new long[entries.length][2]; for (int p = 0; p < entries.length; ++p) { String s = entries[p]; if (s.equals("*")) { target[p][1] = -1; continue; } boolean plus = s.endsWith("+"); long v = number(plus ? s.substring(0,s.length()-1) : s,0,9999999999L); if (v < 0) bad("invalid target entry " + s); target[p][0] = v; target[p][1] = plus ? -1 : v; } Graph g = graph(current,limit,target); if (g.found >= 0) { List<String> a = names(path(g,g.found)); out("reached " + mark(g.states.get(g.found)) + " length=" + a.size() + (a.isEmpty() ? "" : ": " + String.join(" ",a))); } else if (g.aborted) out("search limit " + limit + " exceeded"); else out("unreachable (markings explored: " + g.states.size() + ")"); }
                case "INCIDENCE" -> { List<List<String>> rows = new ArrayList<>(); List<String> header = new ArrayList<>(); header.add(""); header.addAll(transitions); rows.add(header); for (int p = 0; p < places.size(); ++p) { List<String> r = new ArrayList<>(); r.add(places.get(p)); for (int t = 0; t < transitions.size(); ++t) r.add(Long.toString(post[p][t]-pre[p][t])); rows.add(r); } int[] widths = new int[transitions.size()+1]; for (List<String> r : rows) for (int i = 0; i < r.size(); ++i) widths[i] = Math.max(widths[i],r.get(i).length()); for (List<String> r : rows) { List<String> a = new ArrayList<>(); for (int i = 0; i < r.size(); ++i) { String pad = " ".repeat(widths[i]-r.get(i).length()); a.add(i == 0 ? r.get(i)+pad : pad+r.get(i)); } out(String.join("  ",a).stripTrailing()); } }
                case "PINV", "TINV" -> invariants(cmd.equals("TINV"));
                case "SIPHONS", "TRAPS" -> { if (places.size() > 12) bad("more than 12 places"); List<Integer> ss = sets(cmd.equals("TRAPS")); out("minimal " + (cmd.equals("TRAPS") ? "traps" : "siphons") + ": " + ss.size()); for (int s : ss) { long tokens = 0; for (int p : bits(s)) tokens += current[p]; out("  " + setText(s) + " tokens=" + tokens); } }
                case "CLASSIFY" -> classify(); case "WORKFLOW" -> workflow(limit);
                case "SHOW" -> { for (int p = 0; p < places.size(); ++p) out("place " + places.get(p) + " tokens=" + initial.get(p) + " capacity=" + (capacities.get(p) == 0 ? "none" : capacities.get(p))); for (int t = 0; t < transitions.size(); ++t) { List<String> lists = new ArrayList<>(); for (long[][] matrix : List.of(pre,post,inhibitor)) { List<String> a = new ArrayList<>(); for (int p = 0; p < places.size(); ++p) if (matrix[p][t] > 0) a.add(places.get(p) + ":" + matrix[p][t]); lists.add(a.isEmpty() ? "-" : String.join(",",a)); } out("transition " + transitions.get(t) + " priority=" + priorities.get(t) + " pre=" + lists.get(0) + " post=" + lists.get(1) + " inhibit=" + lists.get(2)); } }
            }
        }
    }
    public static void main(String[] args) throws IOException {
        int blocks = Integer.parseInt(INPUT.readLine());
        for (int b = 0; b < blocks; ++b) { Net n = new Net(INPUT.readLine().split(" ")[1]); String line; while (!(line = INPUT.readLine()).equals("END NET")) { try { n.define(line.split(" ")); } catch (IllegalArgumentException e) { out("error: " + e.getMessage()); } } n.current = n.initialMarking(); out("net " + n.name + ": places=" + n.places.size() + " transitions=" + n.transitions.size() + " arcs=" + n.arcs + " inhibitors=" + n.inhibitors); int count = Integer.parseInt(INPUT.readLine()); for (int i = 0; i < count; ++i) { try { n.execute(INPUT.readLine().split(" ")); } catch (IllegalArgumentException e) { out("error: " + e.getMessage()); } } }
    }
}
