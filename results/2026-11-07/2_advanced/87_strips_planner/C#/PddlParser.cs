global using System;
global using System.Collections.Generic;
global using System.Globalization;
global using System.IO;
global using System.Linq;
global using State = System.Collections.Generic.HashSet<int>;
sealed record Expr(string? Word, List<Expr>? Children)
{
    public string Text => Word!;
    public List<Expr> List => Children!;
}
sealed class Atom : IEquatable<Atom>
{
    public string Predicate {
        get;
    }
    public List<string> Terms {
        get;
    }
    public Atom(string predicate, IEnumerable<string> terms) {
        Predicate = predicate;
        Terms = terms.ToList();
    }
    public Atom(Expr expr) : this(expr.List[0].Text, expr.List.Skip(1).Select(e => e.Text)) {
    }
    public string Text => "(" + string.Join(" ", new[] {
        Predicate
    }.Concat(Terms)) + ")";
    public Atom Replace(Dictionary<string, string> values) => new(Predicate, Terms.Select(t => values[t]));
    public bool Equals(Atom? other) => other is not null && Predicate == other.Predicate && Terms.SequenceEqual(other.Terms);
    public override bool Equals(object? other) => other is Atom atom && Equals(atom);
    public override int GetHashCode()
    {
        HashCode hash = new();
        hash.Add(Predicate, StringComparer.Ordinal);
        foreach (string term in Terms) hash.Add(term, StringComparer.Ordinal);
        return hash.ToHashCode();
    }
}
sealed record Literal(Atom Atom, bool Negative = false)
{
    public string Text => Negative ? $"(not {Atom.Text})" : Atom.Text;
    public Literal Replace(Dictionary<string, string> values) => new(Atom.Replace(values), Negative);
}
sealed record Typed(string Name, string Type);
sealed record Predicate(string Name, List<string> Types);
sealed class Schema(string name)
{
    public string Name {
        get;
    } = name;
    public List<Typed> Parameters {
        get;
        set;
    } = new();
    public List<Literal> Pre {
        get;
        set;
    } = new();
    public List<Literal> Effects {
        get;
    } = new();
    public int Cost {
        get;
        set;
    } = 1;
}
sealed class Domain(string name)
{
    public string Name {
        get;
    } = name;
    public List<string> TypeOrder {
        get;
    } = new() {
        "object"
    };
    public Dictionary<string, string> Parents {
        get;
    } = new(StringComparer.Ordinal);
    public List<Predicate> Predicates {
        get;
    } = new();
    public List<Schema> Actions {
        get;
        set;
    } = new();
    public List<string> Diagnostics {
        get;
    } = new();
}
sealed class Problem(string name)
{
    public string Name {
        get;
    } = name;
    public List<Typed> Objects {
        get;
        set;
    } = new();
    public List<Atom> Initial {
        get;
        set;
    } = new();
    public List<Atom> Goals {
        get;
        set;
    } = new();
    public List<string> Diagnostics {
        get;
    } = new();
}
static class PddlParser
{
    public static List<Expr> Expressions(string path)
    {
        List<string> tokens = new();
        foreach (string line in File.ReadLines(path))
        {
            System.Text.StringBuilder word = new();
            void Flush() {
                if (word.Length > 0) {
                    tokens.Add(word.ToString());
                    word.Clear();
                }
            }
            foreach (char c in line.TakeWhile(c => c != ';'))
            {
                if (c is '(' or ')' or ' ') {
                    Flush();
                    if (c != ' ') tokens.Add(c.ToString());
                }
                else word.Append(c);
            }
            Flush();
        }
        int i = 0;
        Expr Read()
        {
            string token = tokens[i++];
            if (token != "(") return new Expr(token, null);
            List<Expr> children = new();
            while (tokens[i] != ")") children.Add(Read());
            i++;
            return new Expr(null, children);
        }
        List<Expr> result = new();
        while (i < tokens.Count) result.Add(Read());
        return result;
    }
    public static List<Typed> TypedList(List<Expr> words)
    {
        List<Typed> result = new();
        List<string> pending = new();
        int i = 0;
        while (i < words.Count)
        {
            if (words[i].Text == "-")
            {
                i++;
                result.AddRange(pending.Select(name => new Typed(name, words[i].Text)));
                pending.Clear();
            }
            else pending.Add(words[i].Text);
            i++;
        }
        result.AddRange(pending.Select(name => new Typed(name, "object")));
        return result;
    }
    public static List<Expr> Conjunction(Expr expr) => expr.List[0].Text == "and" ? expr.List.Skip(1).ToList() : new() {
        expr
    };
    public static Literal ReadLiteral(Expr expr) => expr.List[0].Text == "not" ? new Literal(new Atom(expr.List[1]), true) : new Literal(new Atom(expr));
    public static Domain ReadDomain()
    {
        List<Expr> a = Expressions("input/domain.txt")[0].List;
        Domain domain = new(a[1].List[1].Text);
        foreach (Expr expr in a.Skip(2))
        {
            List<Expr> s = expr.List;
            switch (s[0].Text)
            {
                case ":types":
                foreach (Expr word in s.Skip(1)) if (word.Text != "-" && !domain.TypeOrder.Contains(word.Text))
                {
                    domain.TypeOrder.Add(word.Text);
                    if (word.Text != "object") domain.Parents[word.Text] = "object";
                }
                foreach (Typed item in TypedList(s.Skip(1).ToList())) domain.Parents[item.Name] = item.Type;
                break;
                case ":predicates":
                foreach (Expr value in s.Skip(1)) domain.Predicates.Add(new Predicate(value.List[0].Text, TypedList(value.List.Skip(1).ToList()).Select(t => t.Type).ToList()));
                break;
                case ":action":
                Schema action = new(s[1].Text);
                for (int i = 2; i < s.Count; i += 2)
                {
                    switch (s[i].Text)
                    {
                        case ":parameters": action.Parameters = TypedList(s[i + 1].List);
                        break;
                        case ":precondition": action.Pre = Conjunction(s[i + 1]).Select(ReadLiteral).ToList();
                        break;
                        default:
                        foreach (Expr effect in Conjunction(s[i + 1]))
                        {
                            if (effect.List[0].Text == "increase") action.Cost = int.Parse(effect.List[2].Text, CultureInfo.InvariantCulture);
                            else action.Effects.Add(ReadLiteral(effect));
                        }
                        break;
                    }
                }
                domain.Actions.Add(action);
                break;
            }
        }
        return domain;
    }
    public static List<Problem> ReadProblems() => Expressions("input/problems.txt").Select(expr =>
    {
        List<Expr> a = expr.List;
        Problem problem = new(a[1].List[1].Text);
        foreach (Expr section in a.Skip(2))
        {
            List<Expr> s = section.List;
            switch (s[0].Text)
            {
                case ":objects": problem.Objects = TypedList(s.Skip(1).ToList());
                break;
                case ":init": problem.Initial = s.Skip(1).Select(e => new Atom(e)).ToList();
                break;
                case ":goal": problem.Goals = Conjunction(s[1]).Select(e => new Atom(e)).ToList();
                break;
            }
        }
        return problem;
    }).ToList();
}
