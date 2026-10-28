using System.Numerics;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static string Repeat(this string text, int count) => string.Concat(Enumerable.Repeat(text, count));
    public static GrammarParser.Grammar parsed, cleaned, eliminated, factored, grammar;
    public static List<string> diagnostics = new(), eliminationLog, factorLog, unreachableLog = new();
    public static FirstFollow.Sets sets;
    public static Table.Result table;
    public static int beforeConflicts;
    public static Dictionary<string, Metric> lengths = new(), costs = new();
    public static Dictionary<string, List<string>> words = new(), leftContext = new(), rightContext = new();
    public record Metric(BigInteger length, int height) : IComparable<Metric> {
        public int CompareTo(Metric m) {
            int c = length.CompareTo(m.length);
            return c != 0 ? c : height.CompareTo(m.height);
        }
    }
    public static BigInteger Plus(BigInteger a, BigInteger b) {
        return a + b;
    }
    public static string List<T>(string heading, IEnumerable<T> values) {
        string line = heading;
        foreach (Object value in values)
            line += " " + value;
        return line;
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static HashSet<string> Reachable(GrammarParser.Grammar g) {
        HashSet<string> seen = new();
        Queue<string> queue = new();
        queue.Enqueue(g.start);
        seen.Add(g.start);
        while (queue.Count != 0) {
            string lhs = queue.Dequeue();
            foreach (List<string> rhs in g.rules[lhs])
                foreach (string symbol in rhs)
                    if (GrammarParser.Nonterminal(symbol) && seen.Add(symbol))
                        queue.Enqueue(symbol);
        }
        return seen;
    }
    public static string FirstRemoved(List<string> rhs, HashSet<string> removed) {
        foreach (string symbol in rhs)
            if (removed.Contains(symbol))
                return symbol;
        return null;
    }
    public static void FilterAlternatives(GrammarParser.Grammar g, HashSet<string> removed, string reason) {
        foreach (string lhs in g.order) {
            List<List<string>> keep = new();
            foreach (List<string> rhs in g.rules[lhs]) {
                string symbol = FirstRemoved(rhs, removed);
                if (symbol == null)
                    keep.Add(rhs);
                else
                    diagnostics.Add("removed " + GrammarParser.Production(lhs, rhs) + " (" + reason + " " +
                                    symbol + ")");
            }
            g.rules[lhs] = keep;
        }
    }
    public static void Remove(GrammarParser.Grammar g, HashSet<string> removed) {
        g.order.RemoveAll(symbol => removed.Contains(symbol));
        foreach (string symbol in removed)
            g.rules.Remove(symbol);
    }
    public static GrammarParser.Grammar Clean() {
        GrammarParser.Grammar g = GrammarParser.Copy(parsed);
        if (parsed.hasDeclaration)
            foreach (string word in FirstFollow.TerminalOrder(parsed.words.Keys))
                if (!parsed.declared.Contains(word))
                    diagnostics.Add("undeclared terminal " + word + " at line " + parsed.words[word]);
        HashSet<string> undefined = new();
        foreach (string lhs in g.order)
            foreach (List<string> rhs in g.rules[lhs])
                foreach (string symbol in rhs)
                    if (GrammarParser.Nonterminal(symbol) && !g.rules.ContainsKey(symbol))
                        undefined.Add(symbol);
        List<string> sorted = new(undefined);
        sorted.Sort((a, b) =>
                        string.CompareOrdinal(a.Substring(1, a.Length - 2), b.Substring(1, b.Length - 2)));
        foreach (string symbol in sorted)
            diagnostics.Add("undefined nonterminal " + symbol);
        FilterAlternatives(g, undefined, "undefined");
        HashSet<string> productive = new();
        bool changed;
        do {
            changed = false;
            foreach (string lhs in g.order)
                if (!productive.Contains(lhs))
                    foreach (List<string> rhs in g.rules[lhs]) {
                        bool valid = true;
                        foreach (string symbol in rhs)
                            if (GrammarParser.Nonterminal(symbol) && !productive.Contains(symbol))
                                valid = false;
                        if (valid) {
                            productive.Add(lhs);
                            changed = true;
                            break;
                        }
                    }
        } while (changed);
        HashSet<string> removed = new();
        foreach (string lhs in g.order)
            if (!productive.Contains(lhs)) {
                removed.Add(lhs);
                diagnostics.Add("unproductive nonterminal " + lhs);
            }
        Remove(g, removed);
        FilterAlternatives(g, removed, "unproductive");
        HashSet<string> reachable = Reachable(g);
        removed = new();
        foreach (string lhs in g.order)
            if (!reachable.Contains(lhs)) {
                removed.Add(lhs);
                diagnostics.Add("unreachable nonterminal " + lhs);
            }
        Remove(g, removed);
        return g;
    }
    public static void LeftRecursion() {
        foreach (string origin in cleaned.order) {
            Queue<string> queue = new();
            Dictionary<string, string> parent = new();
            HashSet<string> seen = new();
            queue.Enqueue(origin);
            seen.Add(origin);
            string last = null;
            while (queue.Count != 0 && last == null) {
                string current = queue.Dequeue();
                foreach (List<string> rhs in cleaned.rules[current]) {
                    if (rhs.Count == 0)
                        continue;
                    string first = rhs[0];
                    if (first.Equals(origin)) {
                        last = current;
                        break;
                    }
                    if (GrammarParser.Nonterminal(first) && seen.Add(first)) {
                        parent[first] = current;
                        queue.Enqueue(first);
                    }
                }
            }
            if (last != null) {
                List<string> path = new();
                for (string current = last; !current.Equals(origin); current = parent[current])
                    path.Add(current);
                path.Reverse();
                path.Insert(0, origin);
                path.Add(origin);
                diagnostics.Add("left recursion: " + string.Join(" -> ", path));
            }
        }
    }
    public static void Prepare() {
        diagnostics.AddRange(parsed.diagnostics);
        cleaned = Clean();
        LeftRecursion();
        FirstFollow.Sets before = FirstFollow.Analyze(cleaned);
        beforeConflicts = Table.Build(cleaned, before).conflicts.Count;
        Transform.Result elimination = Transform.Eliminate(cleaned);
        eliminated = elimination.grammar;
        eliminationLog = elimination.log;
        Transform.Result factoring = Transform.Factor(eliminated);
        factored = factoring.grammar;
        factorLog = factoring.log;
        grammar = GrammarParser.Copy(factored);
        HashSet<string> reachable = Reachable(grammar), removed = new();
        foreach (string lhs in grammar.order)
            if (!reachable.Contains(lhs)) {
                removed.Add(lhs);
                unreachableLog.Add("remove unreachable " + lhs);
                diagnostics.Add("unreachable after transformation " + lhs);
            }
        Remove(grammar, removed);
        sets = FirstFollow.Analyze(grammar);
        table = Table.Build(grammar, sets);
        if (parsed.hasDeclaration) {
            HashSet<string> unused = new(parsed.declared);
            unused.ExceptWith(sets.terminals);
            foreach (string terminal in FirstFollow.TerminalOrder(unused))
                diagnostics.Add("unused token " + terminal);
        }
        Shortest();
        Contexts();
    }
    public static Metric AlternativeMetric(List<string> rhs) {
        BigInteger length = BigInteger.Zero;
        int height = 1;
        foreach (string symbol in rhs)
            if (GrammarParser.Nonterminal(symbol)) {
                Metric child = lengths.GetValueOrDefault(symbol);
                if (child == null)
                    return null;
                length = Plus(length, child.length);
                height = Math.Max(height, child.height + 1);
            } else
                length = Plus(length, BigInteger.One);
        return new Metric(length, height);
    }
    public static void Shortest() {
        bool changed;
        do {
            changed = false;
            foreach (string lhs in grammar.order)
                foreach (List<string> rhs in grammar.rules[lhs]) {
                    Metric candidate = AlternativeMetric(rhs), old = lengths.GetValueOrDefault(lhs);
                    if (candidate != null && (old == null || candidate.CompareTo(old) < 0)) {
                        lengths[lhs] = candidate;
                        changed = true;
                    }
                }
        } while (changed);
        foreach (string lhs in grammar.order)
            Word(lhs);
    }
    public static List<string> Word(string lhs) {
        if (words.ContainsKey(lhs))
            return words[lhs];
        foreach (List<string> rhs in grammar.rules[lhs])
            if (AlternativeMetric(rhs).Equals(lengths[lhs])) {
                List<string> result = Sentence(rhs);
                words[lhs] = result;
                return result;
            }
        throw new InvalidOperationException();
    }
    public static List<string> Sentence(List<string> symbols) {
        List<string> result = new();
        foreach (string symbol in symbols)
            if (GrammarParser.Nonterminal(symbol))
                result.AddRange(Word(symbol));
            else
                result.Add(symbol);
        return result;
    }
    public static Metric ContextMetric(Table.Production production, int occurrence) {
        Metric parent = costs.GetValueOrDefault(production.lhs);
        if (parent == null)
            return null;
        BigInteger length = parent.length;
        for (int i = 0; i < production.rhs.Count; i++)
            if (i != occurrence) {
                string symbol = production.rhs[i];
                length =
                    Plus(length, GrammarParser.Nonterminal(symbol) ? lengths[symbol].length : BigInteger.One);
            }
        return new Metric(length, parent.height + 1);
    }
    public static void Contexts() {
        costs[grammar.start] = new Metric(BigInteger.Zero, 0);
        bool changed;
        do {
            changed = false;
            foreach (Table.Production production in table.productions)
                for (int i = 0; i < production.rhs.Count; i++) {
                    string symbol = production.rhs[i];
                    if (!GrammarParser.Nonterminal(symbol) || symbol.Equals(grammar.start))
                        continue;
                    Metric candidate = ContextMetric(production, i), old = costs.GetValueOrDefault(symbol);
                    if (candidate != null && (old == null || candidate.CompareTo(old) < 0)) {
                        costs[symbol] = candidate;
                        changed = true;
                    }
                }
        } while (changed);
        leftContext[grammar.start] = new();
        rightContext[grammar.start] = new();
        foreach (string lhs in grammar.order)
            Context(lhs);
    }
    public static void Context(string lhs) {
        if (leftContext.ContainsKey(lhs))
            return;
        foreach (Table.Production production in table.productions)
            for (int i = 0; i < production.rhs.Count; i++)
                if (production.rhs[i].Equals(lhs) && ContextMetric(production, i) != null &&
                    ContextMetric(production, i).Equals(costs[lhs])) {
                    Context(production.lhs);
                    List<string> left = new(leftContext[production.lhs]);
                    left.AddRange(Sentence(production.rhs.GetRange(0, i - (0))));
                    List<string> right =
                        Sentence(production.rhs.GetRange(i + 1, production.rhs.Count - (i + 1)));
                    right.AddRange(rightContext[production.lhs]);
                    leftContext[lhs] = left;
                    rightContext[lhs] = right;
                    return;
                }
    }
    public static List<string> Example(Table.Production production) {
        List<string> result = new(leftContext[production.lhs]);
        result.AddRange(Sentence(production.rhs));
        result.AddRange(rightContext[production.lhs]);
        return result;
    }
    public static string Summary(GrammarParser.Grammar g) {
        int productions = 0, empty = 0, unit = 0;
        foreach (string lhs in g.order)
            foreach (List<string> rhs in g.rules[lhs]) {
                productions++;
                if (rhs.Count == 0)
                    empty++;
                if (rhs.Count == 1 && GrammarParser.Nonterminal(rhs[0]))
                    unit++;
            }
        return "start=" + g.start + " nonterminals=" + g.order.Count +
               " terminals=" + FirstFollow.Terminals(g).Count + " productions=" + productions +
               " empty=" + empty + " unit=" + unit;
    }
    public static List<string> Listing(GrammarParser.Grammar g, bool numbered) {
        List<string> result = new();
        int count = 0;
        foreach (string lhs in g.order)
            count += g.rules[lhs].Count;
        int width = Convert.ToString(count).Length, number = 0;
        foreach (string lhs in g.order)
            for (int i = 0; i < g.rules[lhs].Count; i++) {
                number++;
                string line = (i == 0 ? lhs + " -> " : " ".Repeat(lhs.Length) + " | ") +
                              GrammarParser.Notation(g.rules[lhs][i]);
                if (numbered)
                    line = " ".Repeat(width - Convert.ToString(number).Length) + number + "  " + line;
                result.Add(line);
            }
        return result;
    }
    public static void Stage(List<string> output, string heading, List<string> log, GrammarParser.Grammar g,
                             bool numbered) {
        output.Add(heading);
        if (log != null)
            output.AddRange(log.Count == 0 ? ["none"] : log);
        output.Add(Summary(g));
        output.AddRange(Listing(g, numbered));
        output.Add("");
    }
    public static List<string> GrammarReport() {
        List<string> output = new();
        Stage(output, "== cleaned grammar ==", null, cleaned, false);
        Stage(output, "== left recursion elimination ==", eliminationLog, eliminated, false);
        Stage(output, "== left factoring ==", factorLog, factored, false);
        Stage(output, "== final grammar ==", unreachableLog, grammar, true);
        output.Add("== cross reference ==");
        List<string> symbols = new(grammar.order);
        symbols.AddRange(sets.terminals);
        foreach (string symbol in symbols) {
            List<int> uses = new();
            foreach (Table.Production production in table.productions)
                if (production.rhs.Contains(symbol))
                    uses.Add(production.number);
            string label = GrammarParser.Nonterminal(symbol) ? symbol : "\"" + symbol + "\"";
            output.Add(uses.Count == 0 ? label + " not used" : List(label + " used in", uses));
        }
        return output;
    }
    public static List<string> SetsReport() {
        List<string> output = new([
            "passes: nullable=" + sets.nullablePasses + " first=" + sets.firstPasses +
                " follow=" + sets.followPasses,
            ""
        ]);
        foreach (string lhs in grammar.order) {
            output.Add(lhs);
            output.Add("  nullable: " + (sets.nullable[lhs] ? "yes" : "no"));
            output.Add(List("  first:", FirstFollow.TerminalOrder(sets.first[lhs])));
            output.Add(List("  follow:", FirstFollow.TerminalOrder(sets.follow[lhs])));
            output.Add(List("  shortest:", words[lhs]));
        }
        return output;
    }
    public static List<int> FirstPath(int number, string terminal) {
        Queue<int> queue = new();
        HashSet<int> seen = new();
        Dictionary<int, int> parent = new();
        queue.Enqueue(number);
        seen.Add(number);
        while (queue.Count != 0) {
            int current = queue.Dequeue();
            Table.Production production = table.productions[current - 1];
            foreach (string symbol in production.rhs) {
                if (symbol.Equals(terminal)) {
                    List<int> path = new();
                    for (int q = current; q != number; q = parent[q])
                        path.Add(q);
                    path.Reverse();
                    return path;
                }
                if (GrammarParser.Nonterminal(symbol))
                    foreach (Table.Production next in table.productions)
                        if (next.lhs.Equals(symbol) && seen.Add(next.number)) {
                            parent[next.number] = current;
                            queue.Enqueue(next.number);
                        }
                if (!GrammarParser.Nonterminal(symbol) || !sets.nullable[symbol])
                    break;
            }
        }
        throw new InvalidOperationException();
    }
    public static List<int> FollowPath(string lhs, string terminal) {
        Queue<string> queue = new();
        Dictionary<string, List<int>> paths = new();
        paths[lhs] = new();
        queue.Enqueue(lhs);
        while (queue.Count != 0) {
            string current = queue.Dequeue();
            if (current.Equals(grammar.start) && terminal.Equals("$"))
                return paths[current];
            foreach (Table.Production production in table.productions)
                for (int i = 0; i < production.rhs.Count; i++)
                    if (production.rhs[i].Equals(current)) {
                        FirstFollow.Sequence suffix = FirstFollow.OfSequence(
                            production.rhs.GetRange(i + 1, production.rhs.Count - (i + 1)), sets);
                        List<int> path = new(paths[current]);
                        path.Add(production.number);
                        if (suffix.first.Contains(terminal))
                            return path;
                        if (suffix.empty && !paths.ContainsKey(production.lhs)) {
                            paths[production.lhs] = path;
                            queue.Enqueue(production.lhs);
                        }
                    }
        }
        throw new InvalidOperationException();
    }
    public static List<string> TableReport() {
        List<string> output = new(["== predict sets =="]);
        foreach (Table.Production production in table.productions) {
            output.Add(production.number + ": " + production.Notation());
            output.Add(List("  predict:", FirstFollow.TerminalOrder(production.predict.Keys)));
        }
        output.Add("");
        output.Add("== parse table ==");
        List<string> terminals = new(sets.terminals);
        terminals.Add("$");
        List<List<string>> rows = new();
        List<string> header = new([""]);
        header.AddRange(terminals);
        rows.Add(header);
        foreach (string lhs in grammar.order) {
            List<string> row = new([lhs]);
            foreach (string terminal in terminals) {
                List<int> cell = table.cells[new Table.Cell(lhs, terminal)];
                List<string> numbers = new();
                foreach (int number in cell)
                    numbers.Add(Convert.ToString(number));
                row.Add(numbers.Count == 0 ? "." : string.Join("/", numbers));
            }
            rows.Add(row);
        }
        int[] widths = new int[header.Count];
        foreach (List<string> row in rows)
            for (int c = 0; c < row.Count; c++)
                widths[c] = Math.Max(widths[c], row[c].Length);
        foreach (List<string> row in rows) {
            string line = row[0] + " ".Repeat(widths[0] - row[0].Length);
            for (int c = 1; c < row.Count; c++)
                line += "  " + " ".Repeat(widths[c] - row[c].Length) + row[c];
            output.Add(line);
        }
        output.Add("");
        output.Add("== conflicts ==");
        if (table.conflicts.Count == 0)
            output.Add("none");
        foreach (Table.Conflict conflict in table.conflicts) {
            string lhs = conflict.cell.lhs, terminal = conflict.cell.terminal;
            output.Add("conflict " + lhs + " on " + terminal + ": " + conflict.kind + ", chosen " +
                       conflict.chosen);
            foreach (int number in table.cells[conflict.cell]) {
                Table.Production production = table.productions[number - 1];
                string reason = production.predict[terminal];
                List<int> path =
                    reason.Equals("FIRST") ? FirstPath(number, terminal) : FollowPath(lhs, terminal);
                output.Add("  " + number + ": " + production.Notation() + " (" + reason +
                           (path.Count == 0 ? "" : List(" via", path)) + ")");
            }
        }
        output.Add("LL(1): " + (table.conflicts.Count == 0 ? "yes" : "no"));
        output.Add("conflicts before transformation: " + beforeConflicts);
        return output;
    }
    public record EarleyProduction(string lhs, List<string> rhs) {
    }
    public record State(int production, int dot, int origin) {
    }
    public static bool InLanguage(List<string> tokens) {
        List<EarleyProduction> productions = new();
        productions.Add(new EarleyProduction("", [cleaned.start]));
        foreach (string lhs in cleaned.order)
            foreach (List<string> rhs in cleaned.rules[lhs])
                productions.Add(new EarleyProduction(lhs, rhs));
        List<HashSet<State>> chart = new();
        for (int i = 0; i <= tokens.Count; i++)
            chart.Add(new());
        chart[0].Add(new State(0, 0, 0));
        for (int position = 0; position <= tokens.Count; position++) {
            bool changed;
            do {
                changed = false;
                foreach (State state in new HashSet<State>(chart[position])) {
                    EarleyProduction production = productions[state.production];
                    if (state.dot < production.rhs.Count) {
                        string symbol = production.rhs[state.dot];
                        if (GrammarParser.Nonterminal(symbol)) {
                            for (int q = 1; q < productions.Count; q++)
                                if (productions[q].lhs.Equals(symbol) &&
                                    chart[position].Add(new State(q, 0, position)))
                                    changed = true;
                        } else if (position < tokens.Count && symbol.Equals(tokens[position]))
                            chart[position + 1].Add(new State(state.production, state.dot + 1, state.origin));
                    } else
                        foreach (State previous in new HashSet<State>(chart[state.origin])) {
                            EarleyProduction parent = productions[previous.production];
                            if (previous.dot < parent.rhs.Count &&
                                parent.rhs[previous.dot].Equals(production.lhs) &&
                                chart[position].Add(
                                    new State(previous.production, previous.dot + 1, previous.origin)))
                                changed = true;
                        }
                }
            } while (changed);
        }
        return chart[tokens.Count].Contains(new State(0, 1, 0));
    }
    public static string Error(Driver.Event errorEvent) {
        string unexpected = errorEvent.token.Equals("$")
                                ? "end of input"
                                : "\"" + errorEvent.token + "\" at token " + errorEvent.position;
        string expected;
        if (GrammarParser.Nonterminal(errorEvent.symbol)) {
            List<string> terminals = new(sets.terminals);
            terminals.Add("$");
            List<string> candidates = new();
            foreach (string terminal in terminals)
                if (table.choices.ContainsKey(new Table.Cell(errorEvent.symbol, terminal)))
                    candidates.Add(terminal.Equals("$") ? "$" : "\"" + terminal + "\"");
            expected = string.Join(" ", candidates);
        } else
            expected = errorEvent.symbol.Equals("$") ? "$" : "\"" + errorEvent.symbol + "\"";
        string recovery = errorEvent.kind.Equals("skip")  ? "skipped \"" + errorEvent.token + "\""
                          : errorEvent.kind.Equals("pop") ? "popped " + errorEvent.symbol
                                                          : "inserted \"" + errorEvent.symbol + "\"";
        return "step " + errorEvent.step + ": unexpected " + unexpected + "; expected " + expected + "; " +
               recovery;
    }
    public static string Label(Driver.Node node) {
        return node.symbol + (node.mark == null ? "" : " (" + node.mark + ")");
    }
    public static void Branches(Driver.Node node, string prefix, bool last, List<string> output) {
        output.Add(prefix + (last ? "`-- " : "|-- ") + Label(node));
        string next = prefix + (last ? "    " : "|   ");
        for (int i = 0; i < node.children.Count; i++)
            Branches(node.children[i], next, i == node.children.Count - 1, output);
    }
    public static List<string> Tree(Driver.Node node) {
        List<string> output = new();
        output.Add(Label(node));
        for (int i = 0; i < node.children.Count; i++)
            Branches(node.children[i], "", i == node.children.Count - 1, output);
        return output;
    }
    public static Driver.Node Compact(Driver.Node node) {
        List<Driver.Node> children = new();
        foreach (Driver.Node child in node.children) {
            if (child.symbol.Equals("%empty"))
                continue;
            Driver.Node compactChild = Compact(child);
            if (compactChild.mark == null && GrammarParser.Nonterminal(compactChild.symbol) &&
                compactChild.children.Count == 0)
                continue;
            if (compactChild.mark == null && GrammarParser.Nonterminal(compactChild.symbol) &&
                compactChild.symbol.Contains("'"))
                children.AddRange(compactChild.children);
            else
                children.Add(compactChild);
        }
        if (children.Count == 1 && node.mark == null)
            return children[0];
        Driver.Node result = new Driver.Node(node.symbol);
        result.mark = node.mark;
        result.children = children;
        return result;
    }
    public static List<string> Trace(Driver.Result parse) {
        List<List<string>> rows = new();
        rows.Add(new(["step", "stack", "input", "action"]));
        foreach (Driver.Trace trace in parse.trace)
            rows.Add(new([
                Convert.ToString(trace.step), string.Join(" ", trace.stack), string.Join(" ", trace.input),
                trace.action
            ]));
        int[] widths = new int[3];
        foreach (List<string> row in rows)
            for (int c = 0; c < 3; c++)
                widths[c] = Math.Max(widths[c], row[c].Length);
        List<string> output = new();
        foreach (List<string> row in rows) {
            string line = "";
            for (int c = 0; c < 3; c++)
                line += row[c] + " ".Repeat(widths[c] - row[c].Length) + "  ";
            output.Add(line + row[3]);
        }
        return output;
    }
    public static List<string> Derivation(List<int> leftParse) {
        List<string> sequence = new([grammar.start]), output = new(["  " + grammar.start]);
        foreach (int number in leftParse) {
            Table.Production production = table.productions[number - 1];
            int index = 0;
            while (!GrammarParser.Nonterminal(sequence[index]))
                index++;
            sequence.RemoveAt(index);
            sequence.InsertRange(index, production.rhs);
            output.Add("  => " + GrammarParser.Notation(sequence));
        }
        return output;
    }
    public static List<Driver.Input> Input(List<string> tokens) {
        List<Driver.Input> result = new();
        for (int i = 0; i < tokens.Count; i++)
            result.Add(new Driver.Input(tokens[i], i + 1));
        return result;
    }
    public static List<string> ParsesReport(List<string> inputs) {
        List<string> output = new();
        HashSet<int> used = new();
        List<int> mismatches = new();
        int accepted = 0, inLanguage = 0, unknown = 0, skip = 0, pop = 0, missing = 0;
        HashSet<string> known = new(sets.terminals);
        for (int number = 1; number <= inputs.Count; number++) {
            string line = inputs[number - 1];
            List<string> tokens = line.Length == 0 ? new() : new(line.Split(' ').ToList());
            List<Driver.Input> filtered = new();
            List<string> errors = new();
            for (int i = 0; i < tokens.Count; i++)
                if (known.Contains(tokens[i]))
                    filtered.Add(new Driver.Input(tokens[i], i + 1));
                else {
                    unknown++;
                    errors.Add("unknown \"" + tokens[i] + "\" at token " + (i + 1) + "; removed");
                }
            Driver.Result result = Driver.Parse(filtered, grammar, sets, table);
            used.UnionWith(result.leftParse);
            foreach (Driver.Event errorEvent in result.errors)
                errors.Add(Error(errorEvent));
            bool valid = errors.Count == 0, language = InLanguage(tokens);
            if (valid)
                accepted++;
            if (language)
                inLanguage++;
            if (valid != language)
                mismatches.Add(number);
            skip += result.skip;
            pop += result.pop;
            missing += result.missing;
            output.Add("== input " + number + " ==");
            output.Add(List("tokens:", tokens));
            output.AddRange(Trace(result));
            output.Add(List("left parse:", result.leftParse));
            output.Add("stats: steps=" + result.trace.Count + " predicts=" + result.predicts +
                       " matches=" + result.matches + " max_stack=" + result.maxStack);
            if (errors.Count != 0) {
                output.Add("errors:");
                foreach (string error in errors)
                    output.Add("  " + error);
            }
            output.Add(valid ? "result: accepted" : "result: rejected (errors: " + errors.Count + ")");
            output.Add("language: " + (language ? "yes" : "no"));
            if (valid) {
                output.Add("derivation:");
                output.AddRange(Derivation(result.leftParse));
            }
            output.Add("tree:");
            output.AddRange(Tree(result.root));
            output.Add("compact tree:");
            output.AddRange(Tree(Compact(result.root)));
            output.Add("");
        }
        output.Add("== summary ==");
        output.Add("inputs=" + inputs.Count + " accepted=" + accepted +
                   " rejected=" + (inputs.Count - accepted) + " in_language=" + inLanguage);
        output.Add(List("mismatches:", mismatches));
        output.Add("recovery: unknown=" + unknown + " skip=" + skip + " pop=" + pop + " missing=" + missing);
        output.Add("coverage: " + used.Count + " of " + table.productions.Count + " productions used");
        List<int> unused = new();
        foreach (Table.Production production in table.productions)
            if (!used.Contains(production.number))
                unused.Add(production.number);
        output.Add(List("unused:", unused));
        foreach (int number in unused) {
            Table.Production production = table.productions[number - 1];
            List<string> example = Example(production);
            Driver.Result result = Driver.Parse(Input(example), grammar, sets, table);
            output.Add("  " + number + ": " + production.Notation());
            output.Add(List("    example:", example));
            output.Add(result.errors.Count == 0
                           ? "    result: accepted"
                           : "    result: rejected (errors: " + result.errors.Count + ")");
            output.Add("    used: " + (result.leftParse.Contains(number) ? "yes" : "no"));
        }
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        parsed = GrammarParser.Parse(Lines("grammar.bnf"));
        Prepare();
        Write("grammar.txt", GrammarReport());
        Write("sets.txt", SetsReport());
        Write("table.txt", TableReport());
        Write("parses.txt", ParsesReport(Lines("inputs.txt")));
        diagnostics.Add(table.conflicts.Count == 0
                            ? "result: LL(1)"
                            : "result: not LL(1) (conflicts: " + table.conflicts.Count + ")");
        Write("diagnostics.txt", diagnostics);
    }
}
