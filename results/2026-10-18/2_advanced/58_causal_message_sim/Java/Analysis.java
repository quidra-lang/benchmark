import java.util.*;

final class Analysis {
    static List<List<Integer>> graph(Main.Simulation sim) {
        List<List<Integer>> edges = new ArrayList<>();
        for (Main.Event e : sim.events) {
            List<Integer> row = new ArrayList<>();
            List<Main.Event> local = sim.processes.get(e.process).events;
            if (e.local < local.size())
                row.add(local.get(e.local).number - 1);
            edges.add(row);
        }
        for (Main.Packet c : sim.copies)
            if (c.recv != null)
                edges.get(c.message.send.number - 1).add(c.recv.number - 1);
        return edges;
    }
    static List<Integer> path(int source, int target, List<List<Integer>> edges) {
        int[] parent = new int[edges.size()];
        Arrays.fill(parent, -1);
        parent[source] = source;
        Deque<Integer> queue = new ArrayDeque<>();
        queue.add(source);
        while (!queue.isEmpty() && parent[target] < 0) {
            int current = queue.removeFirst();
            for (int next : edges.get(current))
                if (parent[next] < 0) {
                    parent[next] = current;
                    queue.add(next);
                }
        }
        if (parent[target] < 0)
            return null;
        List<Integer> result = new ArrayList<>();
        int current = target;
        while (true) {
            result.add(current);
            if (current == source)
                break;
            current = parent[current];
        }
        Collections.reverse(result);
        return result;
    }
    static final class Concurrency {
        int ordered, concurrent, same, inversions;
        int[][] pairs;
        Concurrency(int size) {
            pairs = new int[size][size];
        }
    }
    static Concurrency concurrency(Main.Simulation sim) {
        Concurrency result = new Concurrency(sim.names.size());
        for (int i = 0; i < sim.events.size(); i++)
            for (int j = i + 1; j < sim.events.size(); j++) {
                Main.Event a = sim.events.get(i), b = sim.events.get(j);
                if (Clocks.relation(a.vector, b.vector).equals("||")) {
                    result.concurrent++;
                    if (a.lamport == b.lamport)
                        result.same++;
                    result.pairs[Math.min(a.process, b.process)][Math.max(a.process, b.process)]++;
                } else
                    result.ordered++;
                if ((a.time - b.time) * (a.lamport - b.lamport) < 0)
                    result.inversions++;
            }
        return result;
    }
    record Relation(int process, Main.Packet first, Main.Packet second) {}
    static List<Relation> relations(Main.Simulation sim, boolean races) {
        List<Relation> result = new ArrayList<>();
        for (Processes.State p : sim.processes)
            for (int i = 0; i < p.delivered.size(); i++) {
                Main.Packet a = p.delivered.get(i);
                int end = races ? Math.min(i + 2, p.delivered.size()) : p.delivered.size();
                for (int j = i + 1; j < end; j++) {
                    Main.Packet b = p.delivered.get(j);
                    if (races ? Clocks.relation(a.message.send.vector, b.message.send.vector).equals("||")
                              : Clocks.before(b.message.send.vector, a.message.send.vector))
                        result.add(new Relation(p.index, a, b));
                }
            }
        return result;
    }
    static boolean consistent(int[] cut, List<Processes.State> processes) {
        for (int i = 0; i < cut.length; i++)
            if (cut[i] > 0 && !Clocks.lessEqual(processes.get(i).events.get(cut[i] - 1).vector, cut))
                return false;
        return true;
    }
    record Predicate(int cuts, boolean definitely) {}
    static final class Enumeration {
        int[] limits, levels;
        int product, consistent;
        List<Predicate> predicates = new ArrayList<>();
    }
    static Enumeration enumerate(Main.Simulation sim, int time, List<Integer> thresholds) {
        int n = sim.names.size();
        Enumeration result = new Enumeration();
        result.limits = new int[n];
        int[] stride = new int[n];
        int product = 1, total = 0;
        for (int i = 0; i < n; i++) {
            for (Main.Event e : sim.processes.get(i).events)
                if (e.time <= time)
                    result.limits[i]++;
            stride[i] = product;
            product *= result.limits[i] + 1;
            total += result.limits[i];
        }
        result.product = product;
        result.levels = new int[total + 1];
        boolean[] good = new boolean[product];
        int[] amount = new int[product];
        for (int id = 0; id < product; id++) {
            int[] cut = new int[n];
            int level = 0, balance = 0;
            for (int i = 0; i < n; i++) {
                cut[i] = id / stride[i] % (result.limits[i] + 1);
                level += cut[i];
                balance += sim.processes.get(i).balanceAt(cut[i]);
            }
            good[id] = consistent(cut, sim.processes);
            amount[id] = sim.initial() - balance;
            if (good[id]) {
                result.consistent++;
                result.levels[level]++;
            }
        }
        for (int threshold : thresholds) {
            int count = 0;
            boolean[] reachable = new boolean[product];
            for (int id = 0; id < product; id++)
                if (good[id]) {
                    if (amount[id] >= threshold) {
                        count++;
                        continue;
                    }
                    if (id == 0)
                        reachable[id] = true;
                    else
                        for (int i = 0; i < n; i++)
                            if (id / stride[i] % (result.limits[i] + 1) > 0 && reachable[id - stride[i]]) {
                                reachable[id] = true;
                                break;
                            }
                }
            result.predicates.add(new Predicate(count, !reachable[product - 1]));
        }
        return result;
    }
}
