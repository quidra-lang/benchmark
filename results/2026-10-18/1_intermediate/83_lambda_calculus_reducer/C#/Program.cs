using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Program
{
    class Problem(string reason) : Exception("error: " + reason) { }

    static void Fail(string reason) => throw new Problem(reason);

    record Term(char Kind, string Name = "", int Number = 0, Term? Left = null, Term? Right = null);

    static Term Variable(string name) => new('v', name);

    static Term Constant(string name) => new('c', name);

    static Term Abstraction(string name, Term body) => new('a', name, Left: body);

    static Term Application(Term function, Term argument) => new('p', Left: function, Right: argument);

    record Token(string Kind, string Text, int Column);

    static bool Lower(char c) => c is >= 'a' and <= 'z';

    static bool Upper(char c) => c is >= 'A' and <= 'Z';

    static bool Digit(char c) => c is >= '0' and <= '9';

    static bool MacroName(string name) => name.Length > 0 && Upper(name[0]) && name.All(c => Upper(c) || Digit(c) || c == '_');

    class Parser
    {
        public List<Token> Tokens = new();
        public int At;
        public Parser(string line, int start)
        {
            for (int i = start; i < line.Length;)
            {
                char c = line[i];
                if (c == ' ')
                {
                    i++;
                    continue;
                }
                int first = i;
                string kind;
                if ("\\.()=;".Contains(c))
                {
                    kind = c.ToString();
                    i++;
                }
                else if (Lower(c))
                {
                    kind = "variable";
                    while (i < line.Length && (Lower(line[i]) || Digit(line[i]))) i++;
                }
                else if (Upper(c))
                {
                    kind = "macro";
                    while (i < line.Length && (Upper(line[i]) || Digit(line[i]) || line[i] == '_')) i++;
                }
                else if (c == '#' && i + 1 < line.Length && Digit(line[i + 1]))
                {
                    kind = "numeral";
                    i++;
                    while (i < line.Length && Digit(line[i])) i++;
                }
                else
                {
                    Fail($"column {i + 1}: unexpected character '{c}'");
                    return;
                }
                Tokens.Add(new Token(kind, line[first..i], first + 1));
            }
            Tokens.Add(new Token("end", "", line.Length + 1));
        }
        public Token Peek() => Tokens[At];
        public Token Expect(string kind)
        {
            Token token = Peek();
            if (token.Kind != kind) Fail($"column {token.Column}: expected " + (kind == "macro" ? "macro name" : kind == "variable" ? "variable" : $"'{kind}'"));
            At++;
            return token;
        }
        public Term ReadTerm()
        {
            List<Term> elements = new();
            while (Peek().Kind is "variable" or "macro" or "numeral" or "(") elements.Add(Atom());
            if (Peek().Kind == "\\")
            {
                At++;
                List<string> names = new() { Expect("variable").Text };
                while (Peek().Kind == "variable") names.Add(Tokens[At++].Text);
                Expect(".");
                Term body = ReadTerm();
                for (int i = names.Count - 1; i >= 0; i--) body = Abstraction(names[i], body);
                elements.Add(body);
            }
            if (elements.Count == 0) Fail($"column {Peek().Column}: expected term");
            Term result = elements[0];
            for (int i = 1; i < elements.Count; i++) result = Application(result, elements[i]);
            return result;
        }
        Term Atom()
        {
            Token token = Tokens[At++];
            if (token.Kind == "variable") return Variable(token.Text);
            if (token.Kind == "macro") return new('m', token.Text);
            if (token.Kind == "numeral") return new('n', Number: int.Parse(token.Text[1..]));
            Term body = ReadTerm();
            Expect(")");
            return body;
        }
        public void End()
        {
            if (Peek().Kind != "end") Fail($"column {Peek().Column}: unexpected '{Peek().Text}'");
        }
    }

    static string Print(Term term, bool end = true)
    {
        if (term.Kind == 'n') return "#" + term.Number;
        if (term.Kind == 'd') return term.Number.ToString(CultureInfo.InvariantCulture);
        if (term.Kind != 'a' && term.Kind != 'p') return term.Name;
        if (term.Kind == 'a')
        {
            List<string> names = new();
            Term body = term;
            while (body.Kind == 'a')
            {
                names.Add(body.Name);
                body = body.Left!;
            }
            string text = term.Name.Length == 0 ? new string('\\', names.Count) + Print(body) : "\\" + string.Join(" ", names) + ". " + Print(body);
            return end ? text : "(" + text + ")";
        }
        string left = term.Left!.Kind == 'a' ? "(" + Print(term.Left) + ")" : Print(term.Left, false);
        string right = term.Right!.Kind == 'p' ? "(" + Print(term.Right) + ")" : Print(term.Right, end);
        return left + " " + right;
    }

    static SortedSet<string> Free(Term term)
    {
        SortedSet<string> result = new(StringComparer.Ordinal);
        if (term.Kind == 'v') result.Add(term.Name);
        else if (term.Kind == 'a')
        {
            result.UnionWith(Free(term.Left!));
            result.Remove(term.Name);
        }
        else if (term.Kind == 'p')
        {
            result.UnionWith(Free(term.Left!));
            result.UnionWith(Free(term.Right!));
        }
        return result;
    }

    static void References(Term term, List<string> result)
    {
        if (term.Kind == 'm') result.Add(term.Name);
        else
        {
            if (term.Left != null) References(term.Left, result);
            if (term.Right != null) References(term.Right, result);
        }
    }

    static Term Substitute(Term term, string name, Term value)
    {
        if (term.Kind == 'v') return term.Name == name ? value : term;
        if (term.Kind == 'p') return Application(Substitute(term.Left!, name, value), Substitute(term.Right!, name, value));
        string bound = term.Name;
        var bodyFree = Free(term.Left!);
        if (bound == name || !bodyFree.Contains(name)) return term;
        var valueFree = Free(value);
        if (!valueFree.Contains(bound)) return Abstraction(bound, Substitute(term.Left!, name, value));
        int end = bound.Length;
        while (end > 0 && Digit(bound[end - 1])) end--;
        string prefix = bound[..end], fresh;
        int index = 1;
        do
        {
            fresh = prefix + index++;
        }
        while (bodyFree.Contains(fresh) || valueFree.Contains(fresh));
        return Abstraction(fresh, Substitute(Substitute(term.Left!, bound, Variable(fresh)), name, value));
    }

    static string Sequence(int index) => ((char)('a' + index % 26)).ToString() + (index < 26 ? "" : (index / 26).ToString(CultureInfo.InvariantCulture));

    record Binding(string OldName, string NewName);

    static Term Canonical(Term term)
    {
        int next = 0;
        return Rename(term, Free(term), ref next, new());
    }

    static Term Rename(Term term, SortedSet<string> free, ref int next, List<Binding> bindings)
    {
        if (term.Kind == 'v')
        {
            for (int i = bindings.Count - 1; i >= 0; i--) if (bindings[i].OldName == term.Name) return Variable(bindings[i].NewName);
            return term;
        }
        if (term.Kind == 'p')
        {
            Term left = Rename(term.Left!, free, ref next, bindings);
            Term right = Rename(term.Right!, free, ref next, bindings);
            return Application(left, right);
        }
        string name;
        do
        {
            name = Sequence(next++);
        }
        while (free.Contains(name));
        bindings.Add(new Binding(term.Name, name));
        Term body = Rename(term.Left!, free, ref next, bindings);
        bindings.RemoveAt(bindings.Count - 1);
        return Abstraction(name, body);
    }

    static Term Debruijn(Term term) => Debruijn(term, new());

    static Term Debruijn(Term term, List<string> bindings)
    {
        if (term.Kind == 'v')
        {
            for (int i = bindings.Count - 1; i >= 0; i--) if (bindings[i] == term.Name) return new('d', Number: bindings.Count - 1 - i);
            return term;
        }
        if (term.Kind == 'p') return Application(Debruijn(term.Left!, bindings), Debruijn(term.Right!, bindings));
        bindings.Add(term.Name);
        Term body = Debruijn(term.Left!, bindings);
        bindings.RemoveAt(bindings.Count - 1);
        return Abstraction("", body);
    }

    static bool Same(Term a, Term b)
    {
        if (a.Kind != b.Kind) return false;
        return a.Kind switch
        {
            'v' or 'm' or 'c' => a.Name == b.Name,
            'd' or 'n' => a.Number == b.Number,
            'a' => Same(a.Left!, b.Left!),
            _ => Same(a.Left!, b.Left!) && Same(a.Right!, b.Right!)
        };
    }

    record Step(Term Term, string Kind);

    static bool EtaRedex(Term term) => term.Kind == 'a' && term.Left!.Kind == 'p' && term.Left.Right!.Kind == 'v' && term.Left.Right.Name == term.Name && !Free(term.Left.Left!).Contains(term.Name);

    static Step? OneStep(Term term, string strategy, bool eta)
    {
        bool normal = strategy == "NORMAL", applicative = strategy == "APPLICATIVE", cbn = strategy == "CBN";
        if (term.Kind == 'v') return null;
        if (term.Kind == 'a')
        {
            if (!normal && !applicative) return null;
            if (normal && eta && EtaRedex(term)) return new(term.Left!.Left!, "eta");
            Step? body = OneStep(term.Left!, strategy, eta);
            if (body != null) return new(Abstraction(term.Name, body.Term), body.Kind);
            return eta && EtaRedex(term) ? new(term.Left!.Left!, "eta") : null;
        }
        if ((normal || cbn) && term.Left!.Kind == 'a') return new(Substitute(term.Left.Left!, term.Left.Name, term.Right!), "beta");
        Step? left = OneStep(term.Left!, strategy, eta);
        if (left != null) return new(Application(left.Term, term.Right!), left.Kind);
        if (cbn) return null;
        Step? right = OneStep(term.Right!, strategy, eta);
        if (right != null) return new(Application(term.Left!, right.Term), right.Kind);
        return term.Left!.Kind == 'a' && (normal || applicative || term.Right!.Kind is 'v' or 'a') ? new(Substitute(term.Left.Left!, term.Left.Name, term.Right!), "beta") : null;
    }

    record Reduced(Term Term, int Count, bool Success);
    readonly SortedDictionary<string, Term> macros = new(StringComparer.Ordinal);
    bool display, eta;
    int limit = 10000;
    Program()
    {
        Term x = Variable("x"), y = Variable("y"), z = Variable("z");
        macros["I"] = Abstraction("x", x);
        macros["K"] = Abstraction("x", Abstraction("y", x));
        macros["S"] = Abstraction("x", Abstraction("y", Abstraction("z", Application(Application(x, z), Application(y, z)))));
    }

    Term Expand(Term term)
    {
        if (term.Kind == 'v') return term;
        if (term.Kind == 'm')
        {
            if (!macros.TryGetValue(term.Name, out Term? value)) Fail("unbound macro " + term.Name);
            return Expand(value!);
        }
        if (term.Kind == 'n')
        {
            Term body = Variable("x");
            for (int i = 0; i < term.Number; i++) body = Application(Variable("f"), body);
            return Abstraction("f", Abstraction("x", body));
        }
        if (term.Kind == 'a') return Abstraction(term.Name, Expand(term.Left!));
        return Application(Expand(term.Left!), Expand(term.Right!));
    }

    bool Depends(string from, string on, HashSet<string>? seen = null)
    {
        seen ??= new(StringComparer.Ordinal);
        if (!macros.TryGetValue(from, out Term? term) || !seen.Add(from)) return false;
        List<string> refs = new();
        References(term, refs);
        return refs.Any(name => name == on || Depends(name, on, seen));
    }

    Reduced Reduce(Term term, string strategy, bool useEta, bool show = false, bool ski = false)
    {
        int count = 0;
        while (true)
        {
            Step? next = ski ? SkiStep(term) : OneStep(term, strategy, useEta);
            if (next == null) return new(term, count, true);
            if (count == limit) return new(term, count, false);
            term = next.Term;
            count++;
            if (show) Console.WriteLine($"step {count} ({next.Kind}): {Print(term)}");
        }
    }

    string Failure() => $"no normal form within {limit} steps";

    static int Size(Term term) => term.Kind == 'v' ? 1 : term.Kind == 'a' ? 1 + Size(term.Left!) : 1 + Size(term.Left!) + Size(term.Right!);

    static int Depth(Term term) => term.Kind == 'v' ? 1 : term.Kind == 'a' ? 1 + Depth(term.Left!) : 1 + Math.Max(Depth(term.Left!), Depth(term.Right!));

    class Type
    {
        public int Variable;
        public Type? Left, Right, Link;
        public Type(int variable)
        {
            Variable = variable;
        }
        public Type(Type left, Type right)
        {
            Variable = -1;
            Left = left;
            Right = right;
        }
    }

    class Untypable : Exception { }

    static Type Resolved(Type type)
    {
        Type end = type;
        while (end.Link != null) end = end.Link;
        while (type.Link != null)
        {
            Type next = type.Link;
            type.Link = end;
            type = next;
        }
        return end;
    }

    static bool Occurs(Type variable, Type within)
    {
        within = Resolved(within);
        return within == variable || within.Variable < 0 && (Occurs(variable, within.Left!) || Occurs(variable, within.Right!));
    }

    static void Unify(Type a, Type b)
    {
        a = Resolved(a);
        b = Resolved(b);
        if (a == b) return;
        if (a.Variable >= 0)
        {
            if (Occurs(a, b)) throw new Untypable();
            a.Link = b;
        }
        else if (b.Variable >= 0) Unify(b, a);
        else
        {
            Unify(a.Left!, b.Left!);
            Unify(a.Right!, b.Right!);
        }
    }

    record TypedBinding(string Name, Type Type);

    static Type Infer(Term term, List<TypedBinding> bindings, Dictionary<string, Type> free, ref int next)
    {
        if (term.Kind == 'v')
        {
            for (int i = bindings.Count - 1; i >= 0; i--) if (bindings[i].Name == term.Name) return bindings[i].Type;
            if (!free.TryGetValue(term.Name, out Type? type)) free[term.Name] = type = new Type(next++);
            return type;
        }
        if (term.Kind == 'a')
        {
            Type parameter = new(next++);
            bindings.Add(new(term.Name, parameter));
            Type body = Infer(term.Left!, bindings, free, ref next);
            bindings.RemoveAt(bindings.Count - 1);
            return new(parameter, body);
        }
        Type function = Infer(term.Left!, bindings, free, ref next), argument = Infer(term.Right!, bindings, free, ref next), result = new(next++);
        Unify(function, new Type(argument, result));
        return result;
    }

    static string PrintType(Type type, Dictionary<int, string> names)
    {
        type = Resolved(type);
        if (type.Variable >= 0)
        {
            if (!names.TryGetValue(type.Variable, out string? name)) names[type.Variable] = name = Sequence(names.Count);
            return name;
        }
        Type left = Resolved(type.Left!);
        string argument = PrintType(left, names);
        return (left.Variable < 0 ? "(" + argument + ")" : argument) + " -> " + PrintType(type.Right!, names);
    }

    static string Church(Term term)
    {
        if (term.Kind == 'a' && term.Left!.Kind == 'a')
        {
            string f = term.Name, x = term.Left.Name;
            Term body = term.Left.Left!;
            int count = 0;
            while (body.Kind == 'p' && body.Left!.Kind == 'v' && body.Left.Name == f)
            {
                count++;
                body = body.Right!;
            }
            if (body.Kind == 'v' && body.Name == x) return count.ToString(CultureInfo.InvariantCulture);
            if (term.Left.Left!.Kind == 'v' && term.Left.Left.Name == f) return "true";
        }
        if (term.Kind == 'a' && term.Left!.Kind == 'p' && term.Left.Left!.Kind == 'p' && term.Left.Left.Left!.Kind == 'v' && term.Left.Left.Left.Name == term.Name)
        {
            Term p = term.Left.Left.Right!, q = term.Left.Right!;
            if (!Free(p).Contains(term.Name) && !Free(q).Contains(term.Name)) return "(" + Church(p) + ", " + Church(q) + ")";
        }
        return Print(Canonical(term));
    }

    static Term AbstractSki(string name, Term term)
    {
        if (!Free(term).Contains(name)) return Application(Constant("K"), term);
        if (term.Kind == 'v' && term.Name == name) return Constant("I");
        if (term.Kind == 'p' && term.Right!.Kind == 'v' && term.Right.Name == name && !Free(term.Left!).Contains(name)) return term.Left!;
        return Application(Application(Constant("S"), AbstractSki(name, term.Left!)), AbstractSki(name, term.Right!));
    }

    static Term Ski(Term term) => term.Kind == 'v' ? term : term.Kind == 'a' ? AbstractSki(term.Name, Ski(term.Left!)) : Application(Ski(term.Left!), Ski(term.Right!));

    static Term Apply(Term head, List<Term> arguments, int from)
    {
        for (int i = from; i < arguments.Count; i++) head = Application(head, arguments[i]);
        return head;
    }

    static Step? SkiStep(Term term)
    {
        List<Term> args = new();
        Term head = term;
        while (head.Kind == 'p')
        {
            args.Insert(0, head.Right!);
            head = head.Left!;
        }
        if (head.Kind == 'c')
        {
            if (head.Name == "I" && args.Count > 0) return new(Apply(args[0], args, 1), "I");
            if (head.Name == "K" && args.Count >= 2) return new(Apply(args[0], args, 2), "K");
            if (head.Name == "S" && args.Count >= 3) return new(Apply(Application(Application(args[0], args[2]), Application(args[1], args[2])), args, 3), "S");
        }
        for (int i = 0; i < args.Count; i++)
        {
            Step? next = SkiStep(args[i]);
            if (next != null)
            {
                args[i] = next.Term;
                return new(Apply(head, args, 0), next.Kind);
            }
        }
        return null;
    }

    record Closure(Term Term, List<Closure> Environment);

    static Term Realize(Term code, List<Closure> environment, int depth)
    {
        while (code.Kind == 'd' && code.Number >= depth)
        {
            Closure closure = environment[code.Number - depth];
            code = closure.Term;
            environment = closure.Environment;
            depth = 0;
        }
        if (code.Kind == 'v' || code.Kind == 'd') return code;
        if (code.Kind == 'a') return Abstraction("", Realize(code.Left!, environment, depth + 1));
        return Application(Realize(code.Left!, environment, depth), Realize(code.Right!, environment, depth));
    }

    static Term FromDebruijn(Term term, SortedSet<string> free, List<string> bindings, ref int next)
    {
        if (term.Kind == 'v') return term;
        if (term.Kind == 'd') return Variable(bindings[bindings.Count - 1 - term.Number]);
        if (term.Kind == 'p')
        {
            Term left = FromDebruijn(term.Left!, free, bindings, ref next), right = FromDebruijn(term.Right!, free, bindings, ref next);
            return Application(left, right);
        }
        string name;
        do
        {
            name = Sequence(next++);
        }
        while (free.Contains(name));
        bindings.Add(name);
        Term body = FromDebruijn(term.Left!, free, bindings, ref next);
        bindings.RemoveAt(bindings.Count - 1);
        return Abstraction(name, body);
    }

    void Kam(Term term)
    {
        Term code = Debruijn(term);
        List<Closure> environment = new(), stack = new();
        int count = 0;
        while (true)
        {
            string kind = code.Kind == 'p' ? "push" : code.Kind == 'a' && stack.Count > 0 ? "grab" : code.Kind == 'd' ? "access" : "";
            if (kind.Length == 0) break;
            if (count == limit)
            {
                Console.WriteLine($"no result within {limit} transitions");
                return;
            }
            if (kind == "push")
            {
                stack.Add(new(code.Right!, environment));
                code = code.Left!;
            }
            else if (kind == "grab")
            {
                List<Closure> next = new() { stack[^1] };
                stack.RemoveAt(stack.Count - 1);
                next.AddRange(environment);
                environment = next;
                code = code.Left!;
            }
            else
            {
                Closure closure = environment[code.Number];
                code = closure.Term;
                environment = closure.Environment;
            }
            count++;
            if (display) Console.WriteLine($"step {count} ({kind}): {Print(code)} [env {environment.Count}, stack {stack.Count}]");
        }
        Term result = Realize(code, environment, 0);
        for (int i = stack.Count - 1; i >= 0; i--) result = Application(result, Realize(stack[i].Term, stack[i].Environment, 0));
        int index = 0;
        result = FromDebruijn(result, Free(result), new(), ref index);
        Console.WriteLine($"result: {Print(result)} (transitions: {count})");
    }
    static readonly HashSet<string> Reserved = new(StringComparer.Ordinal) { "S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV" };

    void Command(string line)
    {
        int split = line.IndexOf(' ');
        string command = split < 0 ? line : line[..split], argument = split < 0 ? "" : line[(split + 1)..];
        if (!new[] { "let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam" }.Contains(command)) Fail("unknown command " + command);
        if (new[] { "unlet", "macros", "steps", "eta", "limit" }.Contains(command))
        {
            string[] words = argument.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            switch (command)
            {
                case "steps":
                case "eta":
                    if (words.Length != 1 || (words[0] != "on" && words[0] != "off")) Fail("bad argument");
                    if (command == "steps") display = words[0] == "on";
                    else eta = words[0] == "on";
                    break;
                case "limit":
                    if (words.Length != 1 || words[0].Length is < 1 or > 5 || !words[0].All(Digit)) Fail("bad argument");
                    int value = int.Parse(words[0]);
                    if (value < 1 || value > 10000) Fail("bad argument");
                    limit = value;
                    break;
                case "macros":
                    if (words.Length != 0) Fail("bad argument");
                    bool any = false;
                    foreach (var entry in macros) if (entry.Key != "S" && entry.Key != "K" && entry.Key != "I")
                    {
                        Console.WriteLine(entry.Key + " = " + Print(entry.Value));
                        any = true;
                    }
                    if (!any) Console.WriteLine("(none)");
                    break;
                case "unlet":
                    if (words.Length != 1 || !MacroName(words[0])) Fail("bad argument");
                    string name = words[0];
                    if (Reserved.Contains(name)) Fail("reserved name " + name);
                    if (!macros.ContainsKey(name)) Fail("unbound macro " + name);
                    foreach (var entry in macros)
                    {
                        List<string> refs = new();
                        References(entry.Value, refs);
                        if (refs.Contains(name)) Fail(name + " is used by " + entry.Key);
                    }
                    macros.Remove(name);
                    Console.WriteLine("removed " + name);
                    break;
            }
            return;
        }
        Parser parser = new(line, split < 0 ? line.Length : split + 1);
        string? identifier = null;
        string strategy = "NORMAL";
        Term first;
        Term? second = null;
        if (command == "let")
        {
            identifier = parser.Expect("macro").Text;
            parser.Expect("=");
            first = parser.ReadTerm();
        }
        else if (command == "subst")
        {
            identifier = parser.Expect("variable").Text;
            parser.Expect("=");
            first = parser.ReadTerm();
            parser.Expect(";");
            second = parser.ReadTerm();
        }
        else
        {
            if (command == "reduce" && parser.Peek().Kind == "macro" && new[] { "NORMAL", "APPLICATIVE", "CBN", "CBV" }.Contains(parser.Peek().Text)) strategy = parser.Tokens[parser.At++].Text;
            first = parser.ReadTerm();
            if (command is "equal" or "alpha")
            {
                parser.Expect(";");
                second = parser.ReadTerm();
            }
        }
        parser.End();
        if (command == "let")
        {
            if (Reserved.Contains(identifier!)) Fail("reserved name " + identifier);
            List<string> refs = new();
            References(first, refs);
            foreach (string name in refs)
            {
                if (name == identifier || Depends(name, identifier!)) Fail("recursive definition of " + identifier);
                if (!macros.ContainsKey(name)) Fail("unbound macro " + name);
            }
            var variables = Free(first);
            if (variables.Count > 0) Fail("free variable " + variables.Min + " in definition of " + identifier);
            Console.WriteLine((macros.ContainsKey(identifier!) ? "redefined " : "defined ") + identifier);
            macros[identifier!] = first;
            return;
        }
        first = Expand(first);
        if (second != null) second = Expand(second);
        switch (command)
        {
            case "expand":
                Console.WriteLine(Print(first));
                break;
            case "subst":
                Console.WriteLine(Print(Substitute(second!, identifier!, first)));
                break;
            case "debruijn":
                Console.WriteLine(Print(Debruijn(first)));
                break;
            case "fv":
                var variables = Free(first);
                Console.WriteLine(variables.Count == 0 ? "(none)" : string.Join(" ", variables));
                break;
            case "size":
                Console.WriteLine(Size(first));
                break;
            case "depth":
                Console.WriteLine(Depth(first));
                break;
            case "alpha":
                Console.WriteLine(Same(Debruijn(first), Debruijn(second!)) ? "yes" : "no");
                break;
            case "equal":
                Reduced left = Reduce(first, "NORMAL", eta), right = Reduce(second!, "NORMAL", eta);
                Console.WriteLine(!left.Success || !right.Success ? "unknown" : Same(Debruijn(left.Term), Debruijn(right.Term)) ? "yes" : "no");
                break;
            case "type":
                try
                {
                    int index = 0;
                    Console.WriteLine(PrintType(Infer(first, new(), new(StringComparer.Ordinal), ref index), new()));
                }
                catch (Untypable)
                {
                    Console.WriteLine("not typable");
                }
                break;
            case "church":
                Reduced church = Reduce(first, "NORMAL", false);
                Console.WriteLine(church.Success ? Church(Canonical(church.Term)) : Failure());
                break;
            case "ski":
                Console.WriteLine(Print(Ski(first)));
                break;
            case "kam":
                Kam(first);
                break;
            case "reduce":
            case "skireduce":
                bool ski = command == "skireduce";
                Reduced result = Reduce(ski ? Ski(first) : first, strategy, eta, display, ski);
                Console.WriteLine(result.Success ? $"result: {Print(ski ? result.Term : Canonical(result.Term))} (steps: {result.Count})" : Failure());
                break;
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program workbench = new();
        string? line;
        while ((line = Console.ReadLine()) != null && line != "quit")
        {
            if (line.Length == 0 || line.StartsWith("--", StringComparison.Ordinal)) continue;
            try
            {
                workbench.Command(line);
            }
            catch (Problem problem)
            {
                Console.WriteLine(problem.Message);
            }
        }
    }
}
