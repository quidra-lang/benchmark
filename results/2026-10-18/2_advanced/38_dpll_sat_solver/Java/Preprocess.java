import java.util.*;
final class Preprocess {
    record Clause(int id, int[] literals) {}
    static final class Result {
        int tautologies, duplicateLiterals, unitFixed, pureFixed, empty;
        final List<Integer> tautology = new ArrayList<>(), unit = new ArrayList<>(),
                            subsumed = new ArrayList<>(), pure = new ArrayList<>();
        final int[] fixed;
        final List<Integer> active = new ArrayList<>();
        List<int[]> clauses = new ArrayList<>();
        Result(int variables) {
            fixed = new int[variables + 1];
        }
        int removed() {
            return tautology.size() + unit.size() + subsumed.size() + pure.size();
        }
    }
    static Result run(CnfIo.Formula formula, boolean pureEnabled) {
        Result result = new Result(formula.variables());
        List<Clause> working = new ArrayList<>();
        for (int i = 0; i < formula.clauses().size(); i++) {
            int[] original = formula.clauses().get(i);
            Set<Integer> all = new HashSet<>();
            boolean tautology = false;
            for (int literal : original) {
                if (all.contains(-literal))
                    tautology = true;
                all.add(literal);
            }
            if (tautology) {
                result.tautologies++;
                result.tautology.add(i + 1);
                continue;
            }
            Set<Integer> seen = new HashSet<>();
            List<Integer> literals = new ArrayList<>();
            for (int literal : original) {
                if (seen.add(literal))
                    literals.add(literal);
                else
                    result.duplicateLiterals++;
            }
            working.add(new Clause(i + 1, literals.stream().mapToInt(Integer::intValue).toArray()));
        }
        while (true) {
            int literal = 0;
            for (Clause clause : working)
                if (clause.literals.length == 0) {
                    result.empty = clause.id;
                    return result;
                }
            for (Clause clause : working)
                if (clause.literals.length == 1) {
                    literal = clause.literals[0];
                    break;
                }
            if (literal == 0)
                break;
            result.fixed[Math.abs(literal)] = literal > 0 ? 1 : -1;
            result.unitFixed++;
            List<Clause> next = new ArrayList<>();
            for (Clause clause : working) {
                boolean satisfied = false;
                List<Integer> rest = new ArrayList<>();
                for (int value : clause.literals) {
                    if (value == literal)
                        satisfied = true;
                    if (value != -literal)
                        rest.add(value);
                }
                if (satisfied)
                    result.unit.add(clause.id);
                else
                    next.add(new Clause(clause.id, rest.stream().mapToInt(Integer::intValue).toArray()));
            }
            working = next;
        }
        List<Set<Integer>> sets = new ArrayList<>();
        for (Clause clause : working) {
            Set<Integer> set = new HashSet<>();
            for (int literal : clause.literals)
                set.add(literal);
            sets.add(set);
        }
        boolean[] removed = new boolean[working.size()];
        for (int b = 0; b < working.size(); b++)
            for (int a = 0; a < working.size(); a++)
                if (a != b && (sets.get(a).size() < sets.get(b).size() || a < b) &&
                    sets.get(b).containsAll(sets.get(a))) {
                    removed[b] = true;
                    break;
                }
        List<Clause> retained = new ArrayList<>();
        for (int i = 0; i < working.size(); i++)
            if (removed[i])
                result.subsumed.add(working.get(i).id);
            else
                retained.add(working.get(i));
        working = retained;
        if (pureEnabled)
            while (true) {
                boolean[] positive = new boolean[formula.variables() + 1], negative =
                                                                               new boolean[positive.length];
                for (Clause clause : working)
                    for (int literal : clause.literals)
                        if (literal > 0)
                            positive[literal] = true;
                        else
                            negative[-literal] = true;
                Set<Integer> pure = new HashSet<>();
                for (int x = 1; x <= formula.variables(); x++)
                    if (positive[x] != negative[x]) {
                        int literal = positive[x] ? x : -x;
                        pure.add(literal);
                        result.fixed[x] = positive[x] ? 1 : -1;
                        result.pureFixed++;
                    }
                if (pure.isEmpty())
                    break;
                List<Clause> next = new ArrayList<>();
                for (Clause clause : working) {
                    boolean satisfied = false;
                    for (int literal : clause.literals)
                        if (pure.contains(literal))
                            satisfied = true;
                    if (satisfied)
                        result.pure.add(clause.id);
                    else
                        next.add(clause);
                }
                working = next;
            }
        for (Clause clause : working)
            result.clauses.add(clause.literals);
        for (int x = 1; x <= formula.variables(); x++)
            if (result.fixed[x] == 0)
                result.active.add(x);
        return result;
    }
}
