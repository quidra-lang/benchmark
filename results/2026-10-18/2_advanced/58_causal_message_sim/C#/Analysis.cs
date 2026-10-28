using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Analysis {
    public static List<List<int>> Graph(Program.Simulation sim) {
        List<List<int>> edges = new();
        foreach (Program.Event e in sim.events) {
            List<int> row = new();
            List<Program.Event> local = sim.processes[e.process].events;
            if (e.local < local.Count)
                row.Add(local[e.local].number - 1);
            edges.Add(row);
        }
        foreach (Program.Packet c in sim.copies)
            if (c.recv != null)
                edges[c.message.send.number - 1].Add(c.recv.number - 1);
        return edges;
    }
    public static List<int> Path(int source, int target, List<List<int>> edges) {
        int[] parent = new int[edges.Count];
        Array.Fill(parent, -1);
        parent[source] = source;
        Queue<int> queue = new();
        queue.Enqueue(source);
        while (queue.Count != 0 && parent[target] < 0) {
            int head = queue.Dequeue();
            foreach (int next in edges[head])
                if (parent[next] < 0) {
                    parent[next] = head;
                    queue.Enqueue(next);
                }
        }
        if (parent[target] < 0)
            return null;
        List<int> result = new();
        int current = target;
        while (true) {
            result.Add(current);
            if (current == source)
                break;
            current = parent[current];
        }
        result.Reverse();
        return result;
    }
    public sealed class Concurrency {
        public int ordered, concurrent, same, inversions;
        public int[][] pairs;
        public Concurrency(int size) {
            pairs = Enumerable.Range(0, size)
                        .Select(
                            _ => new int[size])
                        .ToArray();
        }
    }
    public static Concurrency ComputeConcurrency(Program.Simulation sim) {
        Concurrency result = new Concurrency(sim.names.Count);
        for (int i = 0; i < sim.events.Count; i++)
            for (int j = i + 1; j < sim.events.Count; j++) {
                Program.Event a = sim.events[i], b = sim.events[j];
                if (Clocks.Relation(a.vector, b.vector).Equals("||")) {
                    result.concurrent++;
                    if (a.lamport == b.lamport)
                        result.same++;
                    result.pairs[Math.Min(a.process, b.process)][Math.Max(a.process, b.process)]++;
                } else
                    result.ordered++;
                if ((a.time - b.time) * (a.lamport - b.lamport) < 0)
                    result.inversions++;
            }
        return result;
    }
    public record Relation(int process, Program.Packet first, Program.Packet second) {
    }
    public static List<Relation> Relations(Program.Simulation sim, bool races) {
        List<Relation> result = new();
        foreach (Processes.State p in sim.processes)
            for (int i = 0; i < p.delivered.Count; i++) {
                Program.Packet a = p.delivered[i];
                int end = races ? Math.Min(i + 2, p.delivered.Count) : p.delivered.Count;
                for (int j = i + 1; j < end; j++) {
                    Program.Packet b = p.delivered[j];
                    if (races ? Clocks.Relation(a.message.send.vector, b.message.send.vector).Equals("||")
                              : Clocks.Before(b.message.send.vector, a.message.send.vector))
                        result.Add(new Relation(p.index, a, b));
                }
            }
        return result;
    }
    public static bool Consistent(int[] cut, List<Processes.State> processes) {
        for (int i = 0; i < cut.Length; i++)
            if (cut[i] > 0 && !Clocks.LessEqual(processes[i].events[cut[i] - 1].vector, cut))
                return false;
        return true;
    }
    public record Predicate(int cuts, bool definitely) {
    }
    public sealed class Enumeration {
        public int[] limits, levels;
        public int product, consistent;
        public List<Predicate> predicates = new();
    }
    public static Enumeration Enumerate(Program.Simulation sim, int time, List<int> thresholds) {
        int n = sim.names.Count;
        Enumeration result = new Enumeration();
        result.limits = new int[n];
        int[] stride = new int[n];
        int product = 1, total = 0;
        for (int i = 0; i < n; i++) {
            foreach (Program.Event e in sim.processes[i].events)
                if (e.time <= time)
                    result.limits[i]++;
            stride[i] = product;
            product *= result.limits[i] + 1;
            total += result.limits[i];
        }
        result.product = product;
        result.levels = new int[total + 1];
        bool[] good = new bool[product];
        int[] amount = new int[product];
        for (int id = 0; id < product; id++) {
            int[] cut = new int[n];
            int level = 0, balance = 0;
            for (int i = 0; i < n; i++) {
                cut[i] = id / stride[i] % (result.limits[i] + 1);
                level += cut[i];
                balance += sim.processes[i].BalanceAt(cut[i]);
            }
            good[id] = Consistent(cut, sim.processes);
            amount[id] = sim.Initial() - balance;
            if (good[id]) {
                result.consistent++;
                result.levels[level]++;
            }
        }
        foreach (int threshold in thresholds) {
            int count = 0;
            bool[] reachable = new bool[product];
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
            result.predicates.Add(new Predicate(count, !reachable[product - 1]));
        }
        return result;
    }
}
