using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dpll {
    public sealed class Stats {
        public int decisions, propagations, conflicts, maxDepth;
        public void Add(Stats other) {
            decisions += other.decisions;
            propagations += other.propagations;
            conflicts += other.conflicts;
            maxDepth = Math.Max(maxDepth, other.maxDepth);
        }
    }
    public sealed record Entry(int literal, int kind);
    public sealed record Result(bool[] model, List<string> trace, Stats stats);
    public sealed class State {
        Entry Pop() {
            Entry entry = trail[^1];
            trail.RemoveAt(trail.Count - 1);
            return entry;
        }
        public readonly List<int[]> clauses = new();
        public readonly int[] assignment;
        public readonly List<List<int>> watches = new();
        public readonly List<Entry> trail = new();
        public readonly List<string> trace = new();
        public readonly Stats stats = new Stats();
        public int head;
        public State(int variables, List<int[]> original) {
            assignment = new int[variables + 1];
            foreach (int[] clause in original)
                clauses.Add(clause.ToArray());
            for (int i = 0; i < 2 * (variables + 1); i++)
                watches.Add(new());
            for (int i = 0; i < clauses.Count; i++) {
                int[] clause = clauses[i];
                if (clause.Length >= 2) {
                    Watch(clause[0]).Add(i);
                    Watch(clause[1]).Add(i);
                }
            }
        }
        public List<int> Watch(int literal) {
            return watches[2 * Math.Abs(literal) + (literal < 0 ? 1 : 0)];
        }
        public int Value(int literal) {
            return assignment[Math.Abs(literal)] * (literal > 0 ? 1 : -1);
        }
        public void Assign(int literal, int kind) {
            assignment[Math.Abs(literal)] = literal > 0 ? 1 : -1;
            trail.Add(new Entry(literal, kind));
            trace.Add(new string[] { "D", "F", "P" }[kind] + literal);
        }
        public void Conflict() {
            stats.conflicts++;
            trace.Add("C");
        }
        public Result Result(bool satisfied) {
            bool[] model = satisfied ? new bool[assignment.Length] : null;
            if (satisfied)
                for (int i = 1; i < assignment.Length; i++)
                    model[i] = assignment[i] == 1;
            return new Result(model, trace, stats);
        }
        public Result Run() {
            foreach (int[] clause in clauses) {
                if (clause.Length == 0 || clause.Length == 1 && Value(clause[0]) < 0) {
                    Conflict();
                    return Result(false);
                }
                if (clause.Length == 1 && Value(clause[0]) == 0) {
                    Assign(clause[0], 2);
                    stats.propagations++;
                }
            }
            while (true) {
                bool foundConflict = false;
                while (head < trail.Count) {
                    int falseLiteral = -trail[head++].literal;
                    List<int> watched = Watch(falseLiteral);
                    int index = 0;
                    while (index < watched.Count) {
                        int id = watched[index];
                        int[] clause = clauses[id];
                        if (clause[0] == falseLiteral) {
                            int swap = clause[0];
                            clause[0] = clause[1];
                            clause[1] = swap;
                        }
                        int other = clause[0];
                        if (Value(other) > 0) {
                            index++;
                            continue;
                        }
                        int replacement = -1;
                        for (int j = 2; j < clause.Length; j++)
                            if (Value(clause[j]) >= 0) {
                                replacement = j;
                                break;
                            }
                        if (replacement >= 0) {
                            int swap = clause[1];
                            clause[1] = clause[replacement];
                            clause[replacement] = swap;
                            watched.RemoveAt(index);
                            Watch(clause[1]).Add(id);
                            continue;
                        }
                        if (Value(other) < 0) {
                            Conflict();
                            foundConflict = true;
                            break;
                        }
                        if (Value(other) == 0) {
                            Assign(other, 2);
                            stats.propagations++;
                        }
                        index++;
                    }
                    if (foundConflict)
                        break;
                }
                if (foundConflict) {
                    while (trail.Count != 0 && trail[^1].kind != 0) {
                        Entry entry = Pop();
                        assignment[Math.Abs(entry.literal)] = 0;
                    }
                    if (trail.Count == 0)
                        return Result(false);
                    Entry decision = Pop();
                    assignment[Math.Abs(decision.literal)] = 0;
                    Assign(-decision.literal, 1);
                    head = trail.Count - 1;
                    continue;
                }
                int[] positive = new int[assignment.Length], negative = new int[assignment.Length];
                foreach (int[] clause in clauses) {
                    bool satisfied = false;
                    foreach (int literal in clause)
                        if (Value(literal) > 0)
                            satisfied = true;
                    if (satisfied)
                        continue;
                    foreach (int literal in clause)
                        if (Value(literal) == 0) {
                            if (literal > 0)
                                positive[literal]++;
                            else
                                negative[-literal]++;
                        }
                }
                int best = 0, count = 0;
                for (int x = 1; x < assignment.Length; x++) {
                    if (positive[x] > count) {
                        count = positive[x];
                        best = x;
                    }
                    if (negative[x] > count) {
                        count = negative[x];
                        best = -x;
                    }
                }
                if (best == 0)
                    return Result(true);
                Assign(best, 0);
                stats.decisions++;
                int depth = 0;
                foreach (Entry entry in trail)
                    if (entry.kind != 2)
                        depth++;
                stats.maxDepth = Math.Max(stats.maxDepth, depth);
            }
        }
    }
    public static Result Run(int variables, List<int[]> clauses) {
        return new State(variables, clauses).Run();
    }
}
