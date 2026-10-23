using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Program
{
    static readonly HashSet<string> Reserved = new(StringComparer.Ordinal) { "not", "mod", "count", "sum", "min", "max", "retract", "dump", "why", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt" };
    static readonly HashSet<string> Comparisons = new(StringComparer.Ordinal) { "=", "!=", "<", "<=", ">", ">=" };
    static readonly HashSet<string> Operations = new(StringComparer.Ordinal) { "+", "-", "*", "/", "mod" };

    class Problem(string reason) : Exception(reason) { }

    static void Fail(string reason) => throw new Problem(reason);

    static bool Lower(char c) => c is >= 'a' and <= 'z';

    static bool Digit(char c) => c is >= '0' and <= '9';

    static bool WordChar(char c) => Lower(c) || c is >= 'A' and <= 'Z' || Digit(c) || c == '_';

    record Value(bool Integer, long Number, string Symbol) : IComparable<Value>
    {
        public static Value Int(long n) => new(true, n, "");
        public static Value Sym(string s) => new(false, 0, s);
        public int CompareTo(Value? other)
        {
            if (other == null) return 1;
            if (Integer != other.Integer) return Integer ? -1 : 1;
            return Integer ? Number.CompareTo(other.Number) : StringComparer.Ordinal.Compare(Symbol, other.Symbol);
        }
        public override string ToString() => Integer ? Number.ToString(CultureInfo.InvariantCulture) : Symbol.Length > 0 && Lower(Symbol[0]) && !Reserved.Contains(Symbol) && Symbol.All(WordChar) ? Symbol : "\"" + Symbol + "\"";
    }

    class Tuple(IEnumerable<Value> values) : IComparable<Tuple>
    {
        public readonly Value[] Values = values.ToArray();
        public int CompareTo(Tuple? other)
        {
            if (other == null) return 1;
            for (int i = 0; i < Values.Length; i++)
            {
                int c = Values[i].CompareTo(other.Values[i]);
                if (c != 0) return c;
            }
            return 0;
        }
    }

    record Term(string? Variable, Value? Value, bool Anonymous)
    {
        public string Text(Dictionary<string, Value>? env) => Anonymous ? "_" : Value != null ? Value.ToString() : env != null && env.TryGetValue(Variable!, out Value? value) ? value.ToString() : Variable!;
        public Value Get(Dictionary<string, Value> env) => Value ?? env[Variable!];
    }

    record Expr(string Op, Term? Term, Expr? Left, Expr? Right)
    {
        public string Text(Dictionary<string, Value>? env) => Term != null ? Term.Text(env) : Op == "()" ? "(" + Left!.Text(env) + ")" : Left!.Text(env) + " " + Op + " " + Right!.Text(env);
        public void Terms(List<Term> output)
        {
            if (Term != null) output.Add(Term);
            else
            {
                Left!.Terms(output);
                Right?.Terms(output);
            }
        }
        public Value? Evaluate(Dictionary<string, Value> env)
        {
            if (Term != null) return Term.Get(env);
            Value? a = Left!.Evaluate(env);
            if (Op == "()") return a;
            Value? b = Right!.Evaluate(env);
            if (a == null || b == null || !a.Integer || !b.Integer || (Op is "/" or "mod") && b.Number == 0) return null;
            long x = a.Number, y = b.Number;
            return Value.Int(Op switch
            {
                "+" => x + y,
                "-" => x - y,
                "*" => x * y,
                "/" => FloorDivide(x, y),
                _ => x - y * FloorDivide(x, y)
            });
        }
    }

    static long FloorDivide(long a, long b)
    {
        long q = a / b, r = a % b;
        return r != 0 && (r < 0) != (b < 0) ? q - 1 : q;
    }

    record Atom(string Name, List<Term> Terms)
    {
        public string Text(Dictionary<string, Value>? env) => Name + (Terms.Count == 0 ? "" : "(" + string.Join(", ", Terms.Select(t => t.Text(env))) + ")");
        public Tuple Tuple(Dictionary<string, Value> env) => new(Terms.Select(t => t.Get(env)));
    }

    record Literal(Atom? Atom, bool Negative, Expr? Left, string? Op, Expr? Right)
    {
        public List<Term> Terms()
        {
            if (Atom != null) return Atom.Terms;
            List<Term> output = new();
            Left!.Terms(output);
            Right!.Terms(output);
            return output;
        }
        public string Text(Dictionary<string, Value>? env) => Atom != null ? (Negative ? "not " : "") + Atom.Text(env) : Left!.Text(env) + " " + Op + " " + Right!.Text(env);
        public bool Comparison(Dictionary<string, Value> env)
        {
            Value? a = Left!.Evaluate(env), b = Right!.Evaluate(env);
            if (a == null || b == null) return false;
            if (Op == "=") return a == b;
            if (Op == "!=") return a != b;
            if (!a.Integer || !b.Integer) return false;
            int c = a.Number.CompareTo(b.Number);
            return Op switch
            {
                "<" => c < 0,
                "<=" => c <= 0,
                ">" => c > 0,
                _ => c >= 0
            };
        }
    }

    record Rule(int Number, Atom? Head, List<Literal> Body)
    {
        public string Text() => (Head == null ? ":- " : Head.Text(null) + " :- ") + string.Join(", ", Body.Select(l => l.Text(null))) + ".";
        public List<Term> Terms() => (Head?.Terms ?? new()).Concat(Body.SelectMany(l => l.Terms())).ToList();
    }

    record Token(string Kind, string Text);

    record Statement(string Kind, Atom? Atom, List<Literal> Body, string? Name, long Number, string Aggregate, string? Variable);

    class Parser
    {
        public readonly List<Token> Tokens = new();
        int at;
        public Parser(string line)
        {
            for (int i = 0; i < line.Length;)
            {
                char c = line[i];
                if (c == ' ')
                {
                    i++;
                    continue;
                }
                if (c == '%') break;
                int first = i;
                string kind;
                if (c == '"')
                {
                    int end = line.IndexOf('"', i + 1);
                    if (end < 0) Fail("unterminated string");
                    i = end + 1;
                    kind = "string";
                }
                else if (i + 1 < line.Length && new[] { ":-", "?-", "!=", "<=", ">=" }.Contains(line.Substring(i, 2)))
                {
                    i += 2;
                    kind = line[first..i];
                }
                else if ("(),.:=<>+-*/".Contains(c))
                {
                    i++;
                    kind = c.ToString();
                }
                else if (WordChar(c))
                {
                    while (i < line.Length && WordChar(line[i])) i++;
                    string s = line[first..i];
                    if (Lower(c)) kind = Reserved.Contains(s) ? s : "name";
                    else if (c is >= 'A' and <= 'Z') kind = "variable";
                    else if (s == "_") kind = "anonymous";
                    else if (s.All(Digit))
                    {
                        if (long.Parse(s) > 1000000000) Fail("integer out of range '" + s + "'");
                        kind = "integer";
                    }
                    else
                    {
                        Fail("bad token '" + s + "'");
                        return;
                    }
                }
                else
                {
                    Fail("bad character '" + c + "'");
                    return;
                }
                Tokens.Add(new(kind, line[first..i]));
            }
            Tokens.Add(new("end", ""));
        }
        Token Peek() => Tokens[at];
        public bool Is(string kind) => Peek().Kind == kind;
        void Syntax() => Fail(Is("end") ? "syntax error at end of line" : "syntax error at '" + Peek().Text + "'");
        Token Expect(string kind)
        {
            if (!Is(kind)) Syntax();
            return Tokens[at++];
        }
        Term ReadTerm()
        {
            Token t = Peek();
            if (Is("name"))
            {
                at++;
                return new(null, Value.Sym(t.Text), false);
            }
            if (Is("string"))
            {
                at++;
                return new(null, Value.Sym(t.Text[1..^1]), false);
            }
            if (Is("integer") || Is("-"))
            {
                bool minus = Is("-");
                if (minus) at++;
                long n = long.Parse(Expect("integer").Text);
                return new(null, Value.Int(minus ? -n : n), false);
            }
            if (Is("variable"))
            {
                at++;
                return new(t.Text, null, false);
            }
            if (Is("anonymous"))
            {
                at++;
                return new(null, null, true);
            }
            Syntax();
            return null!;
        }
        Atom ReadAtom()
        {
            string name = Expect("name").Text;
            List<Term> args = new();
            if (Is("("))
            {
                at++;
                args.Add(ReadTerm());
                while (Is(","))
                {
                    at++;
                    args.Add(ReadTerm());
                }
                Expect(")");
            }
            return new(name, args);
        }
        Expr Factor()
        {
            if (Is("("))
            {
                at++;
                Expr inner = Expression();
                Expect(")");
                return new("()", null, inner, null);
            }
            return new("", ReadTerm(), null, null);
        }
        Expr Product()
        {
            Expr output = Factor();
            while (Is("*") || Is("/") || Is("mod"))
            {
                string op = Tokens[at++].Text;
                output = new(op, null, output, Factor());
            }
            return output;
        }
        Expr Expression()
        {
            Expr output = Product();
            while (Is("+") || Is("-"))
            {
                string op = Tokens[at++].Text;
                output = new(op, null, output, Product());
            }
            return output;
        }
        Literal ReadLiteral()
        {
            if (Is("not"))
            {
                at++;
                return new(ReadAtom(), true, null, null, null);
            }
            if (Is("name") && !Comparisons.Contains(Tokens[at + 1].Kind) && !Operations.Contains(Tokens[at + 1].Kind)) return new(ReadAtom(), false, null, null, null);
            Expr left = Expression();
            if (!Comparisons.Contains(Peek().Kind)) Syntax();
            string op = Tokens[at++].Text;
            return new(null, false, left, op, Expression());
        }
        List<Literal> ReadBody()
        {
            List<Literal> output = new() { ReadLiteral() };
            while (Is(","))
            {
                at++;
                output.Add(ReadLiteral());
            }
            return output;
        }
        public Statement ReadStatement()
        {
            string kind = Peek().Kind, aggregate = "";
            string? name = null, variable = null;
            Atom? atom = null;
            List<Literal> body = new();
            long number = 0;
            if (Is("name") || Is(":-"))
            {
                if (Is("name")) atom = ReadAtom();
                if (Is(":-"))
                {
                    at++;
                    body = ReadBody();
                    kind = "rule";
                }
                else
                {
                    if (atom == null) Syntax();
                    kind = "fact";
                }
            }
            else if (Is("?-"))
            {
                at++;
                kind = "query";
                if (Is("count"))
                {
                    aggregate = "count";
                    at++;
                }
                else if (Is("sum") || Is("min") || Is("max"))
                {
                    aggregate = Tokens[at++].Text;
                    variable = Expect("variable").Text;
                    Expect(":");
                }
                body = ReadBody();
            }
            else
            {
                if (!new[] { "retract", "why", "dump", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt" }.Contains(kind)) Syntax();
                at++;
                if (kind is "retract" or "why") atom = ReadAtom();
                else if (kind == "dump") name = Expect("name").Text;
                else if (kind == "forget") number = long.Parse(Expect("integer").Text);
                else if (kind == "listing" && Is("name")) name = Tokens[at++].Text;
            }
            Expect(".");
            if (!Is("end")) Syntax();
            return new(kind, atom, body, name, number, aggregate, variable);
        }
    }

    class Predicate(int arity)
    {
        public int Arity = arity;
        public SortedSet<Tuple> Facts = new();
        public Predicate Copy() => new(Arity) { Facts = new(Facts) };
    }

    class State
    {
        public SortedDictionary<string, Predicate> Predicates = new(StringComparer.Ordinal);
        public List<Rule> Rules = new();
        public State Copy()
        {
            State s = new();
            foreach (var entry in Predicates) s.Predicates[entry.Key] = entry.Value.Copy();
            s.Rules.AddRange(Rules);
            return s;
        }
    }

    record History(State State, int Line);

    record Derivation(int Round, int Rule);

    class Model
    {
        public SortedDictionary<string, SortedDictionary<Tuple, Derivation>> Tuples = new(StringComparer.Ordinal);
        public int[] Rounds = Array.Empty<int>(), Added = Array.Empty<int>();
    }
    State state = new();
    readonly List<History> history = new();
    int nextRule = 1;

    static List<string> Variables(IEnumerable<Term> terms) => terms.Where(t => t.Variable != null).Select(t => t.Variable!).Distinct(StringComparer.Ordinal).ToList();

    static List<Term> BodyTerms(List<Literal> body) => body.SelectMany(l => l.Terms()).ToList();

    static List<Atom> Atoms(Atom? head, List<Literal> body) => (head == null ? Enumerable.Empty<Atom>() : new[] { head }).Concat(body.Where(l => l.Atom != null).Select(l => l.Atom!)).ToList();
    SortedDictionary<string, int> PredicateCheck(Atom? head, List<Literal> body, bool clause)
    {
        SortedDictionary<string, int> arities = new(StringComparer.Ordinal);
        foreach (var e in state.Predicates) arities[e.Key] = e.Value.Arity;
        foreach (Atom a in Atoms(head, body))
        {
            bool exists = arities.TryGetValue(a.Name, out int expected);
            if (!exists && !clause) Fail("unknown predicate " + a.Name);
            if (exists && expected != a.Terms.Count) Fail($"arity mismatch for {a.Name}: expected {expected}, got {a.Terms.Count}");
            arities[a.Name] = a.Terms.Count;
        }
        return arities;
    }

    static void Safety(Atom? head, List<Literal> body, string? aggregateVariable)
    {
        if (head != null && head.Terms.Any(t => t.Anonymous)) Fail("anonymous variable in head");
        if (body.Any(l => l.Atom == null && l.Terms().Any(t => t.Anonymous))) Fail("anonymous variable in comparison");
        HashSet<string> bound = new(body.Where(l => l.Atom != null && !l.Negative).SelectMany(l => Variables(l.Atom!.Terms)), StringComparer.Ordinal);
        List<string> needed = head == null ? new() : Variables(head.Terms);
        if (aggregateVariable != null) needed.Add(aggregateVariable);
        foreach (Literal l in body) if (l.Atom == null || l.Negative) needed.AddRange(Variables(l.Terms()));
        foreach (string name in needed) if (!bound.Contains(name)) Fail("unsafe variable " + name);
    }

    static Dictionary<string, int>? Strata(IEnumerable<string> predicates, List<Rule> rules)
    {
        Dictionary<string, int> result = predicates.ToDictionary(p => p, _ => 0, StringComparer.Ordinal);
        for (int pass = 0; pass < result.Count; pass++)
        {
            bool changed = false;
            foreach (Rule r in rules) if (r.Head != null) foreach (Literal l in r.Body) if (l.Atom != null)
            {
                int value = result[l.Atom.Name] + (l.Negative ? 1 : 0);
                if (result[r.Head.Name] < value)
                {
                    result[r.Head.Name] = value;
                    changed = true;
                }
            }
            if (!changed) return result;
            if (pass + 1 == result.Count) return null;
        }
        return result;
    }

    void Snapshot(int line) => history.Add(new(state.Copy(), line));

    static Dictionary<string, Value>? Match(Atom atom, Tuple tuple, Dictionary<string, Value> original)
    {
        Dictionary<string, Value> env = new(original, StringComparer.Ordinal);
        for (int i = 0; i < atom.Terms.Count; i++)
        {
            Term t = atom.Terms[i];
            Value value = tuple.Values[i];
            if (t.Anonymous) continue;
            if (t.Value != null)
            {
                if (t.Value != value) return null;
            }
            else if (env.TryGetValue(t.Variable!, out Value? old))
            {
                if (old != value) return null;
            }
            else env[t.Variable!] = value;
        }
        return env;
    }

    static Tuple Key(List<string> vars, Dictionary<string, Value> env) => new(vars.Select(v => env[v]));

    static bool Filters(List<Literal> body, Model model, Dictionary<string, Value> env, bool complete)
    {
        foreach (Literal l in body) if (l.Atom == null || l.Negative)
        {
            if (!complete && !Variables(l.Terms()).All(env.ContainsKey)) continue;
            if (l.Atom == null)
            {
                if (!l.Comparison(env)) return false;
            }
            else if (model.Tuples[l.Atom.Name].Keys.Any(t => Match(l.Atom, t, env) != null)) return false;
        }
        return true;
    }

    static List<Dictionary<string, Value>> Solutions(List<Literal> body, Model model, int before = -1)
    {
        var positive = body.Where(l => l.Atom != null && !l.Negative).OrderBy(l => model.Tuples[l.Atom!.Name].Count).ToList();
        List<string> variables = Variables(BodyTerms(body));
        SortedDictionary<Tuple, Dictionary<string, Value>> output = new();

        void Visit(int at, Dictionary<string, Value> env)
        {
            if (!Filters(body, model, env, at == positive.Count)) return;
            if (at == positive.Count)
            {
                output.TryAdd(Key(variables, env), env);
                return;
            }
            Atom atom = positive[at].Atom!;
            List<string> names = Variables(atom.Terms);
            SortedSet<Tuple> seen = new();
            foreach (var entry in model.Tuples[atom.Name])
            {
                if (before >= 0 && entry.Value.Round >= before) continue;
                var candidate = Match(atom, entry.Key, env);
                if (candidate != null && seen.Add(Key(names, candidate))) Visit(at + 1, candidate);
            }
        }

        Visit(0, new(StringComparer.Ordinal));
        return output.Values.ToList();
    }

    Model BuildModel()
    {
        var levels = Strata(state.Predicates.Keys, state.Rules)!;
        int maximum = levels.Values.DefaultIfEmpty(-1).Max();
        Model model = new() { Rounds = new int[maximum + 1], Added = new int[maximum + 1] };
        foreach (var e in state.Predicates)
        {
            SortedDictionary<Tuple, Derivation> tuples = new();
            foreach (Tuple t in e.Value.Facts) tuples[t] = new(0, 0);
            model.Tuples[e.Key] = tuples;
        }
        int serial = 0;
        for (int level = 0; level <= maximum; level++) while (true)
        {
            SortedDictionary<string, SortedDictionary<Tuple, int>> staged = new(StringComparer.Ordinal);
            foreach (Rule r in state.Rules) if (r.Head != null && levels[r.Head.Name] == level)
            {
                foreach (var env in Solutions(r.Body, model))
                {
                    Tuple t = r.Head.Tuple(env);
                    if (model.Tuples[r.Head.Name].ContainsKey(t)) continue;
                    if (!staged.TryGetValue(r.Head.Name, out var tuples)) staged[r.Head.Name] = tuples = new();
                    if (!tuples.TryGetValue(t, out int old) || old > r.Number) tuples[t] = r.Number;
                }
            }
            if (staged.Count == 0) break;
            serial++;
            model.Rounds[level]++;
            foreach (var p in staged) foreach (var t in p.Value)
            {
                model.Tuples[p.Key][t.Key] = new(serial, t.Value);
                model.Added[level]++;
            }
        }
        return model;
    }

    static string TupleText(string predicate, Tuple tuple) => predicate + (tuple.Values.Length == 0 ? "" : "(" + string.Join(", ", tuple.Values.Select(v => v.ToString())) + ")");

    static IEnumerable<string> AnswerLines(List<string> vars, List<Dictionary<string, Value>> answers, string prefix) => answers.Select(env => prefix + string.Join(", ", vars.Select(v => v + " = " + env[v])));

    void Proof(string predicate, Tuple tuple, Model model, int depth, List<string> output)
    {
        string prefix = new string(' ', 2 * depth) + TupleText(predicate, tuple);
        Derivation derivation = model.Tuples[predicate][tuple];
        if (derivation.Round == 0)
        {
            output.Add(prefix + " [fact]");
            return;
        }
        foreach (Rule r in state.Rules) if (r.Head != null && r.Head.Name == predicate)
        {
            List<string> vars = Variables(r.Terms());
            SortedDictionary<Tuple, Dictionary<string, Value>> choices = new();
            foreach (var env in Solutions(r.Body, model, derivation.Round)) if (r.Head.Tuple(env).CompareTo(tuple) == 0) choices[Key(vars, env)] = env;
            if (choices.Count == 0) continue;
            var chosen = choices.First().Value;
            output.Add(prefix + " [rule " + r.Number + "]");
            foreach (Literal l in r.Body)
            {
                if (l.Atom != null && !l.Negative)
                {
                    foreach (var t in model.Tuples[l.Atom.Name]) if (t.Value.Round < derivation.Round && Match(l.Atom, t.Key, chosen) != null)
                    {
                        Proof(l.Atom.Name, t.Key, model, depth + 1, output);
                        break;
                    }
                }
                else output.Add(new string(' ', 2 * (depth + 1)) + l.Text(chosen));
            }
            return;
        }
    }

    List<string> Process(Statement s, int line)
    {
        List<string> output = new();
        if (s.Kind is "fact" or "rule")
        {
            var arities = PredicateCheck(s.Atom, s.Body, true);
            Safety(s.Atom, s.Body, null);
            Rule rule = new(nextRule, s.Atom, s.Body);
            if (s.Kind == "rule")
            {
                foreach (Rule old in state.Rules) if (old.Text() == rule.Text()) Fail("duplicate of rule " + old.Number);
                var trial = state.Rules.Append(rule).ToList();
                if (s.Atom != null && Strata(arities.Keys, trial) == null) Fail("negative cycle through " + s.Atom.Name);
            }
            else if (state.Predicates.TryGetValue(s.Atom!.Name, out var predicate) && predicate.Facts.Contains(s.Atom.Tuple(new()))) return output;
            Snapshot(line);
            foreach (var e in arities) if (!state.Predicates.ContainsKey(e.Key)) state.Predicates[e.Key] = new(e.Value);
            if (s.Kind == "fact") state.Predicates[s.Atom!.Name].Facts.Add(s.Atom.Tuple(new()));
            else
            {
                state.Rules.Add(rule);
                nextRule++;
                foreach (var group in rule.Terms().Where(t => t.Variable != null).GroupBy(t => t.Variable, StringComparer.Ordinal)) if (group.Count() == 1) output.Add($"WARNING line {line}: singleton variable {group.Key}");
            }
            return output;
        }
        if (s.Kind == "undo")
        {
            if (history.Count == 0) Fail("nothing to undo");
            History h = history[^1];
            history.RemoveAt(history.Count - 1);
            state = h.State;
            return new() { "undid line " + h.Line };
        }
        if (s.Kind == "forget")
        {
            Rule? rule = state.Rules.FirstOrDefault(r => r.Number == s.Number);
            if (rule == null) Fail("no rule " + s.Number);
            Snapshot(line);
            state.Rules.Remove(rule!);
            return output;
        }
        if (s.Kind is "retract" or "why") PredicateCheck(s.Atom, new(), false);
        if (s.Kind == "retract")
        {
            var removed = state.Predicates[s.Atom!.Name].Facts.Where(t => Match(s.Atom, t, new()) != null).ToList();
            if (removed.Count == 0) Fail("no matching facts");
            Snapshot(line);
            state.Predicates[s.Atom.Name].Facts.ExceptWith(removed);
            return new() { removed.Count + (removed.Count == 1 ? " fact retracted" : " facts retracted") };
        }
        if (s.Kind is "listing" or "dump")
        {
            if (s.Name != null && !state.Predicates.ContainsKey(s.Name)) Fail("unknown predicate " + s.Name);
            if (s.Kind == "listing")
            {
                foreach (Rule r in state.Rules) if (s.Name == null || r.Head != null && r.Head.Name == s.Name) output.Add(r.Number + ": " + r.Text());
                return output.Count == 0 ? new() { "no rules" } : output;
            }
        }
        if (s.Kind == "query")
        {
            PredicateCheck(null, s.Body, false);
            Safety(null, s.Body, s.Variable);
        }
        if (s.Kind == "why" && s.Atom!.Terms.Any(t => t.Value == null)) Fail("why needs a ground atom");
        var levels = Strata(state.Predicates.Keys, state.Rules)!;
        if (s.Kind == "strata")
        {
            if (levels.Count == 0) return new() { "no predicates" };
            List<string> names = state.Predicates.Keys.ToList();
            int n = names.Count;
            bool[,] reach = new bool[n, n];
            foreach (Rule r in state.Rules) if (r.Head != null) foreach (Literal l in r.Body) if (l.Atom != null) reach[names.IndexOf(r.Head.Name), names.IndexOf(l.Atom.Name)] = true;
            for (int k = 0; k < n; k++) for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) reach[i, j] |= reach[i, k] && reach[k, j];
            for (int k = 0; k <= levels.Values.Max(); k++) output.Add("stratum " + k + ": " + string.Join(", ", names.Select((name, i) => levels[name] == k ? name + (reach[i, i] ? "*" : "") : null).Where(name => name != null)));
            return output;
        }
        Model model = BuildModel();
        switch (s.Kind)
        {
            case "query":
            {
                var answers = Solutions(s.Body, model);
                var vars = Variables(BodyTerms(s.Body));
                if (s.Aggregate == "count") output.Add(answers.Count.ToString());
                else if (s.Aggregate == "sum")
                {
                    long total = 0;
                    foreach (var env in answers)
                    {
                        Value v = env[s.Variable!];
                        if (!v.Integer) Fail("non-integer value in sum");
                        total += v.Number;
                    }
                    output.Add(total.ToString());
                }
                else if (s.Aggregate is "min" or "max")
                {
                    Value? best = null;
                    foreach (var env in answers)
                    {
                        Value v = env[s.Variable!];
                        if (best == null || (s.Aggregate == "min" ? v.CompareTo(best) < 0 : v.CompareTo(best) > 0)) best = v;
                    }
                    output.Add(best?.ToString() ?? "no answers");
                }
                else if (vars.Count == 0) output.Add(answers.Count == 0 ? "false." : "true.");
                else
                {
                    output.AddRange(AnswerLines(vars, answers, ""));
                    output.Add(answers.Count + (answers.Count == 1 ? " answer" : " answers"));
                }
                break;
            }
            case "dump":
                foreach (Tuple t in model.Tuples[s.Name!].Keys) output.Add(TupleText(s.Name!, t) + ".");
                int count = model.Tuples[s.Name!].Count;
                output.Add(count + (count == 1 ? " tuple" : " tuples"));
                break;
            case "why":
                Tuple tuple = s.Atom!.Tuple(new());
                if (!model.Tuples[s.Atom.Name].ContainsKey(tuple)) output.Add("false.");
                else Proof(s.Atom.Name, tuple, model, 0, output);
                break;
            case "check":
                foreach (Rule r in state.Rules) if (r.Head == null)
                {
                    var answers = Solutions(r.Body, model);
                    var vars = Variables(BodyTerms(r.Body));
                    output.Add("constraint " + r.Number + ": " + (answers.Count == 0 ? "ok" : answers.Count + (answers.Count == 1 ? " violation" : " violations")));
                    if (vars.Count > 0) output.AddRange(AnswerLines(vars, answers, "  "));
                }
                if (output.Count == 0) output.Add("no constraints");
                break;
            case "predicates":
                foreach (var e in state.Predicates)
                {
                    int rules = state.Rules.Count(r => r.Head != null && r.Head.Name == e.Key);
                    output.Add($"{e.Key}/{e.Value.Arity}: facts {e.Value.Facts.Count}, rules {rules}, tuples {model.Tuples[e.Key].Count}");
                }
                if (output.Count == 0) output.Add("no predicates");
                break;
            case "stats":
                int facts = state.Predicates.Values.Sum(p => p.Facts.Count), tuples = model.Tuples.Values.Sum(p => p.Count), ruleCount = state.Rules.Count(r => r.Head != null);
                output.Add($"facts {facts}, rules {ruleCount}, constraints {state.Rules.Count - ruleCount}, tuples {tuples}");
                for (int k = 0; k < model.Rounds.Length; k++) output.Add($"stratum {k}: rounds {model.Rounds[k]}, new {model.Added[k]}");
                foreach (Rule r in state.Rules) if (r.Head != null) output.Add($"rule {r.Number}: new {model.Tuples[r.Head.Name].Values.Count(d => d.Rule == r.Number)}");
                break;
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program engine = new();
        string? line;
        int number = 0;
        while ((line = Console.ReadLine()) != null)
        {
            number++;
            try
            {
                Parser parser = new(line);
                if (parser.Is("end")) continue;
                Statement statement = parser.ReadStatement();
                if (statement.Kind == "halt") break;
                foreach (string output in engine.Process(statement, number)) Console.WriteLine(output);
            }
            catch (Problem problem)
            {
                Console.WriteLine($"ERROR line {number}: {problem.Message}");
            }
        }
    }
}
