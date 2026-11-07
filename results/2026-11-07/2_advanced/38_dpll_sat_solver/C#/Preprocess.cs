using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Preprocess {
    public sealed record Clause(int id, int[] literals);
    public sealed class Result {
        public int tautologies, duplicateLiterals, unitFixed, pureFixed, empty;
        public readonly List<int> tautology = new(), unit = new(), subsumed = new(), pure = new();
        public readonly int[] fixedAssignment;
        public readonly List<int> active = new();
        public List<int[]> clauses = new();
        public Result(int variables) {
            fixedAssignment = new int[variables + 1];
        }
        public int Removed() {
            return tautology.Count + unit.Count + subsumed.Count + pure.Count;
        }
    }
    public static Result Run(CnfIo.Formula formula, bool pureEnabled) {
        Result result = new Result(formula.variables);
        List<Clause> working = new();
        for (int i = 0; i < formula.clauses.Count; i++) {
            int[] original = formula.clauses[i];
            HashSet<int> all = new();
            bool tautology = false;
            foreach (int literal in original) {
                if (all.Contains(-literal))
                    tautology = true;
                all.Add(literal);
            }
            if (tautology) {
                result.tautologies++;
                result.tautology.Add(i + 1);
                continue;
            }
            HashSet<int> seen = new();
            List<int> literals = new();
            foreach (int literal in original) {
                if (seen.Add(literal))
                    literals.Add(literal);
                else
                    result.duplicateLiterals++;
            }
            working.Add(new Clause(i + 1, literals.ToArray()));
        }
        while (true) {
            int literal = 0;
            foreach (Clause clause in working)
                if (clause.literals.Length == 0) {
                    result.empty = clause.id;
                    return result;
                }
            foreach (Clause clause in working)
                if (clause.literals.Length == 1) {
                    literal = clause.literals[0];
                    break;
                }
            if (literal == 0)
                break;
            result.fixedAssignment[Math.Abs(literal)] = literal > 0 ? 1 : -1;
            result.unitFixed++;
            List<Clause> next = new();
            foreach (Clause clause in working) {
                bool satisfied = false;
                List<int> rest = new();
                foreach (int value in clause.literals) {
                    if (value == literal)
                        satisfied = true;
                    if (value != -literal)
                        rest.Add(value);
                }
                if (satisfied)
                    result.unit.Add(clause.id);
                else
                    next.Add(new Clause(clause.id, rest.ToArray()));
            }
            working = next;
        }
        List<HashSet<int>> sets = new();
        foreach (Clause clause in working) {
            HashSet<int> set = new();
            foreach (int literal in clause.literals)
                set.Add(literal);
            sets.Add(set);
        }
        bool[] removed = new bool[working.Count];
        for (int b = 0; b < working.Count; b++)
            for (int a = 0; a < working.Count; a++)
                if (a != b && (sets[a].Count < sets[b].Count || a < b) && sets[a].IsSubsetOf(sets[b])) {
                    removed[b] = true;
                    break;
                }
        List<Clause> retained = new();
        for (int i = 0; i < working.Count; i++)
            if (removed[i])
                result.subsumed.Add(working[i].id);
            else
                retained.Add(working[i]);
        working = retained;
        if (pureEnabled)
            while (true) {
                bool[] positive = new bool[formula.variables + 1], negative = new bool[positive.Length];
                foreach (Clause clause in working)
                    foreach (int literal in clause.literals)
                        if (literal > 0)
                            positive[literal] = true;
                        else
                            negative[-literal] = true;
                HashSet<int> pure = new();
                for (int x = 1; x <= formula.variables; x++)
                    if (positive[x] != negative[x]) {
                        int literal = positive[x] ? x : -x;
                        pure.Add(literal);
                        result.fixedAssignment[x] = positive[x] ? 1 : -1;
                        result.pureFixed++;
                    }
                if (pure.Count == 0)
                    break;
                List<Clause> next = new();
                foreach (Clause clause in working) {
                    bool satisfied = false;
                    foreach (int literal in clause.literals)
                        if (pure.Contains(literal))
                            satisfied = true;
                    if (satisfied)
                        result.pure.Add(clause.id);
                    else
                        next.Add(clause);
                }
                working = next;
            }
        foreach (Clause clause in working)
            result.clauses.Add(clause.literals);
        for (int x = 1; x <= formula.variables; x++)
            if (result.fixedAssignment[x] == 0)
                result.active.Add(x);
        return result;
    }
}
