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

    static bool Lower(char c) => c is >= 'a' and <= 'z';

    static bool Upper(char c) => c is >= 'A' and <= 'Z';

    static bool Digit(char c) => c is >= '0' and <= '9';

    static bool ValidName(string s) => s.Length is >= 1 and <= 8 && Lower(s[0]) && s.All(c => Lower(c) || Digit(c));

    static int Bits(int n) => BitOperations.PopCount((uint)n);

    record Shape(string Op, int Left, int Right);

    class Node(string op, Node? left, Node? right, int id)
    {
        public readonly string Op = op;
        public readonly Node? Left = left, Right = right;
        public readonly int Id = id;
        public readonly int Variables = op.Length == 1 && Upper(op[0]) ? 1 << (op[0] - 'A') : (left?.Variables ?? 0) | (right?.Variables ?? 0);
        public bool Binary => Right != null;
    }
    readonly Dictionary<Shape, Node> nodes = new();
    readonly SortedDictionary<string, Node> definitions = new(StringComparer.Ordinal);
    readonly Dictionary<int, string> printed = new();
    readonly Dictionary<(int, bool), Node> normalForms = new();

    Node Make(string op, Node? left = null, Node? right = null)
    {
        Shape shape = new(op, left?.Id ?? -1, right?.Id ?? -1);
        if (nodes.TryGetValue(shape, out Node? old)) return old;
        Node n = new(op, left, right, nodes.Count);
        nodes[shape] = n;
        return n;
    }

    Node Not(Node n) => Make("~", n);

    static int Precedence(string op) => op switch
    {
        "<->" => 1,
        "->" => 2,
        "|" => 3,
        "^" => 4,
        "&" => 5,
        _ => 6
    };

    string Print(Node n)
    {
        if (printed.TryGetValue(n.Id, out string? old)) return old;
        string result;
        if (n.Left == null) result = n.Op;
        else if (!n.Binary) result = "~" + (n.Left.Binary ? "(" + Print(n.Left) + ")" : Print(n.Left));
        else
        {
            string a = Print(n.Left), b = Print(n.Right!);
            int p = Precedence(n.Op);
            if (n.Left.Binary && (Precedence(n.Left.Op) < p || n.Op == "->" && n.Left.Op == "->")) a = "(" + a + ")";
            if (n.Right!.Binary && (Precedence(n.Right.Op) < p || n.Right.Op == n.Op && n.Op != "->")) b = "(" + b + ")";
            result = a + " " + n.Op + " " + b;
        }
        printed[n.Id] = result;
        return result;
    }

    static int Size(Node n) => 1 + (n.Left == null ? 0 : Size(n.Left)) + (n.Right == null ? 0 : Size(n.Right));

    static int Depth(Node n) => 1 + Math.Max(n.Left == null ? 0 : Depth(n.Left), n.Right == null ? 0 : Depth(n.Right));

    static string Variables(int mask) => string.Concat(Enumerable.Range(0, 26).Where(i => (mask & 1 << i) != 0).Select(i => (char)('A' + i)));

    record Token(string Text, int Position);

    class Parser
    {
        readonly Program workbench;
        readonly List<Token> tokens = new();
        readonly int end;
        int at;
        public Parser(Program workbench, string text, int start)
        {
            this.workbench = workbench;
            end = start + text.Length;
            for (int i = 0; i < text.Length;)
            {
                char c = text[i];
                if (c == ' ')
                {
                    i++;
                    continue;
                }
                int first = i;
                if (text.AsSpan(i).StartsWith("<->")) i += 3;
                else if (text.AsSpan(i).StartsWith("->")) i += 2;
                else if (Lower(c))
                {
                    i++;
                    while (i < text.Length && (Lower(text[i]) || Digit(text[i]))) i++;
                }
                else if (Upper(c) || "01~&^|()".Contains(c)) i++;
                else
                {
                    Fail($"invalid character '{c}' at {start + i}");
                    return;
                }
                tokens.Add(new(text[first..i], start + first));
            }
        }
        string Peek() => at == tokens.Count ? "" : tokens[at].Text;
        void Unexpected()
        {
            if (at == tokens.Count) Fail("unexpected end of formula at " + end);
            Token t = tokens[at];
            Fail($"unexpected '{t.Text}' at {t.Position}");
        }
        Node Unary()
        {
            string t = Peek();
            if (t == "~")
            {
                at++;
                return workbench.Not(Unary());
            }
            if (t == "(")
            {
                at++;
                Node n = Expression(1);
                if (Peek() != ")") Unexpected();
                at++;
                return n;
            }
            if (t.Length > 0 && (Upper(t[0]) || t is "0" or "1"))
            {
                at++;
                return workbench.Make(t);
            }
            if (t.Length > 0 && Lower(t[0]))
            {
                Token token = tokens[at++];
                if (!workbench.definitions.TryGetValue(t, out Node? n)) Fail($"undefined name '{t}' at {token.Position}");
                return n!;
            }
            Unexpected();
            return null!;
        }
        Node Expression(int level)
        {
            if (level == 6) return Unary();
            Node left = Expression(level + 1);
            string op = level switch
            {
                1 => "<->",
                2 => "->",
                3 => "|",
                4 => "^",
                _ => "&"
            };
            while (Peek() == op)
            {
                at++;
                left = workbench.Make(op, left, Expression(level == 2 ? level : level + 1));
            }
            return left;
        }
        public Node Parse()
        {
            Node n = Expression(1);
            if (at != tokens.Count) Unexpected();
            return n;
        }
    }

    Node Parse(string text, int start) => new Parser(this, text, start).Parse();

    Node Nnf(Node n, bool positive)
    {
        if (normalForms.TryGetValue((n.Id, positive), out Node? old)) return old;
        Node result;
        if (n.Left == null) result = n.Op is "0" or "1" ? Make(positive ? n.Op : n.Op == "0" ? "1" : "0") : positive ? n : Not(n);
        else if (n.Op == "~") result = Nnf(n.Left, !positive);
        else if (n.Op is "&" or "|") result = Make(positive ? n.Op : n.Op == "&" ? "|" : "&", Nnf(n.Left, positive), Nnf(n.Right!, positive));
        else if (n.Op == "->") result = Make(positive ? "|" : "&", Nnf(n.Left, !positive), Nnf(n.Right!, positive));
        else
        {
            bool equal = (n.Op == "<->") == positive;
            result = Make("|", Make("&", Nnf(n.Left, true), Nnf(n.Right!, equal)), Make("&", Nnf(n.Left, false), Nnf(n.Right!, !equal)));
        }
        normalForms[(n.Id, positive)] = result;
        return result;
    }

    Node Dual(Node n, Dictionary<int, Node> memo)
    {
        if (memo.TryGetValue(n.Id, out Node? old)) return old;
        Node result;
        if (n.Left == null) result = n.Op == "0" ? Make("1") : n.Op == "1" ? Make("0") : n;
        else if (n.Op == "~") result = Not(Dual(n.Left, memo));
        else
        {
            Node a = Dual(n.Left, memo), b = Dual(n.Right!, memo);
            result = n.Op switch
            {
                "&" => Make("|", a, b),
                "|" => Make("&", a, b),
                "^" => Make("<->", a, b),
                "<->" => Make("^", a, b),
                _ => Make("&", Not(a), b)
            };
        }
        memo[n.Id] = result;
        return result;
    }

    Node ReduceNot(Node n) => n.Op == "0" ? Make("1") : n.Op == "1" ? Make("0") : n.Op == "~" ? n.Left! : Not(n);

    static bool Complement(Node a, Node b) => a.Op == "~" && a.Left == b || b.Op == "~" && b.Left == a;

    Node SimplifyBinary(string op, Node a, Node b)
    {
        bool a0 = a.Op == "0", a1 = a.Op == "1", b0 = b.Op == "0", b1 = b.Op == "1";
        switch (op)
        {
            case "&":
                if (a0 || b0) return Make("0");
                if (a1) return b;
                if (b1 || a == b) return a;
                if (Complement(a, b)) return Make("0");
                break;
            case "|":
                if (a1 || b1) return Make("1");
                if (a0) return b;
                if (b0 || a == b) return a;
                if (Complement(a, b)) return Make("1");
                break;
            case "^":
                if (a0) return b;
                if (b0) return a;
                if (a1) return ReduceNot(b);
                if (b1) return ReduceNot(a);
                if (a == b) return Make("0");
                if (Complement(a, b)) return Make("1");
                break;
            case "->":
                if (a0 || b1) return Make("1");
                if (a1) return b;
                if (b0) return ReduceNot(a);
                if (a == b) return Make("1");
                if (Complement(a, b)) return b;
                break;
            case "<->":
                if (a1) return b;
                if (b1) return a;
                if (a0) return ReduceNot(b);
                if (b0) return ReduceNot(a);
                if (a == b) return Make("1");
                if (Complement(a, b)) return Make("0");
                break;
        }
        return Make(op, a, b);
    }

    Node Simplify(Node n, Dictionary<char, int> substitutions, Dictionary<int, Node> memo)
    {
        if (memo.TryGetValue(n.Id, out Node? old)) return old;
        Node result;
        if (n.Left == null) result = substitutions.TryGetValue(n.Op[0], out int value) ? Make(value.ToString()) : n;
        else if (n.Op == "~") result = ReduceNot(Simplify(n.Left, substitutions, memo));
        else result = SimplifyBinary(n.Op, Simplify(n.Left, substitutions, memo), Simplify(n.Right!, substitutions, memo));
        memo[n.Id] = result;
        return result;
    }

    static int Evaluate(Node n, int trueVariables, Dictionary<int, int> memo)
    {
        if (memo.TryGetValue(n.Id, out int old)) return old;
        int result;
        if (n.Left == null) result = Upper(n.Op[0]) ? (trueVariables >> (n.Op[0] - 'A')) & 1 : n.Op[0] - '0';
        else if (n.Op == "~") result = 1 - Evaluate(n.Left, trueVariables, memo);
        else
        {
            int a = Evaluate(n.Left, trueVariables, memo), b = Evaluate(n.Right!, trueVariables, memo);
            result = n.Op switch
            {
                "&" => a & b,
                "|" => a | b,
                "^" => a ^ b,
                "->" => (1 - a) | b,
                _ => 1 - (a ^ b)
            };
        }
        memo[n.Id] = result;
        return result;
    }

    static int[] Truth(Node n, string vars)
    {
        int[] table = new int[1 << vars.Length];
        for (int r = 0; r < table.Length; r++)
        {
            int mask = 0;
            for (int i = 0; i < vars.Length; i++) if ((r & 1 << (vars.Length - 1 - i)) != 0) mask |= 1 << (vars[i] - 'A');
            table[r] = Evaluate(n, mask, new());
        }
        return table;
    }

    static string Binary(int row, int count) => count == 0 ? "" : Convert.ToString(row, 2).PadLeft(count, '0');

    static string Assignment(int row, string vars) => "{" + string.Join(" ", vars.Select((c, i) => c + "=" + Binary(row, vars.Length)[i])) + "}";

    static int PatternCompare(string a, string b)
    {
        for (int i = 0; i < a.Length; i++)
        {
            int c = "10-".IndexOf(a[i]).CompareTo("10-".IndexOf(b[i]));
            if (c != 0) return c;
        }
        return 0;
    }

    static int Literals(string p) => p.Count(c => c != '-');

    static string Term(string pattern, string vars, bool clause)
    {
        var parts = vars.Select((c, i) => pattern[i] == '-' ? null : (pattern[i] == '0' ? "~" : "") + c).Where(s => s != null).ToList();
        return parts.Count == 0 ? clause ? "0" : "1" : string.Join(clause ? " | " : " & ", parts);
    }

    static string Form(List<string> patterns, string vars, bool clauses)
    {
        if (patterns.Count == 0) return clauses ? "1" : "0";
        return string.Join(clauses ? " & " : " | ", patterns.Select(p => clauses && patterns.Count >= 2 && Literals(p) >= 2 ? "(" + Term(p, vars, true) + ")" : Term(p, vars, clauses)));
    }

    static string Opposite(string p) => string.Concat(p.Select(c => c == '1' ? '0' : c == '0' ? '1' : '-'));

    static int[] Coefficients(int[] table)
    {
        int[] output = (int[])table.Clone();
        for (int bit = 1; bit < output.Length; bit <<= 1) for (int s = 0; s < output.Length; s++) if ((s & bit) != 0) output[s] ^= output[s ^ bit];
        return output;
    }

    record Implicant(string Pattern, int Mask, int Values, HashSet<int> Coverage);

    static void Implicants(int at, int n, int mask, int values, string prefix, List<Implicant> output, HashSet<int> allowed)
    {
        if (at == n)
        {
            HashSet<int> coverage = new();
            for (int row = 0; row < 1 << n; row++) if (((row ^ values) & mask) == 0)
            {
                if (!allowed.Contains(row)) return;
                coverage.Add(row);
            }
            output.Add(new(prefix, mask, values, coverage));
            return;
        }
        int bit = 1 << (n - 1 - at);
        Implicants(at + 1, n, mask | bit, values | bit, prefix + "1", output, allowed);
        Implicants(at + 1, n, mask | bit, values, prefix + "0", output, allowed);
        Implicants(at + 1, n, mask, values, prefix + "-", output, allowed);
    }

    static List<string> CoverPatterns(IEnumerable<Implicant> cover, bool pos)
    {
        List<string> patterns = cover.Select(p => pos ? Opposite(p.Pattern) : p.Pattern).ToList();
        patterns.Sort(PatternCompare);
        return patterns;
    }

    static int CoverLiterals(IEnumerable<Implicant> cover) => cover.Sum(p => Bits(p.Mask));

    static bool Better(List<Implicant> candidate, List<Implicant>? best, bool pos)
    {
        if (best == null || candidate.Count != best.Count) return best == null || candidate.Count < best.Count;
        int a = CoverLiterals(candidate), b = CoverLiterals(best);
        if (a != b) return a < b;
        List<string> x = CoverPatterns(candidate, pos), y = CoverPatterns(best, pos);
        for (int i = 0; i < x.Count; i++)
        {
            int c = PatternCompare(x[i], y[i]);
            if (c != 0) return c < 0;
        }
        return false;
    }

    static List<string> Minimize(string vars, int[] f, int[]? dc, bool pos)
    {
        int n = vars.Length;
        HashSet<int> on = new(), allowed = new();
        for (int r = 0; r < f.Length; r++)
        {
            if ((pos ? 1 - f[r] : f[r]) == 1 && (dc == null || dc[r] == 0)) on.Add(r);
            if (on.Contains(r) || dc != null && dc[r] == 1) allowed.Add(r);
        }
        List<Implicant> all = new();
        Implicants(0, n, 0, 0, "", all, allowed);
        HashSet<int> keys = new(all.Select(p => (p.Mask << 8) | p.Values));
        List<Implicant> primes = new();
        int[] stages = new int[n + 1], primeStages = new int[n + 1];
        foreach (Implicant p in all)
        {
            int stage = n - Bits(p.Mask);
            stages[stage]++;
            bool prime = true;
            for (int bit = 1; bit < 1 << n; bit <<= 1) if ((p.Mask & bit) != 0 && keys.Contains(((p.Mask ^ bit) << 8) | (p.Values & ~bit)))
            {
                prime = false;
                break;
            }
            if (prime)
            {
                primeStages[stage]++;
                if (p.Coverage.Overlaps(on)) primes.Add(p);
            }
        }
        primes.Sort((a, b) => PatternCompare(a.Pattern, b.Pattern));
        HashSet<Implicant> essentialSet = new();
        foreach (int r in on)
        {
            var covering = primes.Where(p => p.Coverage.Contains(r)).ToList();
            if (covering.Count == 1) essentialSet.Add(covering[0]);
        }
        var essential = primes.Where(essentialSet.Contains).ToList();
        var optional = primes.Where(p => !essentialSet.Contains(p)).ToList();
        List<Implicant>? best = null;
        for (int mask = 0; mask < 1 << optional.Count; mask++)
        {
            List<Implicant> candidate = new(essential);
            HashSet<int> covered = new();
            for (int i = 0; i < optional.Count; i++) if ((mask & 1 << i) != 0) candidate.Add(optional[i]);
            if (best != null && candidate.Count > best.Count) continue;
            foreach (Implicant p in candidate) covered.UnionWith(p.Coverage);
            if (on.IsSubsetOf(covered) && Better(candidate, best, pos)) best = candidate;
        }
        List<string> output = new();
        if (!pos)
        {
            for (int stage = 0; stage <= n; stage++)
            {
                output.Add($"stage {stage}: implicants {stages[stage]} primes {primeStages[stage]}");
                if (stage == n || stages[stage + 1] == 0) break;
            }
            output.Add("primes: " + (primes.Count == 0 ? "none" : string.Join(", ", CoverPatterns(primes, false).Select(p => Term(p, vars, false)))));
            output.Add("essential: " + (essential.Count == 0 ? "none" : string.Join(", ", CoverPatterns(essential, false).Select(p => Term(p, vars, false)))));
        }
        output.Add("minimal: " + Form(CoverPatterns(best!, pos), vars, pos));
        output.Add((pos ? "clauses " : "terms ") + best!.Count + " literals " + CoverLiterals(best));
        return output;
    }
    readonly record struct Clause(int Positive, int Negative)
    {
        public bool Subset(Clause other) => (Positive & other.Positive) == Positive && (Negative & other.Negative) == Negative;
        public Clause Union(Clause other) => new(Positive | other.Positive, Negative | other.Negative);
        public bool Tautology => (Positive & Negative) != 0;
        public string Pattern(string vars)
        {
            int positive = Positive, negative = Negative;
            return string.Concat(vars.Select(c => (positive & 1 << (c - 'A')) != 0 ? '1' : (negative & 1 << (c - 'A')) != 0 ? '0' : '-'));
        }
    }

    static HashSet<Clause> Tidy(HashSet<Clause> input)
    {
        HashSet<Clause> output = new();
        foreach (Clause c in input.Where(c => !c.Tautology).OrderBy(c => Bits(c.Positive | c.Negative))) if (!output.Any(e => e.Subset(c))) output.Add(c);
        return output;
    }

    HashSet<Clause> Clauses(Node n, Dictionary<int, HashSet<Clause>> memo)
    {
        if (memo.TryGetValue(n.Id, out var old)) return old;
        HashSet<Clause> result = new();
        if (n.Op == "0") result.Add(new(0, 0));
        else if (n.Op == "1")
        {
        }
        else if (n.Left == null) result.Add(new(1 << (n.Op[0] - 'A'), 0));
        else if (n.Op == "~") result.Add(new(0, 1 << (n.Left.Op[0] - 'A')));
        else
        {
            var a = Clauses(n.Left, memo);
            var b = Clauses(n.Right!, memo);
            if (n.Op == "&")
            {
                result.UnionWith(a);
                result.UnionWith(b);
            }
            else foreach (Clause x in a) foreach (Clause y in b)
            {
                Clause c = x.Union(y);
                if (!c.Tautology) result.Add(c);
            }
            result = Tidy(result);
        }
        memo[n.Id] = result;
        return result;
    }

    static List<string> ClausePatterns(HashSet<Clause> clauses, string vars)
    {
        List<string> patterns = clauses.Select(c => c.Pattern(vars)).ToList();
        patterns.Sort(PatternCompare);
        return patterns;
    }

    record Decision(int Variable, int Low, int High);

    static int Bdd(int[] values, int from, int count, int variable, List<Decision> nodes, Dictionary<Decision, int> index)
    {
        if (count == 1) return values[from];
        int low = Bdd(values, from, count / 2, variable + 1, nodes, index), high = Bdd(values, from + count / 2, count / 2, variable + 1, nodes, index);
        if (low == high) return low;
        Decision d = new(variable, low, high);
        if (index.TryGetValue(d, out int old)) return old;
        int id = nodes.Count + 2;
        nodes.Add(d);
        index[d] = id;
        return id;
    }

    static string[] Words(string text) => text.Split(' ', StringSplitOptions.RemoveEmptyEntries);

    void Define(string name, Node formula, List<string> output)
    {
        output.Add((definitions.ContainsKey(name) ? "redefined " : "defined ") + name + " = " + Print(formula));
        definitions[name] = formula;
    }

    List<string> Command(string line)
    {
        int space = line.IndexOf(' ');
        string command = space < 0 ? line : line[..space], arg = space < 0 ? "" : line[(space + 1)..];
        HashSet<string> single = new(StringComparer.Ordinal) { "PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "MINIMIZE", "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "PROPS", "BDD", "CLAUSES", "DP" };
        HashSet<string> split = new(StringComparer.Ordinal) { "RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES" };
        if (!single.Contains(command) && !split.Contains(command) && !new[] { "DEF", "DEFSUM", "DEL", "LIST" }.Contains(command)) Fail("unknown command " + command);
        if (command == "LIST" && space >= 0) Fail("unexpected argument");
        if (command != "LIST" && space < 0) Fail("missing argument");
        int semicolon = arg.IndexOf(';');
        if (split.Contains(command) && semicolon < 0) Fail("missing ';'");
        List<string> output = new();
        if (command == "LIST")
        {
            output.Add("names: " + definitions.Count);
            foreach (var e in definitions) output.Add(e.Key + " = " + Print(e.Value));
            return output;
        }
        if (command == "DEL")
        {
            if (!ValidName(arg)) Fail("invalid name '" + arg + "'");
            if (!definitions.ContainsKey(arg)) Fail("undefined name '" + arg + "'");
            definitions.Remove(arg);
            return new() { "deleted " + arg };
        }
        if (command == "DEF")
        {
            int at = arg.IndexOf(' ');
            if (at < 0) Fail("missing argument");
            string name = arg[..at];
            if (!ValidName(name)) Fail("invalid name '" + name + "'");
            Node formula = Parse(arg[(at + 1)..], name.Length + 6);
            Define(name, formula, output);
            return output;
        }
        if (command == "DEFSUM")
        {
            if (semicolon < 0) Fail("missing ';'");
            string[] front = Words(arg[..semicolon]), back = Words(arg[(semicolon + 1)..]);
            if (front.Length == 0) Fail("missing argument");
            if (!ValidName(front[0])) Fail("invalid name '" + front[0] + "'");
            if (front.Length == 1) Fail("bad variable list");
            for (int i = 1; i < front.Length; i++) if (front[i].Length != 1 || !Upper(front[i][0]) || i > 1 && StringComparer.Ordinal.Compare(front[i - 1], front[i]) >= 0) Fail("bad variable list");
            int n = front.Length - 1;
            if (n >= 9) Fail("too many variables: " + n);
            int previous = -1;
            Node? result = null;
            foreach (string word in back)
            {
                if (word.Length == 0 || word.Length > 1 && word[0] == '0' || !word.All(Digit)) Fail("bad minterm '" + word + "'");
                int row = int.Parse(word);
                if (row >= 1 << n || row <= previous) Fail("bad minterm '" + word + "'");
                previous = row;
                Node? term = null;
                for (int i = 0; i < n; i++)
                {
                    Node literal = Make(front[i + 1]);
                    if ((row & 1 << (n - i - 1)) == 0) literal = Not(literal);
                    term = term == null ? literal : Make("&", term, literal);
                }
                result = result == null ? term : Make("|", result, term);
            }
            Define(front[0], result ?? Make("0"), output);
            return output;
        }
        int start = command.Length + 2;
        string first = split.Contains(command) ? arg[..semicolon] : arg, second = split.Contains(command) ? arg[(semicolon + 1)..] : "";
        Node f = Parse(first, start);
        Node? g = null;
        if (command is "MINDC" or "EQUIV" or "IMPLIES") g = Parse(second, start + semicolon + 1);
        if (command == "RESTRICT")
        {
            string[] assignments = Words(second);
            if (assignments.Length == 0) Fail("missing assignment");
            Dictionary<char, int> values = new();
            foreach (string a in assignments)
            {
                if (a.Length != 3 || !Upper(a[0]) || a[1] != '=' || !"01".Contains(a[2])) Fail("bad assignment '" + a + "'");
                if (!values.TryAdd(a[0], a[2] - '0')) Fail("duplicate variable " + a[0]);
            }
            return new() { "restricted: " + Print(Simplify(f, values, new())) };
        }
        if (command == "COFACTOR")
        {
            string[] x = Words(second);
            if (x.Length != 1 || x[0].Length != 1 || !Upper(x[0][0])) Fail("bad variable");
            char c = x[0][0];
            Node f1 = Simplify(f, new() { [c] = 1 }, new()), f0 = Simplify(f, new() { [c] = 0 }, new());
            return new() { $"cofactor {c}=1: {Print(f1)}", $"cofactor {c}=0: {Print(f0)}", "difference: " + Print(SimplifyBinary("^", f1, f0)) };
        }
        string vars = Variables(f.Variables | (g?.Variables ?? 0));
        int variableCount = vars.Length;
        if (command == "PRINT") return new() { "formula: " + Print(f), "variables: " + (vars.Length == 0 ? "none" : string.Join(" ", vars.ToCharArray())), $"size {Size(f)} depth {Depth(f)}" };
        if (command == "NNF") return new() { "nnf: " + Print(Nnf(f, true)) };
        if (command == "DUAL") return new() { "dual: " + Print(Dual(f, new())) };
        if (command == "SIMPLIFY") return new() { "simplified: " + Print(Simplify(f, new(), new())) };
        if (command is "CLAUSES" or "DP")
        {
            var clauses = Clauses(Nnf(f, true), new());
            if (command == "CLAUSES") return new() { "clauses: " + Form(ClausePatterns(clauses, vars), vars, true) };
            output.Add("start: clauses " + clauses.Count);
            foreach (char c in vars)
            {
                if (clauses.Count == 0 || clauses.Contains(new(0, 0))) break;
                int bit = 1 << (c - 'A');
                var positive = clauses.Where(x => (x.Positive & bit) != 0).ToList();
                var negative = clauses.Where(x => (x.Negative & bit) != 0).ToList();
                HashSet<Clause> resolvents = new(), next = new();
                foreach (Clause a in positive) foreach (Clause b in negative)
                {
                    Clause r = new((a.Positive | b.Positive) & ~bit, (a.Negative | b.Negative) & ~bit);
                    if (!r.Tautology) resolvents.Add(r);
                }
                foreach (Clause a in clauses) if (((a.Positive | a.Negative) & bit) == 0) next.Add(a);
                next.UnionWith(resolvents);
                clauses = Tidy(next);
                output.Add($"eliminate {c}: resolvents {resolvents.Count} clauses {clauses.Count}");
            }
            output.Add("result: " + (clauses.Contains(new(0, 0)) ? "unsatisfiable" : "satisfiable"));
            return output;
        }
        if (variableCount >= 9) Fail("too many variables: " + variableCount);
        int[] table = Truth(f, vars);
        int[]? other = g == null ? null : Truth(g, vars);
        int rows = table.Length;
        if (command is "MINIMIZE" or "MINDC" or "MINPOS") return Minimize(vars, table, other, command == "MINPOS");
        switch (command)
        {
            case "TABLE":
                output.Add((variableCount == 0 ? "" : string.Join(" ", vars.ToCharArray()) + " ") + "| F");
                for (int r = 0; r < rows; r++) output.Add((variableCount == 0 ? "" : string.Join(" ", Binary(r, variableCount).ToCharArray()) + " ") + "| " + table[r]);
                break;
            case "MINTERMS":
            case "MAXTERMS":
            case "DNF":
            case "CNF":
            {
                bool positive = command is "MINTERMS" or "DNF";
                List<string> patterns = new(), numbers = new();
                for (int r = 0; r < rows; r++) if (table[r] == (positive ? 1 : 0))
                {
                    string p = Binary(r, variableCount);
                    patterns.Add(positive ? p : Opposite(p));
                    numbers.Add(r.ToString());
                }
                output.Add(command.ToLowerInvariant() + ": " + (command is "DNF" or "CNF" ? Form(patterns, vars, !positive) : numbers.Count == 0 ? "none" : string.Join(" ", numbers)));
                break;
            }
            case "ANF":
            {
                int[] coeff = Coefficients(table);
                List<string> patterns = new();
                for (int r = 0; r < rows; r++) if (coeff[r] == 1) patterns.Add(Binary(r, variableCount).Replace('0', '-'));
                patterns.Sort((a, b) => Literals(a) != Literals(b) ? Literals(a).CompareTo(Literals(b)) : PatternCompare(a, b));
                output.Add("anf: " + (patterns.Count == 0 ? "0" : string.Join(" ^ ", patterns.Select(p => Term(p, vars, false)))));
                break;
            }
            case "SAT":
            case "TAUT":
            {
                bool sat = command == "SAT";
                int firstRow = -1;
                for (int r = 0; r < rows; r++) if (table[r] == (sat ? 1 : 0))
                {
                    firstRow = r;
                    break;
                }
                output.Add(firstRow < 0 ? sat ? "unsatisfiable" : "tautology" : (sat ? "satisfiable: " : "not a tautology: ") + Assignment(firstRow, vars));
                break;
            }
            case "COUNT":
                output.Add($"models: {table.Sum()} of {rows}");
                break;
            case "EQUIV":
            case "IMPLIES":
            {
                bool equivalent = command == "EQUIV";
                int firstRow = -1;
                for (int r = 0; r < rows; r++) if (equivalent ? table[r] != other![r] : table[r] == 1 && other![r] == 0)
                {
                    firstRow = r;
                    break;
                }
                output.Add(firstRow < 0 ? equivalent ? "equivalent" : "implies" : equivalent ? $"not equivalent: {Assignment(firstRow, vars)} f={table[firstRow]} g={other![firstRow]}" : "does not imply: " + Assignment(firstRow, vars));
                break;
            }
            case "PROPS":
            {
                List<char> dependencies = new();
                bool selfDual = true, monotone = true, linear = true, symmetric = true;
                for (int i = 0; i < variableCount; i++)
                {
                    int bit = 1 << (variableCount - 1 - i);
                    for (int r = 0; r < rows; r++) if (table[r] != table[r ^ bit])
                    {
                        dependencies.Add(vars[i]);
                        break;
                    }
                }
                int[] coeff = Coefficients(table), weights = Enumerable.Repeat(-1, variableCount + 1).ToArray();
                for (int r = 0; r < rows; r++)
                {
                    selfDual &= table[r] != table[rows - 1 - r];
                    if (coeff[r] == 1 && Bits(r) > 1) linear = false;
                    int weight = Bits(r);
                    if (weights[weight] >= 0 && weights[weight] != table[r]) symmetric = false;
                    weights[weight] = table[r];
                    for (int bit = 1; bit < rows; bit <<= 1) if ((r & bit) == 0 && table[r] > table[r | bit]) monotone = false;
                }
                output.Add("depends: " + (dependencies.Count == 0 ? "none" : string.Join(" ", dependencies)));
                string[] labels = { "zero-preserving", "one-preserving", "self-dual", "monotone", "linear", "symmetric" };
                bool[] values = { table[0] == 0, table[rows - 1] == 1, selfDual, monotone, linear, symmetric };
                for (int i = 0; i < labels.Length; i++) output.Add(labels[i] + ": " + (values[i] ? "yes" : "no"));
                break;
            }
            case "KMAP":
            {
                int n = variableCount;
                if (n < 2 || n > 4) Fail("kmap needs 2 to 4 variables");
                int p = n / 2, q = n - p;
                StringBuilder header = new(vars[..p] + "\\" + vars[p..]);
                for (int i = 0; i < 1 << q; i++) header.Append(' ').Append(Binary(i ^ i / 2, q));
                output.Add(header.ToString());
                for (int i = 0; i < 1 << p; i++)
                {
                    int r = i ^ i / 2;
                    StringBuilder row = new(Binary(r, p) + new string(' ', q + 1));
                    for (int j = 0; j < 1 << q; j++) row.Append(' ', q).Append(table[(r << q) | (j ^ j / 2)]);
                    output.Add(row.ToString());
                }
                break;
            }
            case "BDD":
            {
                List<Decision> decisions = new();
                int root = Bdd(table, 0, rows, 0, decisions, new());
                int[] paths = new int[decisions.Count + 2];
                paths[1] = 1;
                output.Add("nodes: " + decisions.Count);
                for (int i = 0; i < decisions.Count; i++)
                {
                    Decision d = decisions[i];
                    paths[i + 2] = paths[d.Low] + paths[d.High];
                    output.Add($"{i + 2} = ite({vars[d.Variable]}, {d.High}, {d.Low})");
                }
                output.Add("root: " + root);
                output.Add("paths: " + paths[root]);
                break;
            }
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program workbench = new();
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try
            {
                foreach (string output in workbench.Command(line)) Console.WriteLine(output);
            }
            catch (Problem problem)
            {
                Console.WriteLine(problem.Message);
            }
        }
    }
}
