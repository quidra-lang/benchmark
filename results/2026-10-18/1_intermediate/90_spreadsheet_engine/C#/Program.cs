using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
#nullable disable

class Program {
    sealed record Expr(char Kind, int N, int Row, int Flags, string Text, Expr A, Expr B,
                       List<Expr> Args);
    static bool Matches(string value, string pattern) => Regex.IsMatch(value,
                                                                       "\\A(?:" + pattern + ")\\z");
    static Expr Node(char k, int n, string s, Expr a, Expr b, List<Expr> args) {
        return new Expr(k, n, 0, 0, s, a, b, args);
    }
    static Expr Leaf(char k, int n, string s) {
        return Node(k, n, s, null, null, []);
    }
    static Expr Num(int n) {
        return Leaf('N', n, "");
    }
    static Expr Text(string s) {
        return Leaf('S', 0, s);
    }
    static Expr Error(string s) {
        return Leaf('E', 0, s);
    }
    static Expr Ref(int c, int r, int f) {
        return new Expr('R', c, r, f, "", null, null, []);
    }
    static readonly Expr INVALID = Leaf('X', 0, "");
    static int Id(Expr r) {
        return r.Row * 26 + r.N;
    }
    static string Label(int i) {
        return "" + (char)('A' + i % 26) + (i / 26 + 1);
    }
    static bool Inside(Expr r) {
        return r.N >= 0 && r.N < 26 && r.Row >= 0 && r.Row < 99;
    }
    static Expr Range(Expr a, Expr b) {
        int c = a.N, d = b.N, r = a.Row, t = b.Row, ac = a.Flags & 1, bc = b.Flags & 1,
            ar = a.Flags & 2, br = b.Flags & 2;
        if (c > d) {
            int z = c;
            c = d;
            d = z;
            z = ac;
            ac = bc;
            bc = z;
        }
        if (r > t) {
            int z = r;
            r = t;
            t = z;
            z = ar;
            ar = br;
            br = z;
        }
        return Node('G', 0, "", Ref(c, r, ac | ar), Ref(d, t, bc | br), []);
    }
    static Expr Address(string s) {
        if (!Matches(s, "[A-Z][1-9][0-9]?"))
            throw new ArgumentException("bad address");
        return Ref(s[0] - 'A', int.Parse(s.Substring(1)) - 1, 0);
    }
    static Expr Area(string s) {
        int p = s.IndexOf(':');
        if (p < 0) {
            Expr a = Address(s);
            return Range(a, a);
        }
        Expr a = Address(s.Substring(0, p)), b = Address(s.Substring(p + 1));
        return Range(a, b);
    }
    static List<int> Cells(Expr g) {
        List<int> resultRows = new();
        for (int r = g.A.Row; r <= g.B.Row; r++)
            for (int c = g.A.N; c <= g.B.N; c++)
                resultRows.Add(r * 26 + c);
        return resultRows;
    }
    static bool Contains(Expr g, Expr r) {
        return r.N >= g.A.N && r.N <= g.B.N && r.Row >= g.A.Row && r.Row <= g.B.Row;
    }
    static readonly List<HashSet<string>> LEVELS = [
        new HashSet<string> { "=", "<>", "<", "<=", ">", ">=" }, new HashSet<string> { "&" },
        new HashSet<string> { "+", "-" }, new HashSet<string> { "*", "/" }
    ];
    static int Precedence(string op) {
        for (int i = 0; i < 4; i++)
            if (LEVELS[i].Contains(op))
                return i;
        return -1;
    }
    record Token(Expr Value, int Position);
    sealed class Parser {
        readonly List<Token> tokens = new();
        int at;
        void Syntax(int p) {
            throw new ArgumentException("syntax error at " + p);
        }
        public Parser(string s) {
            for (int i = 1; i < s.Length;) {
                int p = i + 1;
                char ch = s[i];
                if (ch == ' ') {
                    i++;
                    continue;
                }
                Expr x;
                if (ch >= '0' && ch <= '9') {
                    int j = i;
                    while (j < s.Length && char.IsDigit(s[j]))
                        j++;
                    if (j - i >= 10)
                        Syntax(p);
                    x = Num(int.Parse(s.Substring(i, j - i)));
                    i = j;
                } else if (ch == '"') {
                    int j = s.IndexOf('"', i + 1);
                    if (j < 0)
                        Syntax(p);
                    x = Text(s.Substring(i + 1, j - i - 1));
                    i = j + 1;
                } else if (char.IsLetter(ch) || ch == '$') {
                    int j = i;
                    while (j < s.Length && (char.IsLetterOrDigit(s[j]) || s[j] == '$'))
                        j++;
                    string w = s.Substring(i, j - i).ToUpperInvariant();
                    i = j;
                    Match m = Regex.Match(w, "\\A(\\$?)([A-Z])(\\$?)([1-9][0-9]?)\\z");
                    if (m.Success)
                        x = Ref(m.Groups[2].Value[0] - 'A', int.Parse(m.Groups[4].Value) - 1,
                                (m.Groups[1].Value.Length == 0 ? 0 : 1) |
                                    (m.Groups[3].Value.Length == 0 ? 0 : 2));
                    else if (Matches(w, "[A-Z][A-Z0-9]*"))
                        x = Leaf(s.Substring(j).TrimStart().StartsWith("(") ? 'C' : 'W', 0, w);
                    else {
                        Syntax(p);
                        return;
                    }
                } else {
                    string op = s.Substring(i, Math.Min(2, s.Length - i));
                    if (!new HashSet<string> { "<>", "<=", ">=" }.Contains(op))
                        op = "" + ch;
                    if ("+-*/&(),:=<>".IndexOf(ch) < 0)
                        Syntax(p);
                    x = Leaf('T', 0, op);
                    i += op.Length;
                }
                tokens.Add(new Token(x, p));
            }
            tokens.Add(new Token(Leaf('Z', 0, ""), s.Length + 1));
        }
        bool Take(string op) {
            Expr x = tokens[at].Value;
            if (x.Kind == 'T' && x.Text.Equals(op)) {
                at++;
                return true;
            }
            return false;
        }
        void Expect(string op) {
            if (!Take(op))
                Syntax(tokens[at].Position);
        }
        Expr Expression(int level) {
            if (level == 4)
                return Primary();
            Expr a = Expression(level + 1);
            while (tokens[at].Value.Kind == 'T' && LEVELS[level].Contains(tokens[at].Value.Text)) {
                string op = tokens[at++].Value.Text;
                a = Node('B', 0, op, a, Expression(level + 1), []);
            }
            return a;
        }
        Expr Primary() {
            if (Take("-"))
                return Node('U', 0, "", Primary(), null, []);
            Token t = tokens[at++];
            Expr x = t.Value;
            if (x.Kind == 'N' || x.Kind == 'S' || x.Kind == 'W')
                return x;
            if (x.Kind == 'R') {
                if (!Take(":"))
                    return x;
                if (tokens[at].Value.Kind != 'R')
                    Syntax(tokens[at].Position);
                return Range(x, tokens[at++].Value);
            }
            if (x.Kind == 'C') {
                Expect("(");
                List<Expr> args = new();
                if (!Take(")")) {
                    args.Add(Expression(0));
                    while (Take(","))
                        args.Add(Expression(0));
                    Expect(")");
                }
                return Node('F', 0, x.Text, null, null, args);
            }
            if (x.Kind == 'T' && x.Text.Equals("(")) {
                Expr a = Expression(0);
                Expect(")");
                return a;
            }
            Syntax(t.Position);
            return null;
        }
        public Expr Parse() {
            Expr x = Expression(0);
            if (tokens[at].Value.Kind != 'Z')
                Syntax(tokens[at].Position);
            return x;
        }
    }
    static string Canonical(Expr x) {
        switch (x.Kind) {
        case 'N':
            return "" + x.N;
        case 'S':
            return "\"" + x.Text + "\"";
        case 'W':
            return x.Text;
        case 'X':
            return "#REF!";
        case 'R':
            return (x.Flags % 2 != 0 ? "$" : "") + (char)('A' + x.N) +
                   ((x.Flags & 2) != 0 ? "$" : "") + (x.Row + 1);
        case 'G':
            return Canonical(x.A) + ":" + Canonical(x.B);
        case 'F': {
            return x.Text + "(" + string.Join(",", x.Args.Select(Canonical)) + ")";
        }
        case 'U':
            return "-" + (x.A.Kind == 'B' ? "(" + Canonical(x.A) + ")" : Canonical(x.A));
        case 'B': {
            string a = Canonical(x.A), b = Canonical(x.B);
            if (x.A.Kind == 'B' && Precedence(x.A.Text) < Precedence(x.Text))
                a = "(" + a + ")";
            if (x.B.Kind == 'B' && Precedence(x.B.Text) <= Precedence(x.Text))
                b = "(" + b + ")";
            return a + x.Text + b;
        }
        default:
            throw new InvalidOperationException();
        }
    }
    static string Display(Expr x) {
        return x == null ? "" : x.Kind == 'N' ? "" + x.N : x.Text;
    }
    static string Notation(Expr x) {
        return x == null       ? "(empty)"
               : x.Kind == '=' ? "=" + Canonical(x.A)
               : x.Kind == 'S' ? "\"" + x.Text + "\""
                               : Display(x);
    }
    static Expr ToNumber(Expr x) {
        return x == null ? Num(0) : x.Kind == 'S' || x.Kind == 'G' ? Error("#VALUE!") : x;
    }
    static Expr ToText(Expr x) {
        return x == null       ? Text("")
               : x.Kind == 'N' ? Text("" + x.N)
               : x.Kind == 'G' ? Error("#VALUE!")
                               : x;
    }
    static Expr Rewrite(Expr x, Func<Expr, Expr> f) {
        if (x == null)
            return null;
        if (x.Kind == 'R' || x.Kind == 'G')
            return f(x);
        Expr a = Rewrite(x.A, f), b = Rewrite(x.B, f);
        List<Expr> args = new();
        bool changed = a != x.A || b != x.B;
        foreach (Expr old in x.Args) {
            Expr v = Rewrite(old, f);
            changed |= v != old;
            args.Add(v);
        }
        return changed ? Node(x.Kind, x.N, x.Text, a, b, args) : x;
    }
    static void Dependencies(Expr x, SortedSet<int> resultRows) {
        if (x == null)
            return;
        if (x.Kind == 'R')
            resultRows.Add(Id(x));
        else if (x.Kind == 'G')
            resultRows.UnionWith(Cells(x));
        else {
            Dependencies(x.A, resultRows);
            Dependencies(x.B, resultRows);
            foreach (Expr a in x.Args)
                Dependencies(a, resultRows);
        }
    }
    record History(string Name, Expr[] Contents);
    sealed class Sheet {
        Expr[] contents = new Expr[2574], values = new Expr[2574];
        List<SortedSet<int>> deps = new();
        List<History> history = new();
        public Sheet() {
            for (int i = 0; i < 2574; i++)
                deps.Add(new());
        }
        Expr Evaluate(Expr x) {
            if (x.Kind == 'N' || x.Kind == 'S' || x.Kind == 'G')
                return x;
            if (x.Kind == 'R')
                return values[Id(x)];
            if (x.Kind == 'W')
                return Error("#NAME?");
            if (x.Kind == 'X')
                return Error("#REF!");
            if (x.Kind == 'U') {
                Expr a = ToNumber(Evaluate(x.A));
                return a.Kind == 'E' ? a : Num(-a.N);
            }
            if (x.Kind == 'B') {
                Expr a = Evaluate(x.A), b = Evaluate(x.B);
                if (a != null && a.Kind == 'E')
                    return a;
                if (b != null && b.Kind == 'E')
                    return b;
                string op = x.Text;
                if (Precedence(op) == 0) {
                    if ((a != null && a.Kind == 'G') || (b != null && b.Kind == 'G'))
                        return Error("#VALUE!");
                    bool strings = (a != null && a.Kind == 'S') || (b != null && b.Kind == 'S');
                    if (a == null)
                        a = strings ? Text("") : Num(0);
                    if (b == null)
                        b = strings ? Text("") : Num(0);
                    int c = a.Kind != b.Kind ? (a.Kind == 'N' ? -1 : 1)
                            : a.Kind == 'N'  ? a.N.CompareTo(b.N)
                                             : string.CompareOrdinal(a.Text, b.Text);
                    bool yes = op switch { "=" => c == 0,  "<>" => c != 0, "<" => c < 0,
                                           "<=" => c <= 0, ">" => c > 0,
                                           _ => c >= 0 };
                    return Num(yes ? 1 : 0);
                }
                a = op.Equals("&") ? ToText(a) : ToNumber(a);
                b = op.Equals("&") ? ToText(b) : ToNumber(b);
                if (a.Kind == 'E')
                    return a;
                if (b.Kind == 'E')
                    return b;
                return op switch { "&" => Text(a.Text + b.Text), "+" => Num(a.N + b.N),
                                   "-" => Num(a.N - b.N), "*" => Num(a.N * b.N),
                                   _ => b.N == 0 ? Error("#DIV/0!") : Num(a.N / b.N) };
            }
            string name = x.Text;
            List<Expr> args = x.Args;
            if (new HashSet<string> { "SUM", "MIN", "MAX", "COUNT", "AVERAGE", "AND", "OR",
                                      "CONCAT" }
                    .Contains(name)) {
                if (args.Count == 0)
                    return Error("#VALUE!");
                List<Expr> items = new();
                List<int> ns = new();
                foreach (Expr arg in args) {
                    Expr v = Evaluate(arg);
                    if (v != null && v.Kind == 'G') {
                        foreach (int i in Cells(v))
                            items.Add(values[i]);
                    } else
                        items.Add(v);
                }
                foreach (Expr v in items)
                    if (v != null && v.Kind == 'N')
                        ns.Add(v.N);
                if (name.Equals("COUNT"))
                    return Num(ns.Count);
                foreach (Expr v in items)
                    if (v != null && v.Kind == 'E')
                        return v;
                if (name.Equals("CONCAT")) {
                    StringBuilder s = new StringBuilder();
                    foreach (Expr v in items)
                        s.Append(ToText(v).Text);
                    return Text(s.ToString());
                }
                int sum = 0;
                foreach (int n in ns)
                    sum += n;
                if (name.Equals("SUM"))
                    return Num(sum);
                if (name.Equals("MIN"))
                    return Num(ns.Count == 0 ? 0 : ns.Min());
                if (name.Equals("MAX"))
                    return Num(ns.Count == 0 ? 0 : ns.Max());
                if (ns.Count == 0)
                    return Error(name.Equals("AVERAGE") ? "#DIV/0!" : "#VALUE!");
                if (name.Equals("AVERAGE"))
                    return Num(sum / ns.Count);
                bool result = name.Equals("AND");
                foreach (int n in ns)
                    result = name.Equals("AND") ? result && n != 0 : result || n != 0;
                return Num(result ? 1 : 0);
            }
            if (name.Equals("IF")) {
                if (args.Count != 2 && args.Count != 3)
                    return Error("#VALUE!");
                Expr c = ToNumber(Evaluate(args[0]));
                if (c.Kind == 'E')
                    return c;
                return c.N != 0 ? Evaluate(args[1]) : args.Count == 3 ? Evaluate(args[2]) : Num(0);
            }
            if (!new HashSet<string> { "ABS", "NOT", "LEN" }.Contains(name))
                return Error("#NAME?");
            if (args.Count != 1)
                return Error("#VALUE!");
            Expr scalar = Evaluate(args[0]);
            scalar = name.Equals("LEN") ? ToText(scalar) : ToNumber(scalar);
            return scalar.Kind == 'E' ? scalar
                                      : Num(name.Equals("LEN")   ? scalar.Text.Length
                                            : name.Equals("ABS") ? Math.Abs(scalar.N)
                                            : scalar.N == 0      ? 1
                                                                 : 0);
        }
        void Recalculate() {
            for (int i = 0; i < 2574; i++) {
                deps[i].Clear();
                if (contents[i] != null && contents[i].Kind == '=') {
                    Dependencies(contents[i].A, deps[i]);
                    values[i] = null;
                } else
                    values[i] = contents[i];
            }
            int serial = 0;
            int[] indices = new int[2574], low = new int[2574];
            Array.Fill(indices, -1);
            bool[] on = new bool[2574], cyclic = new bool[2574], done = new bool[2574];
            Stack<int> stack = new();
            void Visit(int i) {
                indices[i] = low[i] = serial++;
                stack.Push(i);
                on[i] = true;
                foreach (int j in deps[i])
                    if (contents[j] != null && contents[j].Kind == '=') {
                        if (indices[j] < 0) {
                            Visit(j);
                            low[i] = Math.Min(low[i], low[j]);
                        } else if (on[j])
                            low[i] = Math.Min(low[i], indices[j]);
                    }
                if (low[i] == indices[i]) {
                    List<int> part = new();
                    int j;
                    do {
                        j = stack.Pop();
                        on[j] = false;
                        part.Add(j);
                    } while (j != i);
                    if (part.Count > 1 || deps[i].Contains(i))
                        foreach (int k in part)
                            cyclic[k] = true;
                }
            }
            void Calculate(int i) {
                if (contents[i] == null || contents[i].Kind != '=' || done[i])
                    return;
                done[i] = true;
                if (cyclic[i]) {
                    values[i] = Error("#CYCLE!");
                    return;
                }
                foreach (int j in deps[i])
                    Calculate(j);
                Expr v = Evaluate(contents[i].A);
                values[i] = v == null ? Num(0) : v.Kind == 'G' ? Error("#VALUE!") : v;
            }
            for (int i = 0; i < 2574; i++)
                if (contents[i] != null && contents[i].Kind == '=' && indices[i] < 0)
                    Visit(i);
            for (int i = 0; i < 2574; i++)
                Calculate(i);
        }
        int Replace(Expr[] next) {
            Expr[] old = values;
            values = new Expr[2574];
            contents = next;
            Recalculate();
            int count = 0;
            for (int i = 0; i < 2574; i++)
                if (!Notation(old[i]).Equals(Notation(values[i])))
                    count++;
            return count;
        }
        string Describe(int i) {
            return Label(i) + ": " + Notation(contents[i]) + " -> " + Notation(values[i]);
        }
        string Formatted(ICollection<int> xs) {
            return xs.Count == 0 ? "none" : string.Join(",", xs.Select(Label));
        }
        public List<string> Execute(string line) {
            int p = line.IndexOf(' ');
            string name = p < 0 ? line : line.Substring(0, p),
                   rest = p < 0 ? "" : line.Substring(p + 1);
            if (name.Equals("SHOW"))
                return [Describe(Id(Address(rest)))];
            if (name.Equals("LIST")) {
                List<string> resultRows = new();
                for (int i = 0; i < 2574; i++)
                    if (contents[i] != null)
                        resultRows.Add(Describe(i));
                return resultRows.Count == 0 ?["(no cells)"] : resultRows;
            }
            if (name.Equals("DEPS")) {
                int i = Id(Address(rest));
                SortedSet<int> ds = new();
                for (int j = 0; j < 2574; j++)
                    if (deps[j].Contains(i))
                        ds.Add(j);
                return
                    [rest + ": precedents=" + Formatted(deps[i]) + " dependents=" + Formatted(ds)];
            }
            if (name.Equals("PRINT")) {
                Expr g = Area(rest);
                int rw = ("" + (g.B.Row + 1)).Length;
                List<int> widths = new();
                string sep = "+" + new string('-', rw) + "+",
                       header = "|" + new string(' ', rw) + "|";
                for (int c = g.A.N; c <= g.B.N; c++) {
                    int w = 1;
                    for (int r = g.A.Row; r <= g.B.Row; r++)
                        w = Math.Max(w, Display(values[r * 26 + c]).Length);
                    widths.Add(w);
                    sep += new string('-', w) + "+";
                    header += (char)('A' + c) + new string(' ', w - 1) + "|";
                }
                List<string> resultRows = new List<string>([sep, header, sep]);
                for (int r = g.A.Row; r <= g.B.Row; r++) {
                    string s = "" + (r + 1), row = "|" + new string(' ', rw - s.Length) + s + "|";
                    for (int j = 0; j < widths.Count; j++) {
                        Expr v = values[r * 26 + g.A.N + j];
                        s = Display(v);
                        string pad = new string(' ', widths[j] - s.Length);
                        row += (v != null && v.Kind == 'N' ? pad + s : s + pad) + "|";
                    }
                    resultRows.Add(row);
                }
                resultRows.Add(sep);
                return resultRows;
            }
            if (name.Equals("UNDO")) {
                if (history.Count == 0)
                    throw new ArgumentException("nothing to undo");
                History e = history[^1];
                history.RemoveAt(history.Count - 1);
                return ["UNDO " + e.Name + " changed=" + Replace(e.Contents)];
            }
            Expr[] next = (Expr[])contents.Clone();
            int target = -1;
            if (name.Equals("SET")) {
                p = rest.IndexOf(' ');
                target = Id(Address(rest.Substring(0, p)));
                string s = rest.Substring(p + 1);
                if (s.StartsWith("="))
                    next[target] = Node('=', 0, "", new Parser(s).Parse(), null, []);
                else if (Matches(s, "\"[^\"]*\""))
                    next[target] = Text(s.Substring(1, s.Length - 2));
                else if (Matches(s, "0|-?[1-9][0-9]{0,8}"))
                    next[target] = Num(int.Parse(s));
                else
                    throw new ArgumentException("bad value");
            } else if (name.Equals("CLEAR")) {
                foreach (int i in Cells(Area(rest)))
                    next[i] = null;
            } else if (name.Equals("COPY") || name.Equals("MOVE")) {
                p = rest.IndexOf(' ');
                Expr source = Area(rest.Substring(0, p)), dest = Address(rest.Substring(p + 1));
                int dc = dest.N - source.A.N, dr = dest.Row - source.A.Row;
                Expr Shift(Expr r, bool relative) {
                    return Ref(r.N + (relative && (r.Flags & 1) != 0 ? 0 : dc),
                               r.Row + (relative && (r.Flags & 2) != 0 ? 0 : dr), r.Flags);
                }
                Expr destination = Range(Shift(source.A, false), Shift(source.B, false));
                if (!Inside(destination.A) || !Inside(destination.B))
                    throw new ArgumentException("out of grid");
                Func<Expr, Expr> transform = x => {
                    if (x.Kind == 'R') {
                        if (name.Equals("COPY")) {
                            Expr r = Shift(x, true);
                            return Inside(r) ? r : INVALID;
                        }
                        return Contains(source, x)        ? Shift(x, false)
                               : Contains(destination, x) ? INVALID
                                                          : x;
                    }
                    if (name.Equals("MOVE") && !(Contains(source, x.A) && Contains(source, x.B)))
                        return x;
                    Expr a = Shift(x.A, name.Equals("COPY")), b = Shift(x.B, name.Equals("COPY"));
                    return Inside(a) && Inside(b) ? Range(a, b) : INVALID;
                };
                if (name.Equals("MOVE"))
                    for (int i = 0; i < 2574; i++)
                        next[i] = Rewrite(next[i], transform);
                List<int> ids = Cells(source);
                List<Expr> moving = new();
                foreach (int i in ids)
                    moving.Add(name.Equals("COPY") ? Rewrite(contents[i], transform) : next[i]);
                if (name.Equals("MOVE"))
                    foreach (int i in ids)
                        next[i] = null;
                for (int j = 0; j < ids.Count; j++)
                    next[ids[j] + dr * 26 + dc] = moving[j];
            } else if (new HashSet<string> { "INSERTROW", "DELETEROW", "INSERTCOL", "DELETECOL" }
                           .Contains(name)) {
                bool row = name.EndsWith("ROW"), insert = name.StartsWith("INSERT");
                if (!Matches(rest, row ? "[1-9][0-9]?" : "[A-Z]"))
                    throw new ArgumentException("bad address");
                int at = row ? int.Parse(rest) - 1 : rest[0] - 'A', limit = row ? 99 : 26;
                int Axis(Expr x) {
                    return row ? x.Row : x.N;
                }
                Expr Change(Expr x, int v) {
                    return Ref(row ? x.N : v, row ? v : x.Row, x.Flags);
                }
                if (insert)
                    for (int i = 0; i < 2574; i++)
                        if (contents[i] != null && (row ? i / 26 : i % 26) == limit - 1)
                            throw new ArgumentException("last " + (row ? "row" : "column") +
                                                        " not empty");
                Func<Expr, Expr> transform = x => {
                    if (x.Kind == 'R') {
                        int coordinate = Axis(x);
                        if (!insert && coordinate == at)
                            return INVALID;
                        int n = coordinate +
                                (insert ? (coordinate >= at ? 1 : 0) : (coordinate > at ? -1 : 0));
                        return n >= limit ? INVALID : Change(x, n);
                    }
                    int a = Axis(x.A), b = Axis(x.B);
                    if (!insert && a == at && b == at)
                        return INVALID;
                    int u = a + (insert ? (a >= at ? 1 : 0) : (a > at ? -1 : 0)),
                        v = b + (insert ? (b >= at ? 1 : 0) : (b >= at ? -1 : 0));
                    return v >= limit ? INVALID : Range(Change(x.A, u), Change(x.B, v));
                };
                next = new Expr[2574];
                for (int i = 0; i < 2574; i++)
                    if (contents[i] != null) {
                        Expr r = Ref(i % 26, i / 26, 0);
                        int v = Axis(r);
                        if (!insert && v == at)
                            continue;
                        Expr t = Change(r, v + (insert ? (v >= at ? 1 : 0) : (v > at ? -1 : 0)));
                        next[Id(t)] = Rewrite(contents[i], transform);
                    }
            } else
                throw new ArgumentException("unknown command");
            history.Add(new History(name, contents));
            int changed = Replace(next);
            return
                [name +
                 (name.Equals("SET") ? " " + Label(target) + "=" + Notation(values[target]) : "") +
                 " changed=" + changed];
        }
    }
    static void Main() {
        int n = int.Parse(Console.ReadLine()!);
        Sheet sheet = new();
        StringBuilder output = new();
        for (int i = 0; i < n; i++) {
            string line = Console.ReadLine()!;
            try {
                foreach (string value in sheet.Execute(line))
                    output.Append(value).Append('\n');
            } catch (ArgumentException problem) {
                output.Append("ERROR ").Append(problem.Message).Append('\n');
            }
        }
        Console.Write(output);
    }
}
