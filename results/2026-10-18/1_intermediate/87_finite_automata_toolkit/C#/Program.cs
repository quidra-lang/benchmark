using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;

class Program
{
    class Problem(string reason) : Exception("error: " + reason) { }

    static void Fail(string reason) => throw new Problem(reason);

    static HashSet<int> Singleton(int i) => new() { i };

    static string Alphabet(string text) => string.Concat(text.Order());

    static string SetKey(HashSet<int> set) => string.Join(",", set.Order());

    class Automaton(string kind, string alphabet)
    {
        public string Kind = kind, Alphabet = alphabet;
        public List<string> States = new();
        public List<HashSet<int>[]> Transitions = new();
        public HashSet<int> Accepting = new();
        public int Start;
        public int AddState(string name)
        {
            int id = States.Count;
            States.Add(name);
            Transitions.Add(Enumerable.Range(0, Alphabet.Length + 1).Select(_ => new HashSet<int>()).ToArray());
            return id;
        }
        public void Names(string prefix, int count)
        {
            for (int i = 0; i < count; i++) AddState(prefix + i);
        }
        public void Edge(int from, int symbol, int to) => Transitions[from][symbol].Add(to);
        public int Delta(int from, int symbol) => Transitions[from][symbol].First();
        public int TransitionCount => Transitions.Sum(row => row.Sum(set => set.Count));
        public int EpsilonCount => Transitions.Sum(row => row[Alphabet.Length].Count);
        public string Summary(string name) => $"{Kind} {name}: alphabet={Alphabet} states={States.Count} accepting={Accepting.Count} transitions={TransitionCount}";
        public string Set(HashSet<int> set) => "{" + string.Join(",", set.Order().Select(p => States[p])) + "}";
        public string List(HashSet<int> set) => set.Count == 0 ? "none" : string.Join(",", set.Order().Select(p => States[p]));
        public HashSet<int> Close(HashSet<int> input)
        {
            HashSet<int> output = new(input);
            Queue<int> queue = new(input);
            while (queue.Count > 0) foreach (int q in Transitions[queue.Dequeue()][Alphabet.Length]) if (output.Add(q)) queue.Enqueue(q);
            return output;
        }
        public HashSet<int> Initial() => Close(Singleton(Start));
        public HashSet<int> Move(HashSet<int> from, int symbol)
        {
            HashSet<int> output = new();
            foreach (int p in from) output.UnionWith(Transitions[p][symbol]);
            return Close(output);
        }
        public bool Accepts(HashSet<int> set) => set.Overlaps(Accepting);
        public HashSet<int> GraphReach(bool reverse)
        {
            HashSet<int> reached = reverse ? new(Accepting) : Singleton(Start);
            bool changed;
            do
            {
                int old = reached.Count;
                for (int p = 0; p < States.Count; p++) foreach (var edges in Transitions[p])
                {
                    if (reverse)
                    {
                        if (edges.Overlaps(reached)) reached.Add(p);
                    }
                    else if (reached.Contains(p)) reached.UnionWith(edges);
                }
                changed = old != reached.Count;
            } while (changed);
            return reached;
        }
    }

    record Created(Automaton Automaton, List<string> Details);
    readonly Dictionary<string, Automaton> automata = new(StringComparer.Ordinal);
    readonly List<string> registration = new();

    Automaton Get(string name) => automata.TryGetValue(name, out Automaton? a) ? a : throw new Problem("unknown automaton " + name);

    static Created Determinize(Automaton a)
    {
        Automaton d = new("DFA", a.Alphabet);
        List<HashSet<int>> subsets = new();
        Dictionary<string, int> ids = new(StringComparer.Ordinal);
        List<string> details = new();
        HashSet<int> first = a.Initial();
        subsets.Add(first);
        ids[SetKey(first)] = 0;
        d.AddState("D0");
        for (int i = 0; i < subsets.Count; i++)
        {
            var set = subsets[i];
            if (a.Accepts(set)) d.Accepting.Add(i);
            details.Add($"  D{i} = {a.Set(set)}");
            for (int c = 0; c < a.Alphabet.Length; c++)
            {
                var next = a.Move(set, c);
                string key = SetKey(next);
                if (!ids.TryGetValue(key, out int id))
                {
                    id = subsets.Count;
                    ids[key] = id;
                    subsets.Add(next);
                    d.AddState("D" + id);
                }
                d.Edge(i, c, id);
            }
        }
        return new(d, details);
    }

    static int[] BlockIndices(List<List<int>> blocks, int count)
    {
        int[] indices = Enumerable.Repeat(-1, count).ToArray();
        for (int i = 0; i < blocks.Count; i++) foreach (int p in blocks[i]) indices[p] = i;
        return indices;
    }

    static string Partition(Automaton a, List<List<int>> blocks) => string.Join(" ", blocks.Select(block => a.Set(new(block))));

    static Created Minimize(Automaton a)
    {
        var reachable = a.GraphReach(false);
        HashSet<int> missing = new(Enumerable.Range(0, a.States.Count));
        missing.ExceptWith(reachable);
        List<string> details = new() { "  unreachable: " + a.List(missing) };
        List<List<int>> blocks = new();
        List<int> yes = new(), no = new();
        for (int p = 0; p < a.States.Count; p++) if (reachable.Contains(p)) (a.Accepting.Contains(p) ? yes : no).Add(p);
        if (yes.Count > 0) blocks.Add(yes);
        if (no.Count > 0) blocks.Add(no);
        blocks.Sort((x, y) => x[0].CompareTo(y[0]));
        details.Add("  round 0: " + Partition(a, blocks));
        int round = 0;
        while (true)
        {
            int[] index = BlockIndices(blocks, a.States.Count);
            List<List<int>> next = new();
            foreach (List<int> block in blocks)
            {
                Dictionary<string, List<int>> groups = new(StringComparer.Ordinal);
                foreach (int p in block)
                {
                    string signature = string.Join(",", Enumerable.Range(0, a.Alphabet.Length).Select(c => index[a.Delta(p, c)]));
                    if (!groups.TryGetValue(signature, out var group))
                    {
                        group = new();
                        groups[signature] = group;
                        next.Add(group);
                    }
                    group.Add(p);
                }
            }
            next.Sort((x, y) => x[0].CompareTo(y[0]));
            if (next.Count == blocks.Count) break;
            blocks = next;
            details.Add($"  round {++round}: {Partition(a, blocks)}");
        }
        int[] finalIndex = BlockIndices(blocks, a.States.Count);
        List<int> named = new() { finalIndex[a.Start] };
        Dictionary<int, int> ids = new() { [finalIndex[a.Start]] = 0 };
        Automaton m = new("DFA", a.Alphabet);
        m.AddState("M0");
        for (int i = 0; i < named.Count; i++)
        {
            var block = blocks[named[i]];
            int p = block[0];
            if (a.Accepting.Contains(p)) m.Accepting.Add(i);
            details.Add($"  M{i} = {a.Set(new(block))}");
            for (int c = 0; c < a.Alphabet.Length; c++)
            {
                int target = finalIndex[a.Delta(p, c)];
                if (!ids.TryGetValue(target, out int id))
                {
                    id = named.Count;
                    named.Add(target);
                    ids[target] = id;
                    m.AddState("M" + id);
                }
                m.Edge(i, c, id);
            }
        }
        return new(m, details);
    }

    static void CopyEdges(Automaton source, Automaton target, int offset, bool reverse)
    {
        for (int p = 0; p < source.States.Count; p++) for (int c = 0; c <= source.Alphabet.Length; c++) foreach (int q in source.Transitions[p][c]) target.Edge((reverse ? q : p) + offset, c, (reverse ? p : q) + offset);
    }

    static Automaton EpsilonFree(Automaton a)
    {
        Automaton n = new("NFA", a.Alphabet);
        foreach (string state in a.States) n.AddState(state);
        n.Start = a.Start;
        for (int p = 0; p < a.States.Count; p++)
        {
            var closure = a.Close(Singleton(p));
            if (a.Accepts(closure)) n.Accepting.Add(p);
            for (int c = 0; c < a.Alphabet.Length; c++) n.Transitions[p][c].UnionWith(a.Move(closure, c));
        }
        return n;
    }

    static Automaton UnaryConstruction(Automaton a, string command)
    {
        if (command == "COMPLEMENT")
        {
            Automaton n = new("DFA", a.Alphabet);
            foreach (string state in a.States) n.AddState(state);
            n.Start = a.Start;
            CopyEdges(a, n, 0, false);
            n.Accepting.UnionWith(Enumerable.Range(0, a.States.Count));
            n.Accepting.ExceptWith(a.Accepting);
            return n;
        }
        Automaton result = new("NFA", a.Alphabet);
        result.Names("N", a.States.Count + 1);
        CopyEdges(a, result, 1, command == "REVERSE");
        if (command == "REVERSE")
        {
            result.Accepting.Add(a.Start + 1);
            foreach (int p in a.Accepting) result.Edge(0, a.Alphabet.Length, p + 1);
        }
        else
        {
            result.Accepting.Add(0);
            result.Edge(0, a.Alphabet.Length, a.Start + 1);
            foreach (int p in a.Accepting)
            {
                result.Accepting.Add(p + 1);
                result.Edge(p + 1, a.Alphabet.Length, a.Start + 1);
            }
        }
        return result;
    }

    static Automaton Concatenate(Automaton a, Automaton b)
    {
        Automaton n = new("NFA", a.Alphabet);
        int offset = a.States.Count;
        n.Names("N", offset + b.States.Count);
        n.Start = a.Start;
        CopyEdges(a, n, 0, false);
        CopyEdges(b, n, offset, false);
        foreach (int p in a.Accepting) n.Edge(p, a.Alphabet.Length, offset + b.Start);
        foreach (int p in b.Accepting) n.Accepting.Add(offset + p);
        return n;
    }
    readonly record struct Pair(int A, int B);

    static Created Product(Automaton a, Automaton b, string command)
    {
        Automaton p = new("DFA", a.Alphabet);
        Pair first = new(a.Start, b.Start);
        List<Pair> pairs = new() { first };
        Dictionary<Pair, int> ids = new() { [first] = 0 };
        List<string> details = new();
        p.AddState("P0");
        for (int i = 0; i < pairs.Count; i++)
        {
            Pair pair = pairs[i];
            bool x = a.Accepting.Contains(pair.A), y = b.Accepting.Contains(pair.B);
            if (command == "UNION" ? x || y : command == "INTERSECT" ? x && y : x && !y) p.Accepting.Add(i);
            details.Add($"  P{i} = ({a.States[pair.A]},{b.States[pair.B]})");
            for (int c = 0; c < a.Alphabet.Length; c++)
            {
                Pair next = new(a.Delta(pair.A, c), b.Delta(pair.B, c));
                if (!ids.TryGetValue(next, out int id))
                {
                    id = pairs.Count;
                    pairs.Add(next);
                    ids[next] = id;
                    p.AddState("P" + id);
                }
                p.Edge(i, c, id);
            }
        }
        return new(p, details);
    }

    static string Word(List<int> parents, List<char> incoming, int at)
    {
        StringBuilder text = new();
        while (parents[at] >= 0)
        {
            text.Append(incoming[at]);
            at = parents[at];
        }
        return new string(text.ToString().Reverse().ToArray());
    }

    static string Visible(string word) => word.Length == 0 ? "e" : word;

    static string Equivalent(Automaton a, Automaton b, string x, string z)
    {
        a = Determinize(a).Automaton;
        b = Determinize(b).Automaton;
        Pair first = new(a.Start, b.Start);
        List<Pair> pairs = new() { first };
        Dictionary<Pair, int> ids = new() { [first] = 0 };
        List<int> parents = new() { -1 };
        List<char> incoming = new() { ' ' };
        for (int i = 0; i < pairs.Count; i++)
        {
            Pair pair = pairs[i];
            bool accepted = a.Accepting.Contains(pair.A);
            if (accepted != b.Accepting.Contains(pair.B)) return $"NOT EQUIVALENT: {Visible(Word(parents, incoming, i))} is accepted only by {(accepted ? x : z)}";
            for (int c = 0; c < a.Alphabet.Length; c++)
            {
                Pair next = new(a.Delta(pair.A, c), b.Delta(pair.B, c));
                if (!ids.ContainsKey(next))
                {
                    ids[next] = pairs.Count;
                    pairs.Add(next);
                    parents.Add(i);
                    incoming.Add(a.Alphabet[c]);
                }
            }
        }
        return "EQUIVALENT";
    }

    static string? Smallest(Automaton d)
    {
        List<int> states = new() { d.Start }, parents = new() { -1 };
        List<char> incoming = new() { ' ' };
        bool[] seen = new bool[d.States.Count];
        seen[d.Start] = true;
        for (int i = 0; i < states.Count; i++)
        {
            int p = states[i];
            if (d.Accepting.Contains(p)) return Word(parents, incoming, i);
            for (int c = 0; c < d.Alphabet.Length; c++)
            {
                int q = d.Delta(p, c);
                if (!seen[q])
                {
                    seen[q] = true;
                    states.Add(q);
                    parents.Add(i);
                    incoming.Add(d.Alphabet[c]);
                }
            }
        }
        return null;
    }

    record Language(string Kind, long Count);

    static Language Classify(Automaton d, bool countWords)
    {
        var reachable = d.GraphReach(false);
        var live = d.GraphReach(true);
        live.IntersectWith(reachable);
        if (!live.Contains(d.Start)) return new("empty", 0);
        int[] indegree = new int[d.States.Count];
        foreach (int p in live) for (int c = 0; c < d.Alphabet.Length; c++)
        {
            int q = d.Delta(p, c);
            if (live.Contains(q)) indegree[q]++;
        }
        List<int> order = live.Where(p => indegree[p] == 0).Order().ToList();
        for (int i = 0; i < order.Count; i++) for (int c = 0; c < d.Alphabet.Length; c++)
        {
            int q = d.Delta(order[i], c);
            if (live.Contains(q) && --indegree[q] == 0) order.Add(q);
        }
        if (order.Count != live.Count) return new("infinite", 0);
        if (!countWords) return new("finite", 0);
        long[] counts = new long[d.States.Count];
        for (int i = order.Count - 1; i >= 0; i--)
        {
            int p = order[i];
            counts[p] = d.Accepting.Contains(p) ? 1 : 0;
            for (int c = 0; c < d.Alphabet.Length; c++) counts[p] += counts[d.Delta(p, c)];
        }
        return new("finite", counts[d.Start]);
    }

    static long Count(Automaton d, int length)
    {
        long[] values = new long[d.States.Count];
        values[d.Start] = 1;
        for (int i = 0; i < length; i++)
        {
            long[] next = new long[values.Length];
            for (int p = 0; p < values.Length; p++) for (int c = 0; c < d.Alphabet.Length; c++) next[d.Delta(p, c)] += values[p];
            values = next;
        }
        return d.Accepting.Sum(p => values[p]);
    }

    record Enumeration(string Text, int State);

    static string Enumerate(Automaton d, int maximum)
    {
        List<Enumeration> level = new() { new("", d.Start) };
        List<string> first = new();
        long total = 0;
        for (int length = 0; length <= maximum; length++)
        {
            List<Enumeration> next = new();
            foreach (Enumeration item in level)
            {
                if (d.Accepting.Contains(item.State))
                {
                    total++;
                    if (first.Count < 50) first.Add(Visible(item.Text));
                }
                if (length < maximum) for (int c = 0; c < d.Alphabet.Length; c++) next.Add(new(item.Text + d.Alphabet[c], d.Delta(item.State, c)));
            }
            level = next;
        }
        return total + (first.Count == 0 ? "" : " " + string.Join(" ", first)) + (total > 50 ? " ..." : "");
    }

    static string Synchronize(Automaton d)
    {
        int start = (1 << d.States.Count) - 1;
        List<int> sets = new() { start }, parents = new() { -1 };
        List<char> incoming = new() { ' ' };
        Dictionary<int, int> ids = new() { [start] = 0 };
        for (int i = 0; i < sets.Count; i++)
        {
            int set = sets[i];
            if (BitOperations.PopCount((uint)set) == 1) return $"SYNCHRONIZING {Visible(Word(parents, incoming, i))} -> {d.States[BitOperations.TrailingZeroCount((uint)set)]}";
            for (int c = 0; c < d.Alphabet.Length; c++)
            {
                int next = 0;
                for (int p = 0; p < d.States.Count; p++) if ((set & 1 << p) != 0) next |= 1 << d.Delta(p, c);
                if (!ids.ContainsKey(next))
                {
                    ids[next] = sets.Count;
                    sets.Add(next);
                    parents.Add(i);
                    incoming.Add(d.Alphabet[c]);
                }
            }
        }
        return "NOT SYNCHRONIZING";
    }

    record Regex(char Kind, List<Regex> Children);

    class RegexParser(string text)
    {
        int at;
        char Peek() => at == text.Length ? '\0' : text[at];
        void Error() => Fail("syntax error at " + (at + 1));
        public static bool Symbol(char c) => c is >= 'a' and <= 'z' or >= '0' and <= '9';
        Regex Alternation()
        {
            List<Regex> list = new() { Concatenation() };
            while (Peek() == '|')
            {
                at++;
                list.Add(Concatenation());
            }
            return list.Count == 1 ? list[0] : new('|', list);
        }
        Regex Concatenation()
        {
            List<Regex> list = new() { Factor() };
            while (Symbol(Peek()) || Peek() == '(') list.Add(Factor());
            return list.Count == 1 ? list[0] : new('.', list);
        }
        Regex Factor()
        {
            Regex r = Atom();
            while (Peek() is '*' or '+' or '?') r = new(text[at++], new() { r });
            return r;
        }
        Regex Atom()
        {
            char c = Peek();
            if (Symbol(c))
            {
                at++;
                return new(c, new());
            }
            if (c == '(')
            {
                at++;
                Regex r = Alternation();
                if (Peek() != ')') Error();
                at++;
                return r;
            }
            Error();
            return null!;
        }
        public Regex Parse()
        {
            Regex r = Alternation();
            if (at != text.Length) Error();
            return r;
        }
    }
    readonly record struct Fragment(int Entry, int Exit);

    static Fragment Build(Regex regex, Automaton a)
    {
        if (regex.Kind == '.')
        {
            Fragment? first = null, last = null;
            foreach (Regex child in regex.Children)
            {
                Fragment next = Build(child, a);
                if (last.HasValue) a.Edge(last.Value.Exit, a.Alphabet.Length, next.Entry);
                else first = next;
                last = next;
            }
            return new(first!.Value.Entry, last!.Value.Exit);
        }
        int entry = a.AddState("N" + a.States.Count);
        if (regex.Children.Count == 0)
        {
            int exit = a.AddState("N" + a.States.Count);
            a.Edge(entry, regex.Kind == 'e' ? a.Alphabet.Length : a.Alphabet.IndexOf(regex.Kind), exit);
            return new(entry, exit);
        }
        List<Fragment> parts = regex.Children.Select(child => Build(child, a)).ToList();
        int final = a.AddState("N" + a.States.Count);
        foreach (Fragment f in parts)
        {
            a.Edge(entry, a.Alphabet.Length, f.Entry);
            a.Edge(f.Exit, a.Alphabet.Length, final);
        }
        if (regex.Kind != '|')
        {
            Fragment f = parts[0];
            if (regex.Kind != '?') a.Edge(f.Exit, a.Alphabet.Length, f.Entry);
            if (regex.Kind != '+') a.Edge(entry, a.Alphabet.Length, final);
        }
        return new(entry, final);
    }

    Automaton Explicit(string[] w)
    {
        if (w.Length < 6) Fail("wrong number of arguments");
        if (automata.ContainsKey(w[1])) Fail(w[1] + " already exists");
        Automaton a = new(w[0], Alphabet(w[3]));
        foreach (string state in w[2].Split(','))
        {
            if (a.States.Contains(state)) Fail("duplicate state " + state);
            a.AddState(state);
        }
        a.Start = a.States.IndexOf(w[4]);
        if (a.Start < 0) Fail("unknown state " + w[4]);
        if (w[5] != "-") foreach (string state in w[5].Split(','))
        {
            int p = a.States.IndexOf(state);
            if (p < 0) Fail("unknown state " + state);
            if (!a.Accepting.Add(p)) Fail("duplicate state " + state);
        }
        for (int i = 6; i < w.Length; i++)
        {
            string[] t = w[i].Split(':');
            int p = a.States.IndexOf(t[0]);
            char c = t[1][0];
            if (p < 0) Fail("unknown state " + t[0]);
            if (c == 'e' && a.Kind == "DFA") Fail("epsilon transition in DFA");
            int symbol = c == 'e' ? a.Alphabet.Length : a.Alphabet.IndexOf(c);
            if (symbol < 0) Fail("unknown symbol " + c);
            int q = a.States.IndexOf(t[2]);
            if (q < 0) Fail("unknown state " + t[2]);
            var edges = a.Transitions[p][symbol];
            if (edges.Contains(q)) Fail("duplicate transition " + w[i]);
            if (a.Kind == "DFA" && edges.Count > 0) Fail("conflicting transition " + w[i]);
            a.Edge(p, symbol, q);
        }
        if (a.Kind == "DFA") for (int p = 0; p < a.States.Count; p++) for (int c = 0; c < a.Alphabet.Length; c++) if (a.Transitions[p][c].Count == 0) Fail($"missing transition {a.States[p]}:{a.Alphabet[c]}");
        return a;
    }

    static List<string> Table(Automaton a)
    {
        int columns = a.Alphabet.Length + 1 + (a.Kind == "NFA" && a.EpsilonCount > 0 ? 1 : 0);
        string[][] cells = Enumerable.Range(0, a.States.Count + 1).Select(_ => new string[columns]).ToArray();
        cells[0][0] = "";
        for (int c = 1; c < columns; c++) cells[0][c] = c <= a.Alphabet.Length ? a.Alphabet[c - 1].ToString() : "e";
        for (int p = 0; p < a.States.Count; p++)
        {
            cells[p + 1][0] = (p == a.Start ? "->" : "  ") + (a.Accepting.Contains(p) ? "*" : " ") + a.States[p];
            for (int c = 1; c < columns; c++)
            {
                var edges = a.Transitions[p][c - 1];
                cells[p + 1][c] = a.Kind == "DFA" ? a.States[edges.First()] : edges.Count == 0 ? "-" : a.Set(edges);
            }
        }
        int[] widths = Enumerable.Range(0, columns).Select(c => cells.Max(row => row[c].Length)).ToArray();
        return cells.Select(row => string.Join("  ", row.Select((cell, c) => cell.PadRight(widths[c]))).TrimEnd(' ')).ToList();
    }

    static string Show(Automaton a, string name)
    {
        StringBuilder text = new($"{a.Kind} {name} {string.Join(",", a.States)} {a.Alphabet} {a.States[a.Start]} {(a.Accepting.Count == 0 ? "-" : a.List(a.Accepting))}");
        for (int p = 0; p < a.States.Count; p++) for (int c = 0; c <= a.Alphabet.Length; c++) foreach (int q in a.Transitions[p][c].Order()) text.Append(' ').Append(a.States[p]).Append(':').Append(c == a.Alphabet.Length ? 'e' : a.Alphabet[c]).Append(':').Append(a.States[q]);
        return text.ToString();
    }

    List<string> Register(string name, Created created)
    {
        automata[name] = created.Automaton;
        registration.Add(name);
        List<string> output = new() { created.Automaton.Summary(name) };
        output.AddRange(created.Details);
        return output;
    }
    static readonly Dictionary<string, string> Roles = new(StringComparer.Ordinal)
    {
        ["ACCEPT"] = "RO",
        ["CLOSURE"] = "RO",
        ["ENUM"] = "RO",
        ["COUNT"] = "RO",
        ["TODFA"] = "RN",
        ["EPSFREE"] = "RN",
        ["REVERSE"] = "RN",
        ["STAR"] = "RN",
        ["MINIMIZE"] = "DN",
        ["COMPLEMENT"] = "DN",
        ["EQUIV"] = "RR",
        ["UNION"] = "DDN",
        ["INTERSECT"] = "DDN",
        ["DIFF"] = "DDN",
        ["CONCAT"] = "RRN",
        ["EMPTY"] = "R",
        ["FINITE"] = "R",
        ["INFO"] = "R",
        ["TABLE"] = "R",
        ["SHOW"] = "R",
        ["DELETE"] = "R",
        ["SYNC"] = "D",
        ["LIST"] = ""
    };

    List<string> Command(string line)
    {
        string[] w = line.Split(' ');
        string c = w[0];
        if (!Roles.ContainsKey(c) && c is not ("DFA" or "NFA" or "REGEX")) Fail("unknown command " + c);
        if (c is "DFA" or "NFA")
        {
            Automaton created = Explicit(w);
            return Register(w[1], new(created, new()));
        }
        if (c == "REGEX")
        {
            if (w.Length != 4) Fail("wrong number of arguments");
            if (automata.ContainsKey(w[1])) Fail(w[1] + " already exists");
            foreach (char ch in w[3]) if (RegexParser.Symbol(ch) && ch != 'e' && !w[2].Contains(ch)) Fail("unknown symbol " + ch);
            Regex regex = new RegexParser(w[3]).Parse();
            Automaton created = new("NFA", Alphabet(w[2]));
            Fragment fragment = Build(regex, created);
            created.Start = fragment.Entry;
            created.Accepting.Add(fragment.Exit);
            return Register(w[1], new(created, new()));
        }
        string roles = Roles[c];
        if (w.Length != roles.Length + 1) Fail("wrong number of arguments");
        for (int i = 0; i < roles.Length; i++) if (roles[i] is 'R' or 'D') Get(w[i + 1]);
        for (int i = 0; i < roles.Length; i++) if (roles[i] == 'N' && automata.ContainsKey(w[i + 1])) Fail(w[i + 1] + " already exists");
        for (int i = 0; i < roles.Length; i++) if (roles[i] == 'D' && Get(w[i + 1]).Kind == "NFA") Fail(w[i + 1] + " is not a DFA");
        if ((c is "EQUIV" or "UNION" or "INTERSECT" or "DIFF" or "CONCAT") && Get(w[1]).Alphabet != Get(w[2]).Alphabet) Fail("alphabets differ");
        if (c == "LIST") return registration.Count == 0 ? new() { "(none)" } : registration.Select(name => automata[name].Summary(name)).ToList();
        Automaton a = Get(w[1]);
        switch (c)
        {
            case "DELETE":
                automata.Remove(w[1]);
                registration.Remove(w[1]);
                return new() { "deleted " + w[1] };
            case "ACCEPT":
            {
                string word = w[2] == "e" ? "" : w[2];
                foreach (char ch in word) if (!a.Alphabet.Contains(ch)) Fail("unknown symbol " + ch);
                var set = a.Initial();
                StringBuilder path = new(a.Kind == "DFA" ? a.States[set.Single()] : a.Set(set));
                foreach (char ch in word)
                {
                    set = a.Move(set, a.Alphabet.IndexOf(ch));
                    path.Append(" -").Append(ch).Append("-> ").Append(a.Kind == "DFA" ? a.States[set.Single()] : a.Set(set));
                }
                return new() { (a.Accepts(set) ? "ACCEPT " : "REJECT ") + path };
            }
            case "CLOSURE":
            {
                HashSet<int> set = new();
                foreach (string state in w[2].Split(','))
                {
                    int p = a.States.IndexOf(state);
                    if (p < 0) Fail("unknown state " + state);
                    set.Add(p);
                }
                return new() { a.Set(a.Close(set)) };
            }
            case "TODFA":
                return Register(w[2], Determinize(a));
            case "EPSFREE":
                return Register(w[2], new(EpsilonFree(a), new()));
            case "MINIMIZE":
                return Register(w[2], Minimize(a));
            case "COMPLEMENT":
            case "REVERSE":
            case "STAR":
                return Register(w[2], new(UnaryConstruction(a, c), new()));
            case "CONCAT":
                return Register(w[3], new(Concatenate(a, Get(w[2])), new()));
            case "UNION":
            case "INTERSECT":
            case "DIFF":
                return Register(w[3], Product(a, Get(w[2]), c));
            case "EQUIV":
                return new() { Equivalent(a, Get(w[2]), w[1], w[2]) };
            case "TABLE":
                return Table(a);
            case "SHOW":
                return new() { Show(a, w[1]) };
            case "SYNC":
                return new() { Synchronize(a) };
        }
        Automaton d = Determinize(a).Automaton;
        switch (c)
        {
            case "COUNT":
                return new() { Count(d, int.Parse(w[2])).ToString() };
            case "ENUM":
                return new() { Enumerate(d, int.Parse(w[2])) };
            case "EMPTY":
                string? smallest = Smallest(d);
                return new() { smallest == null ? "EMPTY" : "NOT EMPTY " + Visible(smallest) };
            case "FINITE":
                Language language = Classify(d, true);
                return new() { language.Kind == "infinite" ? "INFINITE" : "FINITE " + language.Count };
            case "INFO":
                bool deterministic = a.EpsilonCount == 0, complete = true;
                foreach (var row in a.Transitions) for (int symbol = 0; symbol < a.Alphabet.Length; symbol++)
                {
                    deterministic &= row[symbol].Count <= 1;
                    complete &= row[symbol].Count > 0;
                }
                return new() { a.Summary(w[1]), "  epsilon transitions: " + a.EpsilonCount, "  reachable: " + a.List(a.GraphReach(false)), "  live: " + a.List(a.GraphReach(true)), "  deterministic: " + (deterministic ? "yes" : "no"), "  complete: " + (complete ? "yes" : "no"), "  language: " + Classify(d, false).Kind, "  minimal DFA states: " + Minimize(d).Automaton.States.Count };
        }
        throw new InvalidOperationException();
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        Program toolkit = new();
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            if (line.StartsWith('#')) continue;
            try
            {
                foreach (string output in toolkit.Command(line)) Console.WriteLine(output);
            }
            catch (Problem problem)
            {
                Console.WriteLine(problem.Message);
            }
        }
    }
}
