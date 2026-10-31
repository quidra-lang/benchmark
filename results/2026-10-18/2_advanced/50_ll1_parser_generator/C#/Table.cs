using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Table {
    public sealed class Production {
        public int number;
        public string lhs;
        public List<string> rhs;
        public Dictionary<string, string> predict = new();
        public Production(int number, string lhs, List<string> rhs) {
            this.number = number;
            this.lhs = lhs;
            this.rhs = rhs;
        }
        public string Notation() {
            return GrammarParser.Production(lhs, rhs);
        }
    }
    public record Cell(string lhs, string terminal) {
    }
    public record Conflict(Cell cell, string kind, int chosen) {
    }
    public sealed class Result {
        public List<Production> productions = new();
        public Dictionary<Cell, List<int>> cells = new();
        public Dictionary<Cell, int> choices = new();
        public List<Conflict> conflicts = new();
    }
    public static Result Build(GrammarParser.Grammar grammar, FirstFollow.Sets sets) {
        Result result = new Result();
        foreach (string lhs in grammar.order)
            foreach (List<string> rhs in grammar.rules[lhs])
                result.productions.Add(new Production(result.productions.Count + 1, lhs, rhs));
        List<string> terminals = new(sets.terminals);
        terminals.Add("$");
        foreach (string lhs in grammar.order)
            foreach (string terminal in terminals)
                result.cells[new Cell(lhs, terminal)] = new();
        foreach (Production production in result.productions) {
            FirstFollow.Sequence direct = FirstFollow.OfSequence(production.rhs, sets);
            foreach (string terminal in direct.first)
                production.predict[terminal] = "FIRST";
            if (direct.empty)
                foreach (string terminal in sets.follow[production.lhs])
                    production.predict.TryAdd(terminal, "FOLLOW");
            foreach (string terminal in FirstFollow.TerminalOrder(production.predict.Keys))
                result.cells[new Cell(production.lhs, terminal)].Add(production.number);
        }
        foreach (string lhs in grammar.order)
            foreach (string terminal in terminals) {
                Cell cell = new Cell(lhs, terminal);
                List<int> entries = result.cells[cell];
                if (entries.Count == 0)
                    continue;
                int chosen = entries[0];
                bool first = false, follow = false;
                foreach (int number in entries) {
                    string reason = result.productions[number - 1].predict[terminal];
                    if (reason.Equals("FIRST")) {
                        if (!first)
                            chosen = number;
                        first = true;
                    } else
                        follow = true;
                }
                result.choices[cell] = chosen;
                if (entries.Count > 1)
                    result.conflicts.Add(new Conflict(cell,
                                                      first && follow ? "FIRST/FOLLOW"
                                                      : first         ? "FIRST/FIRST"
                                                                      : "FOLLOW/FOLLOW",
                                                      chosen));
            }
        return result;
    }
}
