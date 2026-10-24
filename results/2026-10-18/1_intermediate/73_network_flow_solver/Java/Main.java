import java.io.*;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super("ERROR " + message);
        }
    }

    static void fail(String message) {
        throw new Problem(message);
    }

    static class Edge {
        int u, v, capacity, cost, lower, flow;
        Edge(int u, int v, int capacity, int cost) {
            this.u = u;
            this.v = v;
            this.capacity = capacity;
            this.cost = cost;
        }
        Edge copy() {
            Edge e = new Edge(u, v, capacity, cost);
            e.lower = lower;
            e.flow = flow;
            return e;
        }
    }

    static class Graph {
        List<String> names = new ArrayList<>();
        List<Edge> edges = new ArrayList<>();
        Graph copy(boolean keepFlow) {
            Graph g = new Graph();
            g.names.addAll(names);
            for (Edge e : edges) {
                Edge f = e.copy();
                if (!keepFlow) f.flow = 0;
                g.edges.add(f);
            }
            return g;
        }
        int add(int u, int v, int capacity, int cost) {
            edges.add(new Edge(u, v, capacity, cost));
            return edges.size();
        }
        Edge edge(int arc) {
            return edges.get(Math.abs(arc) - 1);
        }
        int from(int arc) {
            Edge e = edge(arc);
            return arc > 0 ? e.u : e.v;
        }
        int to(int arc) {
            Edge e = edge(arc);
            return arc > 0 ? e.v : e.u;
        }
        int residual(int arc) {
            Edge e = edge(arc);
            return arc > 0 ? e.capacity - e.flow : e.flow;
        }
        int cost(int arc) {
            return arc > 0 ? edge(arc).cost : -edge(arc).cost;
        }
        List<Integer> arcs(int u) {
            List<Integer> result = new ArrayList<>();
            for (int i = 0; i < edges.size(); i++) if (edges.get(i).u == u) result.add(i + 1);
            for (int i = 0; i < edges.size(); i++) if (edges.get(i).v == u) result.add(-i - 1);
            return result;
        }
        int[] balances() {
            int[] b = new int[names.size()];
            for (Edge e : edges) {
                b[e.u] += e.flow;
                b[e.v] -= e.flow;
            }
            return b;
        }
        int totalCost() {
            int result = 0;
            for (Edge e : edges) result += e.flow * e.cost;
            return result;
        }
        int bottleneck(List<Integer> path) {
            int result = Integer.MAX_VALUE;
            for (int a : path) result = Math.min(result, residual(a));
            return result;
        }
        void push(List<Integer> path, int amount) {
            for (int a : path) edge(a).flow += a > 0 ? amount : -amount;
        }
        String notation(int start, List<Integer> path) {
            StringBuilder text = new StringBuilder(names.get(start));
            for (int a : path) text.append(' ').append(a > 0 ? "+" : "-").append(Math.abs(a)).append(' ').append(names.get(to(a)));
            return text.toString();
        }
        Search bfs(int source, int threshold) {
            Search search = new Search(names.size());
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            search.level[source] = 0;
            queue.add(source);
            while (!queue.isEmpty()) {
                int u = queue.remove();
                for (int a : arcs(u)) {
                    int v = to(a);
                    if (residual(a) >= threshold && search.level[v] < 0) {
                        search.level[v] = search.level[u] + 1;
                        search.parent[v] = a;
                        queue.add(v);
                    }
                }
            }
            return search;
        }
        List<Integer> path(int source, int target, int[] parent) {
            List<Integer> result = new ArrayList<>();
            for (int v = target; v != source; v = from(parent[v])) result.add(parent[v]);
            Collections.reverse(result);
            return result;
        }
        List<Augmentation> maximum(int source, int target, String method) {
            List<Augmentation> result = new ArrayList<>();
            if (method.equals("DINIC")) {
                int phase = 0;
                while (true) {
                    Search search = bfs(source, 1);
                    if (search.level[target] < 0) break;
                    phase++;
                    List<List<Integer>> lists = new ArrayList<>();
                    for (int u = 0; u < names.size(); u++) lists.add(arcs(u));
                    int[] pointer = new int[names.size()];
                    List<Integer> path = new ArrayList<>();
                    int u = source;
                    while (true) {
                        if (u == target) {
                            int amount = bottleneck(path);
                            result.add(new Augmentation(new ArrayList<>(path), amount, phase, 0));
                            push(path, amount);
                            path.clear();
                            u = source;
                        } else if (pointer[u] == lists.get(u).size()) {
                            if (u == source) break;
                            u = from(path.removeLast());
                            pointer[u]++;
                        } else {
                            int a = lists.get(u).get(pointer[u]);
                            int v = to(a);
                            if (residual(a) > 0 && search.level[v] == search.level[u] + 1) {
                                path.add(a);
                                u = v;
                            } else pointer[u]++;
                        }
                    }
                }
                return result;
            }
            int threshold = 1;
            if (method.equals("SCALING")) {
                int largest = 0;
                for (Edge e : edges) largest = Math.max(largest, e.capacity);
                while (threshold <= largest / 2) threshold *= 2;
            }
            do {
                while (true) {
                    Search search = bfs(source, threshold);
                    if (search.level[target] < 0) break;
                    List<Integer> path = path(source, target, search.parent);
                    int amount = bottleneck(path);
                    push(path, amount);
                    result.add(new Augmentation(path, amount, threshold, 0));
                    if (method.equals("AUGMENT")) return result;
                }
                threshold /= 2;
            }
            while (threshold > 0);
            return result;
        }
        boolean negativeCycle(boolean subtractLower) {
            int[] distance = new int[names.size()];
            for (int pass = 0; pass < names.size(); pass++) {
                boolean changed = false;
                for (Edge e : edges) if (e.capacity - (subtractLower ? e.lower : 0) > 0 && distance[e.v] > distance[e.u] + e.cost) {
                    distance[e.v] = distance[e.u] + e.cost;
                    changed = true;
                }
                if (!changed) return false;
            }
            return !names.isEmpty();
        }
        List<Augmentation> cheapest(int source, int target, int wanted) {
            List<Augmentation> result = new ArrayList<>();
            int pushed = 0;
            while (wanted < 0 || pushed < wanted) {
                // Keep the specified global arc order fixed during each shortest-path search.
                List<Integer> usable = new ArrayList<>();
                for (int i = 1; i <= edges.size(); i++) if (residual(i) > 0) usable.add(i);
                for (int i = 1; i <= edges.size(); i++) if (residual(-i) > 0) usable.add(-i);
                Integer[] distance = new Integer[names.size()];
                int[] parent = new int[names.size()];
                distance[source] = 0;
                boolean changed;
                do {
                    changed = false;
                    for (int a : usable) {
                        int u = from(a), v = to(a);
                        if (distance[u] != null && (distance[v] == null || distance[u] + cost(a) < distance[v])) {
                            distance[v] = distance[u] + cost(a);
                            parent[v] = a;
                            changed = true;
                        }
                    }
                }
                while (changed);
                if (distance[target] == null) break;
                List<Integer> path = path(source, target, parent);
                int amount = bottleneck(path);
                if (wanted >= 0) amount = Math.min(amount, wanted - pushed);
                push(path, amount);
                pushed += amount;
                result.add(new Augmentation(path, amount, 0, distance[target]));
            }
            return result;
        }
        List<Piece> decompose() {
            int[] remaining = edges.stream().mapToInt(e -> e.flow).toArray();
            int[] balance = balances();
            List<Piece> result = new ArrayList<>();
            while (Arrays.stream(remaining).anyMatch(x -> x > 0)) {
                int start = -1;
                for (int u = 0; u < names.size(); u++) if (balance[u] > 0) {
                    start = u;
                    break;
                }
                if (start < 0) for (int i = 0; i < edges.size(); i++) if (remaining[i] > 0) {
                    start = edges.get(i).u;
                    break;
                }
                List<Integer> vertices = new ArrayList<>(List.of(start)), path = new ArrayList<>();
                while (true) {
                    int u = vertices.getLast(), i = 0;
                    while (edges.get(i).u != u || remaining[i] == 0) i++;
                    int v = edges.get(i).v;
                    path.add(i + 1);
                    int repeated = vertices.indexOf(v);
                    if (repeated >= 0) {
                        List<Integer> cycle = new ArrayList<>(path.subList(repeated, path.size()));
                        int amount = cycle.stream().mapToInt(a -> remaining[a - 1]).min().orElseThrow();
                        for (int a : cycle) remaining[a - 1] -= amount;
                        result.add(new Piece(true, v, cycle, amount));
                        break;
                    }
                    vertices.add(v);
                    if (balance[v] < 0) {
                        int amount = Math.min(balance[start], -balance[v]);
                        for (int a : path) amount = Math.min(amount, remaining[a - 1]);
                        for (int a : path) remaining[a - 1] -= amount;
                        balance[start] -= amount;
                        balance[v] += amount;
                        result.add(new Piece(false, start, path, amount));
                        break;
                    }
                }
            }
            return result;
        }
    }

    static class Search {
        int[] level, parent;
        Search(int n) {
            level = new int[n];
            Arrays.fill(level, -1);
            parent = new int[n];
        }
    }

    record Augmentation(List<Integer> path, int amount, int stage, int unitCost) { }

    record Piece(boolean cycle, int start, List<Integer> path, int amount) { }

    Graph network = new Graph();
    List<Integer> demand = new ArrayList<>();
    int owner, source, target;

    int node(String name) {
        int index = network.names.indexOf(name);
        if (index < 0) fail("UNKNOWN NODE " + name);
        return index;
    }

    Edge checkedEdge(String text) {
        int number = Integer.parseInt(text);
        if (number < 1 || number > network.edges.size()) fail("UNKNOWN EDGE " + text);
        return network.edges.get(number - 1);
    }

    int[] endpoints(String s, String t) {
        int u = node(s), v = node(t);
        if (u == v) fail("SAME NODE");
        return new int[]{u, v};
    }

    int start(int s, int t) {
        if (owner != 1 || source != s || target != t) for (Edge e : network.edges) e.flow = 0;
        owner = 1;
        source = s;
        target = t;
        return network.balances()[s];
    }

    List<String> flows() {
        List<String> out = new ArrayList<>();
        for (int i = 0; i < network.edges.size(); i++) {
            Edge e = network.edges.get(i);
            out.add("FLOW " + (i + 1) + " " + network.names.get(e.u) + " " + network.names.get(e.v) + " " + e.flow + "/" + e.capacity);
        }
        return out;
    }

    void copyFlows(Graph g, boolean lower) {
        for (int i = 0; i < network.edges.size(); i++) network.edges.get(i).flow = g.edges.get(i).flow + (lower ? network.edges.get(i).lower : 0);
    }

    static String join(List<String> names) {
        return names.isEmpty() ? "-" : String.join(",", names);
    }

    List<String> command(String line) {
        String[] w = line.split(" ");
        String c = w[0];
        List<String> out = new ArrayList<>();
        switch (c) {
            case "NODE" -> {
                Set<String> seen = new HashSet<>(network.names);
                for (int i = 1; i < w.length; i++) if (!seen.add(w[i])) fail("DUPLICATE NODE " + w[i]);
                if (network.names.size() + w.length - 1 > 20) fail("TOO MANY NODES");
                for (int i = 1; i < w.length; i++) {
                    network.names.add(w[i]);
                    demand.add(0);
                }
                out.add("NODE added=" + (w.length - 1) + " total=" + network.names.size());
            }
            case "EDGE" -> {
                int u = node(w[1]), v = node(w[2]);
                if (u == v) fail("SELF LOOP");
                if (network.edges.size() == 60) fail("TOO MANY EDGES");
                int cap = Integer.parseInt(w[3]), cost = w.length == 5 ? Integer.parseInt(w[4]) : 0;
                int number = network.add(u, v, cap, cost);
                out.add("EDGE " + number + " " + w[1] + " " + w[2] + " cap=" + cap + " cost=" + cost);
            }
            case "LOWER", "CAP", "COST" -> {
                Edge e = checkedEdge(w[1]);
                int value = Integer.parseInt(w[2]);
                if (c.equals("LOWER")) {
                    if (value > e.capacity) fail("BAD BOUND");
                    e.lower = value;
                    out.add("LOWER " + w[1] + " low=" + value + " cap=" + e.capacity);
                } else if (c.equals("CAP")) {
                    if (value < e.lower) fail("BAD BOUND");
                    if (value < e.flow) fail("BELOW FLOW");
                    e.capacity = value;
                    out.add("CAP " + w[1] + " low=" + e.lower + " cap=" + value);
                } else {
                    e.cost = value;
                    out.add("COST " + w[1] + " cost=" + value);
                }
            }
            case "DEMAND" -> {
                int u = node(w[1]), value = Integer.parseInt(w[2]);
                demand.set(u, value);
                out.add("DEMAND " + w[1] + " " + value + " total=" + demand.stream().mapToInt(Integer::intValue).sum());
            }
            case "RESET" -> {
                int count = 0;
                for (Edge e : network.edges) {
                    if (e.flow != 0) count++;
                    e.flow = 0;
                }
                owner = 0;
                out.add("RESET edges=" + count);
            }
            case "CLEAR" -> {
                out.add("CLEAR nodes=" + network.names.size() + " edges=" + network.edges.size());
                network = new Graph();
                demand.clear();
                owner = 0;
            }
            case "SHOW" -> {
                out.add("NETWORK nodes=" + network.names.size() + " edges=" + network.edges.size());
                out.add(owner == 0 ? "STATE none" : owner == 2 ? "STATE circulation cost=" + network.totalCost() : "STATE flow " + network.names.get(source) + " " + network.names.get(target) + " value=" + network.balances()[source] + " cost=" + network.totalCost());
                for (int u = 0; u < network.names.size(); u++) {
                    int sent = 0, received = 0;
                    for (Edge e : network.edges) {
                        if (e.u == u) sent += e.flow;
                        if (e.v == u) received += e.flow;
                    }
                    out.add("NODE " + network.names.get(u) + " demand=" + demand.get(u) + " out=" + sent + " in=" + received);
                }
                for (int i = 0; i < network.edges.size(); i++) {
                    Edge e = network.edges.get(i);
                    out.add("EDGE " + (i + 1) + " " + network.names.get(e.u) + " " + network.names.get(e.v) + " cap=" + e.capacity + " cost=" + e.cost + " low=" + e.lower + " flow=" + e.flow);
                }
            }
            case "AUGMENT", "MAXFLOW", "DINIC", "SCALING", "MINCUT" -> {
                int[] ends = endpoints(w[1], w[2]);
                int s = ends[0], t = ends[1], initial = start(s, t);
                List<Augmentation> paths = network.maximum(s, t, c);
                int value = network.balances()[s];
                String heading = c + " " + w[1] + " " + w[2] + " value=" + value;
                if (c.equals("AUGMENT")) {
                    out.add(heading + (paths.isEmpty() ? " none" : " amount=" + paths.getFirst().amount + " " + network.notation(s, paths.getFirst().path)));
                } else if (c.equals("MINCUT")) {
                    Search search = network.bfs(s, 1);
                    List<Integer> cut = new ArrayList<>();
                    for (int i = 0; i < network.edges.size(); i++) {
                        Edge e = network.edges.get(i);
                        if (search.level[e.u] >= 0 && search.level[e.v] < 0) cut.add(i);
                    }
                    out.add(heading + " edges=" + cut.size());
                    for (boolean reachable : new boolean[]{true, false}) {
                        StringBuilder row = new StringBuilder(reachable ? "SOURCE" : "SINK");
                        for (int u = 0; u < network.names.size(); u++) if ((search.level[u] >= 0) == reachable) row.append(' ').append(network.names.get(u));
                        out.add(row.toString());
                    }
                    for (int i : cut) {
                        Edge e = network.edges.get(i);
                        out.add("CUT " + (i + 1) + " " + network.names.get(e.u) + " " + network.names.get(e.v) + " " + e.capacity);
                    }
                } else {
                    int phases = paths.isEmpty() ? 0 : paths.getLast().stage;
                    out.add(heading + " start=" + initial + (c.equals("DINIC") ? " phases=" + phases : "") + " paths=" + paths.size());
                    for (int i = 0; i < paths.size(); i++) {
                        Augmentation a = paths.get(i);
                        out.add("AUG " + (i + 1) + (c.equals("DINIC") ? " phase=" + a.stage : c.equals("SCALING") ? " delta=" + a.stage : "") + " amount=" + a.amount + " " + network.notation(s, a.path));
                    }
                    out.addAll(flows());
                }
            }
            case "SENSITIVITY" -> {
                int[] ends = endpoints(w[1], w[2]);
                Graph base = network.copy(false);
                base.maximum(ends[0], ends[1], "MAXFLOW");
                int value = base.balances()[ends[0]], upCount = 0, downCount = 0;
                List<String> critical = new ArrayList<>();
                for (int i = 0; i < network.edges.size(); i++) {
                    Graph g = network.copy(false);
                    g.edges.get(i).capacity++;
                    g.maximum(ends[0], ends[1], "MAXFLOW");
                    boolean up = g.balances()[ends[0]] > value, down = false;
                    if (network.edges.get(i).capacity > 0) {
                        g = network.copy(false);
                        g.edges.get(i).capacity--;
                        g.maximum(ends[0], ends[1], "MAXFLOW");
                        down = g.balances()[ends[0]] < value;
                    }
                    if (up) upCount++;
                    if (down) downCount++;
                    Edge e = network.edges.get(i);
                    if (up || down) critical.add("CRITICAL " + (i + 1) + " " + network.names.get(e.u) + " " + network.names.get(e.v) + " up=" + (up ? "yes" : "no") + " down=" + (down ? "yes" : "no"));
                }
                out.add("SENSITIVITY " + w[1] + " " + w[2] + " value=" + value + " up=" + upCount + " down=" + downCount);
                out.addAll(critical);
            }
            case "MINCOST" -> {
                int[] ends = endpoints(w[1], w[2]);
                if (network.negativeCycle(false)) fail("NEGATIVE CYCLE");
                int wanted = w[3].equals("MAX") ? -1 : Integer.parseInt(w[3]);
                Graph g = network.copy(false);
                List<Augmentation> paths = g.cheapest(ends[0], ends[1], wanted);
                int amount = g.balances()[ends[0]];
                String heading = "MINCOST " + w[1] + " " + w[2] + " k=" + w[3];
                if (wanted >= 0 && amount < wanted) out.add(heading + " infeasible max=" + amount);
                else {
                    copyFlows(g, false);
                    owner = 1;
                    source = ends[0];
                    target = ends[1];
                    out.add(heading + " flow=" + amount + " cost=" + g.totalCost());
                    for (int i = 0; i < paths.size(); i++) {
                        Augmentation a = paths.get(i);
                        out.add("AUG " + (i + 1) + " amount=" + a.amount + " cost=" + a.unitCost + " " + g.notation(source, a.path));
                    }
                    out.addAll(flows());
                }
            }
            case "DISJOINT" -> {
                int[] ends = endpoints(w[1], w[2]);
                int n = network.names.size(), s = ends[0], t = ends[1];
                Graph g = new Graph();
                g.names.addAll(network.names);
                int[] exit = new int[n];
                for (int u = 0; u < n; u++) {
                    exit[u] = u;
                    if (w[3].equals("VERTEX") && u != s && u != t) {
                        exit[u] = g.names.size();
                        g.names.add(network.names.get(u));
                    }
                }
                for (Edge e : network.edges) g.add(exit[e.u], e.v, e.capacity == 0 ? 0 : 1, 0);
                for (int u = 0; u < n; u++) if (exit[u] != u) g.add(u, exit[u], 1, 0);
                g.maximum(s, t, "MAXFLOW");
                List<Piece> pieces = g.decompose().stream().filter(p -> !p.cycle).toList();
                out.add("DISJOINT " + w[1] + " " + w[2] + " " + w[3] + " count=" + pieces.size());
                for (int i = 0; i < pieces.size(); i++) {
                    StringBuilder row = new StringBuilder("PATH " + (i + 1) + " " + w[1]);
                    for (int a : pieces.get(i).path) if (a <= network.edges.size()) row.append(" +").append(a).append(' ').append(network.names.get(network.edges.get(a - 1).v));
                    out.add(row.toString());
                }
            }
            case "DECOMPOSE" -> {
                List<Piece> pieces = network.decompose();
                int cycles = (int) pieces.stream().filter(Piece::cycle).count(), paths = 0, count = 0;
                out.add("DECOMPOSE paths=" + (pieces.size() - cycles) + " cycles=" + cycles);
                for (Piece p : pieces) out.add((p.cycle ? "CYCLE " + (++count) : "PATH " + (++paths)) + " amount=" + p.amount + " " + network.notation(p.start, p.path));
            }
            case "VERIFY" -> {
                List<String> violations = new ArrayList<>();
                for (int i = 0; i < network.edges.size(); i++) {
                    Edge e = network.edges.get(i);
                    if (e.flow < e.lower) violations.add("LOW " + (i + 1) + " flow=" + e.flow + " low=" + e.lower);
                }
                int[] balance = network.balances();
                for (int u = 0; u < network.names.size(); u++) if (owner != 1 || (u != source && u != target)) {
                    int need = owner == 1 ? 0 : demand.get(u);
                    if (-balance[u] != need) violations.add("BALANCE " + network.names.get(u) + " net=" + (-balance[u]) + " need=" + need);
                }
                out.add(violations.isEmpty() ? "VERIFY ok" : "VERIFY violations=" + violations.size());
                out.addAll(violations);
            }
            case "CIRCULATION" -> {
                boolean cheapest = w[1].equals("MINCOST");
                if (cheapest && network.negativeCycle(true)) fail("NEGATIVE CYCLE");
                int sum = demand.stream().mapToInt(Integer::intValue).sum();
                if (sum != 0) {
                    out.add("CIRCULATION infeasible unbalanced=" + sum);
                    break;
                }
                Graph g = network.copy(false);
                int n = g.names.size(), required = 0;
                g.names.add("source");
                g.names.add("sink");
                int[] remaining = demand.stream().mapToInt(Integer::intValue).toArray();
                for (Edge e : g.edges) {
                    remaining[e.u] += e.lower;
                    remaining[e.v] -= e.lower;
                    e.capacity -= e.lower;
                }
                for (int u = 0; u < n; u++) if (remaining[u] < 0) g.add(n, u, -remaining[u], 0);
                for (int u = 0; u < n; u++) if (remaining[u] > 0) {
                    g.add(u, n + 1, remaining[u], 0);
                    required += remaining[u];
                }
                if (cheapest) g.cheapest(n, n + 1, -1);
                else g.maximum(n, n + 1, "MAXFLOW");
                int achieved = -g.balances()[n + 1];
                if (achieved < required) {
                    out.add("CIRCULATION infeasible required=" + required + " achieved=" + achieved);
                    Search search = g.bfs(n, 1);
                    StringBuilder row = new StringBuilder("CUT");
                    for (int u = 0; u < n; u++) if (search.level[u] >= 0) row.append(' ').append(network.names.get(u));
                    out.add(row.toString());
                } else {
                    copyFlows(g, true);
                    owner = 2;
                    out.add("CIRCULATION feasible required=" + required + " cost=" + network.totalCost());
                    out.addAll(flows());
                }
            }
            case "MATCH" -> out.addAll(matching(w));
            case "ASSIGN" -> out.addAll(assignment(w));
            default -> throw new IllegalStateException();
        }
        return out;
    }

    static List<String> matching(String[] w) {
        List<String> left = Arrays.asList(w[1].split(",")), right = Arrays.asList(w[2].split(","));
        Set<String> seen = new HashSet<>();
        for (String s : left) if (!seen.add(s)) fail("DUPLICATE VERTEX " + s);
        for (String s : right) if (!seen.add(s)) fail("DUPLICATE VERTEX " + s);
        List<int[]> pairs = new ArrayList<>();
        Set<String> pairSeen = new HashSet<>();
        if (!w[3].equals("-")) for (String pair : w[3].split(",")) {
            String[] p = pair.split("-");
            int u = left.indexOf(p[0]), v = right.indexOf(p[1]);
            if (u < 0) fail("UNKNOWN VERTEX " + p[0]);
            if (v < 0) fail("UNKNOWN VERTEX " + p[1]);
            if (!pairSeen.add(pair)) fail("DUPLICATE PAIR " + pair);
            pairs.add(new int[]{u, v});
        }
        int[] a = new int[left.size()], b = new int[right.size()];
        Arrays.fill(a, -1);
        Arrays.fill(b, -1);
        class Kuhn {
            boolean visit(int u, boolean[] examined) {
                for (int[] p : pairs) if (p[0] == u && !examined[p[1]]) {
                    int v = p[1];
                    examined[v] = true;
                    if (b[v] < 0 || visit(b[v], examined)) {
                        b[v] = u;
                        a[u] = v;
                        return true;
                    }
                }
                return false;
            }
        }
        Kuhn solver = new Kuhn();
        for (int u = 0; u < a.length; u++) solver.visit(u, new boolean[b.length]);
        boolean[] za = new boolean[a.length], zb = new boolean[b.length];
        ArrayDeque<Integer> queue = new ArrayDeque<>();
        List<String> freeA = new ArrayList<>(), freeB = new ArrayList<>(), cover = new ArrayList<>(), hallA = new ArrayList<>(), hallB = new ArrayList<>();
        for (int u = 0; u < a.length; u++) if (a[u] < 0) {
            za[u] = true;
            queue.add(u);
            freeA.add(left.get(u));
        }
        while (!queue.isEmpty()) {
            int u = queue.remove();
            for (int[] p : pairs) if (p[0] == u && a[u] != p[1] && !zb[p[1]]) {
                int v = p[1];
                zb[v] = true;
                if (b[v] >= 0 && !za[b[v]]) {
                    za[b[v]] = true;
                    queue.add(b[v]);
                }
            }
        }
        List<String> out = new ArrayList<>();
        out.add("MATCH size=" + (a.length - freeA.size()) + " left=" + a.length + " right=" + b.length);
        for (int u = 0; u < a.length; u++) {
            if (a[u] >= 0) out.add("PAIR " + left.get(u) + " " + right.get(a[u]));
            if (za[u]) hallA.add(left.get(u));
            else cover.add(left.get(u));
        }
        for (int v = 0; v < b.length; v++) {
            if (b[v] < 0) freeB.add(right.get(v));
            if (zb[v]) {
                cover.add(right.get(v));
                hallB.add(right.get(v));
            }
        }
        out.add("FREE " + join(freeA) + " " + join(freeB));
        out.add("COVER size=" + cover.size() + (cover.isEmpty() ? "" : " " + String.join(" ", cover)));
        if (!freeA.isEmpty()) out.add("HALL " + join(hallA) + " " + join(hallB));
        return out;
    }

    static List<String> assignment(String[] w) {
        int n = Integer.parseInt(w[2]);
        if (n < 1 || n > 8) fail("BAD SIZE");
        if (w.length - 3 != n * n) fail("BAD LENGTH");
        Integer[][] values = new Integer[n][n];
        for (int i = 0; i < n * n; i++) if (!w[i + 3].equals("x")) values[i / n][i % n] = Integer.parseInt(w[i + 3]);
        class Enumeration {
            int best, count;
            int[] chosen, current = new int[n];
            void visit(int row, int used, int sum) {
                if (row == n) {
                    if (count == 0 || (w[1].equals("MIN") ? sum < best : sum > best)) {
                        best = sum;
                        count = 1;
                        chosen = current.clone();
                    } else if (sum == best) count++;
                    return;
                }
                for (int col = 0; col < n; col++) if ((used & (1 << col)) == 0 && values[row][col] != null) {
                    current[row] = col;
                    visit(row + 1, used | (1 << col), sum + values[row][col]);
                }
            }
        }
        Enumeration solver = new Enumeration();
        solver.visit(0, 0, 0);
        List<String> out = new ArrayList<>();
        String heading = "ASSIGN " + w[1] + " n=" + n;
        if (solver.count == 0) out.add(heading + " infeasible");
        else {
            out.add(heading + " total=" + solver.best + " optimal=" + solver.count);
            for (int row = 0; row < n; row++) out.add("MATE " + (row + 1) + " " + (solver.chosen[row] + 1) + " " + values[row][solver.chosen[row]]);
        }
        return out;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main solver = new Main();
        int n = Integer.parseInt(reader.readLine());
        for (int i = 0; i < n; i++) {
            try {
                for (String line : solver.command(reader.readLine())) System.out.println(line);
            } catch (Problem e) {
                System.out.println(e.getMessage());
            }
        }
    }
}
