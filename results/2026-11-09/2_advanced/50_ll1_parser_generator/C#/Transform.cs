using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Transform {
    public record Result(GrammarParser.Grammar grammar, List<string> log) {
    }
    public static string Fresh(string lhs, GrammarParser.Grammar grammar) {
        string name = lhs.Substring(0, lhs.Length - 1 - (0)) + "'>";
        while (grammar.rules.ContainsKey(name))
            name = name.Substring(0, name.Length - 1 - (0)) + "'>";
        return name;
    }
    public static bool Reaches(GrammarParser.Grammar grammar, string source, string target) {
        HashSet<string> seen = new();
        Queue<string> queue = new();
        seen.Add(source);
        queue.Enqueue(source);
        while (queue.Count != 0) {
            string current = queue.Dequeue();
            foreach (List<string> rhs in grammar.rules[current])
                if (rhs.Count != 0 && GrammarParser.Nonterminal(rhs[0])) {
                    string next = rhs[0];
                    if (next.Equals(target))
                        return true;
                    if (seen.Add(next))
                        queue.Enqueue(next);
                }
        }
        return false;
    }
    public static List<List<string>> Unique(List<List<string>> alternatives) {
        List<List<string>> result = new();
        foreach (List<string> rhs in alternatives)
            if (!result.Any(old => old.SequenceEqual(rhs)))
                result.Add(rhs);
        return result;
    }
    public static List<string> Concatenate(List<string> a, List<string> b) {
        List<string> result = new(a);
        result.AddRange(b);
        return result;
    }
    public static Result Eliminate(GrammarParser.Grammar source) {
        GrammarParser.Grammar grammar = GrammarParser.Copy(source);
        List<string> original = new(grammar.order), log = new();
        for (int i = 0; i < original.Count; i++) {
            string lhs = original[i];
            for (int j = 0; j < i; j++) {
                string earlier = original[j];
                bool needed = false;
                foreach (List<string> rhs in grammar.rules[lhs])
                    if (rhs.Count != 0 && rhs[0].Equals(earlier))
                        needed = true;
                if (!needed || !Reaches(grammar, earlier, lhs))
                    continue;
                List<List<string>> replacements = new();
                foreach (List<string> rhs in grammar.rules[lhs])
                    if (rhs.Count != 0 && rhs[0].Equals(earlier)) {
                        foreach (List<string> delta in grammar.rules[earlier])
                            replacements.Add(Concatenate(delta, rhs.GetRange(1, rhs.Count - (1))));
                    } else
                        replacements.Add(rhs);
                grammar.rules[lhs] = Unique(replacements);
                log.Add("substitute " + earlier + " into " + lhs);
            }
            List<List<string>> recursive = new(), nonrecursive = new();
            foreach (List<string> rhs in grammar.rules[lhs]) {
                if (rhs.Count == 1 && rhs[0].Equals(lhs)) {
                    log.Add("remove cycle " + GrammarParser.Production(lhs, rhs));
                    continue;
                }
                if (rhs.Count != 0 && rhs[0].Equals(lhs))
                    recursive.Add(new(rhs.GetRange(1, rhs.Count - (1))));
                else
                    nonrecursive.Add(rhs);
            }
            if (recursive.Count == 0) {
                grammar.rules[lhs] = nonrecursive;
                continue;
            }
            string created = Fresh(lhs, grammar);
            List<List<string>> left = new(), right = new();
            foreach (List<string> rhs in nonrecursive)
                left.Add(Concatenate(rhs, [created]));
            foreach (List<string> rhs in recursive)
                right.Add(Concatenate(rhs, [created]));
            right.Add(new());
            grammar.rules[lhs] = left;
            grammar.rules[created] = right;
            grammar.order.Insert(grammar.order.IndexOf(lhs) + 1, created);
            log.Add("eliminate left recursion in " + lhs + " with " + created);
        }
        return new Result(grammar, log);
    }
    public static Result Factor(GrammarParser.Grammar source) {
        GrammarParser.Grammar grammar = GrammarParser.Copy(source);
        List<string> log = new();
        for (int position = 0; position < grammar.order.Count; position++) {
            string lhs = grammar.order[position];
            List<List<string>> current = grammar.rules[lhs];
            List<string> insertions = new();
            int index = 0;
            while (index < current.Count) {
                List<string> row = current[index];
                if (row.Count == 0) {
                    index++;
                    continue;
                }
                List<int> group = new();
                for (int i = 0; i < current.Count; i++)
                    if (current[i].Count != 0 && current[i][0].Equals(row[0]))
                        group.Add(i);
                if (group.Count == 1) {
                    index++;
                    continue;
                }
                int length = row.Count;
                foreach (int i in group)
                    length = Math.Min(length, current[i].Count);
                int prefix = 0;
                while (prefix < length) {
                    bool same = true;
                    foreach (int i in group)
                        if (!current[i][prefix].Equals(row[prefix]))
                            same = false;
                    if (!same)
                        break;
                    prefix++;
                }
                List<string> common = new(row.GetRange(0, prefix - (0)));
                string created = Fresh(lhs, grammar);
                List<List<string>> suffixes = new();
                foreach (int i in group)
                    suffixes.Add(new(current[i].GetRange(prefix, current[i].Count - (prefix))));
                grammar.rules[created] = suffixes;
                List<List<string>> replacement = new();
                for (int i = 0; i < current.Count; i++)
                    if (i == group[0])
                        replacement.Add(Concatenate(common, [created]));
                    else if (!group.Contains(i))
                        replacement.Add(current[i]);
                grammar.rules[lhs] = replacement;
                current = replacement;
                insertions.Add(created);
                log.Add("left factor " + lhs + " on " + GrammarParser.Notation(common) + " with " + created);
                index = group[0] + 1;
            }
            grammar.order.InsertRange(position + 1, insertions);
        }
        return new Result(grammar, log);
    }
}
