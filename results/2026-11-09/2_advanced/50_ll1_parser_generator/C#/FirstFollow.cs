using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class FirstFollow {
    public static bool Include<T>(this HashSet<T> set, IEnumerable<T> values) {
        int count = set.Count;
        set.UnionWith(values);
        return set.Count != count;
    }
    public static List<string> TerminalOrder(IEnumerable<string> terminals) {
        List<string> result = new();
        bool end = false;
        foreach (string terminal in terminals)
            if (terminal.Equals("$"))
                end = true;
            else
                result.Add(terminal);
        result.Sort(StringComparer.Ordinal);
        if (end)
            result.Add("$");
        return result;
    }
    public static HashSet<string> Terminals(GrammarParser.Grammar grammar) {
        HashSet<string> result = new();
        foreach (string lhs in grammar.order)
            foreach (List<string> rhs in grammar.rules[lhs])
                foreach (string symbol in rhs)
                    if (!GrammarParser.Nonterminal(symbol))
                        result.Add(symbol);
        return result;
    }
    public record Sequence(HashSet<string> first, bool empty) {
    }
    public sealed class Sets {
        public Dictionary<string, bool> nullable = new();
        public Dictionary<string, HashSet<string>> first = new(), follow = new();
        public int nullablePasses, firstPasses, followPasses;
        public List<string> terminals;
    }
    public static Sequence OfSequence(List<string> rhs, Sets sets) {
        HashSet<string> result = new();
        foreach (string symbol in rhs) {
            if (!GrammarParser.Nonterminal(symbol)) {
                result.Add(symbol);
                return new Sequence(result, false);
            }
            result.UnionWith(sets.first[symbol]);
            if (!sets.nullable[symbol])
                return new Sequence(result, false);
        }
        return new Sequence(result, true);
    }
    public static Sets Analyze(GrammarParser.Grammar grammar) {
        Sets sets = new Sets();
        foreach (string lhs in grammar.order) {
            sets.nullable[lhs] = false;
            sets.first[lhs] = new();
            sets.follow[lhs] = new();
        }
        sets.follow[grammar.start].Add("$");
        bool changed;
        do {
            sets.nullablePasses++;
            changed = false;
            foreach (string lhs in grammar.order)
                if (!sets.nullable[lhs])
                    foreach (List<string> rhs in grammar.rules[lhs]) {
                        bool empty = true;
                        foreach (string symbol in rhs)
                            if (!GrammarParser.Nonterminal(symbol) || !sets.nullable[symbol])
                                empty = false;
                        if (empty) {
                            sets.nullable[lhs] = true;
                            changed = true;
                            break;
                        }
                    }
        } while (changed);
        do {
            sets.firstPasses++;
            changed = false;
            foreach (string lhs in grammar.order)
                foreach (List<string> rhs in grammar.rules[lhs])
                    if (sets.first[lhs].Include(OfSequence(rhs, sets).first))
                        changed = true;
        } while (changed);
        do {
            sets.followPasses++;
            changed = false;
            foreach (string lhs in grammar.order)
                foreach (List<string> rhs in grammar.rules[lhs])
                    for (int i = 0; i < rhs.Count; i++) {
                        string symbol = rhs[i];
                        if (!GrammarParser.Nonterminal(symbol))
                            continue;
                        Sequence suffix = OfSequence(rhs.GetRange(i + 1, rhs.Count - (i + 1)), sets);
                        HashSet<string> more = new(suffix.first);
                        if (suffix.empty)
                            more.UnionWith(sets.follow[lhs]);
                        if (sets.follow[symbol].Include(more))
                            changed = true;
                    }
        } while (changed);
        sets.terminals = TerminalOrder(Terminals(grammar));
        return sets;
    }
}
