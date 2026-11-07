import java.util.*;
final class Dpll {
    static final class Stats {
        int decisions, propagations, conflicts, maxDepth;
        void add(Stats other) {
            decisions += other.decisions;
            propagations += other.propagations;
            conflicts += other.conflicts;
            maxDepth = Math.max(maxDepth, other.maxDepth);
        }
    }
    record Entry(int literal, int kind) {}
    record Result(boolean[] model, List<String> trace, Stats stats) {}
    static final class State {
        final List<int[]> clauses = new ArrayList<>();
        final int[] assignment;
        final List<List<Integer>> watches = new ArrayList<>();
        final List<Entry> trail = new ArrayList<>();
        final List<String> trace = new ArrayList<>();
        final Stats stats = new Stats();
        int head;
        State(int variables, List<int[]> original) {
            assignment = new int[variables + 1];
            for (int[] clause : original)
                clauses.add(clause.clone());
            for (int i = 0; i < 2 * (variables + 1); i++)
                watches.add(new ArrayList<>());
            for (int i = 0; i < clauses.size(); i++) {
                int[] clause = clauses.get(i);
                if (clause.length >= 2) {
                    watch(clause[0]).add(i);
                    watch(clause[1]).add(i);
                }
            }
        }
        List<Integer> watch(int literal) {
            return watches.get(2 * Math.abs(literal) + (literal < 0 ? 1 : 0));
        }
        int value(int literal) {
            return assignment[Math.abs(literal)] * (literal > 0 ? 1 : -1);
        }
        void assign(int literal, int kind) {
            assignment[Math.abs(literal)] = literal > 0 ? 1 : -1;
            trail.add(new Entry(literal, kind));
            trace.add(new String[] {"D", "F", "P"}[kind] + literal);
        }
        void conflict() {
            stats.conflicts++;
            trace.add("C");
        }
        Result result(boolean satisfied) {
            boolean[] model = satisfied ? new boolean[assignment.length] : null;
            if (satisfied)
                for (int i = 1; i < assignment.length; i++)
                    model[i] = assignment[i] == 1;
            return new Result(model, trace, stats);
        }
        Result run() {
            for (int[] clause : clauses) {
                if (clause.length == 0 || clause.length == 1 && value(clause[0]) < 0) {
                    conflict();
                    return result(false);
                }
                if (clause.length == 1 && value(clause[0]) == 0) {
                    assign(clause[0], 2);
                    stats.propagations++;
                }
            }
            while (true) {
                boolean foundConflict = false;
                while (head < trail.size()) {
                    int falseLiteral = -trail.get(head++).literal;
                    List<Integer> watched = watch(falseLiteral);
                    int index = 0;
                    while (index < watched.size()) {
                        int id = watched.get(index);
                        int[] clause = clauses.get(id);
                        if (clause[0] == falseLiteral) {
                            int swap = clause[0];
                            clause[0] = clause[1];
                            clause[1] = swap;
                        }
                        int other = clause[0];
                        if (value(other) > 0) {
                            index++;
                            continue;
                        }
                        int replacement = -1;
                        for (int j = 2; j < clause.length; j++)
                            if (value(clause[j]) >= 0) {
                                replacement = j;
                                break;
                            }
                        if (replacement >= 0) {
                            int swap = clause[1];
                            clause[1] = clause[replacement];
                            clause[replacement] = swap;
                            watched.remove(index);
                            watch(clause[1]).add(id);
                            continue;
                        }
                        if (value(other) < 0) {
                            conflict();
                            foundConflict = true;
                            break;
                        }
                        if (value(other) == 0) {
                            assign(other, 2);
                            stats.propagations++;
                        }
                        index++;
                    }
                    if (foundConflict)
                        break;
                }
                if (foundConflict) {
                    while (!trail.isEmpty() && trail.getLast().kind != 0) {
                        Entry entry = trail.removeLast();
                        assignment[Math.abs(entry.literal)] = 0;
                    }
                    if (trail.isEmpty())
                        return result(false);
                    Entry decision = trail.removeLast();
                    assignment[Math.abs(decision.literal)] = 0;
                    assign(-decision.literal, 1);
                    head = trail.size() - 1;
                    continue;
                }
                int[] positive = new int[assignment.length], negative = new int[assignment.length];
                for (int[] clause : clauses) {
                    boolean satisfied = false;
                    for (int literal : clause)
                        if (value(literal) > 0)
                            satisfied = true;
                    if (satisfied)
                        continue;
                    for (int literal : clause)
                        if (value(literal) == 0) {
                            if (literal > 0)
                                positive[literal]++;
                            else
                                negative[-literal]++;
                        }
                }
                int best = 0, count = 0;
                for (int x = 1; x < assignment.length; x++) {
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
                    return result(true);
                assign(best, 0);
                stats.decisions++;
                int depth = 0;
                for (Entry entry : trail)
                    if (entry.kind != 2)
                        depth++;
                stats.maxDepth = Math.max(stats.maxDepth, depth);
            }
        }
    }
    static Result run(int variables, List<int[]> clauses) {
        return new State(variables, clauses).run();
    }
}
