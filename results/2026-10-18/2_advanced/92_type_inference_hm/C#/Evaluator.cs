using System;
using System.Collections.Generic;
using System.Linq;
abstract record Value {
    public sealed record Integer(long Number) : Value;
    public sealed record BooleanValue(bool Flag) : Value;
    public sealed record StringValue(string Text) : Value;
    public sealed record PairValue(Value First, Value Second) : Value;
    public sealed record ListValue(List<Value> Values) : Value;
    public sealed record Closure(Parameter Parameter, Expr Body, Dictionary<string, Value> Environment) : Value;
    public sealed record Builtin(string Name) : Value;
}
sealed class RuntimeError(Position position, string reason) : Exception(reason) {
    public Position Position {
        get;
    } = position;
    public string Reason {
        get;
    } = reason;
}
sealed class Evaluator {
    public int Calls {
        get;
        set;
    }
    static Value Checked(long value, Position position) {
        if (value is < int.MinValue or > int.MaxValue) throw new RuntimeError(position, "integer overflow");
        return new Value.Integer(value);
    }
    static int Compare(Value a, Value b, Position position) {
        switch (a, b) {
            case (Value.Integer x, Value.Integer y): return x.Number.CompareTo(y.Number);
            case (Value.BooleanValue x, Value.BooleanValue y): return x.Flag.CompareTo(y.Flag);
            case (Value.StringValue x, Value.StringValue y): return string.CompareOrdinal(x.Text, y.Text);
            case (Value.PairValue x, Value.PairValue y): {
                int first = Compare(x.First, y.First, position);
                return first == 0 ? Compare(x.Second, y.Second, position) : first;
            }
            case (Value.ListValue x, Value.ListValue y): for (int i = 0; i < Math.Min(x.Values.Count, y.Values.Count); i++) {
                int order = Compare(x.Values[i], y.Values[i], position);
                if (order != 0) return order;
            } return x.Values.Count.CompareTo(y.Values.Count);
            default: throw new RuntimeError(position, "functional value compared");
        }
    }
    static bool MatchPattern(Pattern pattern, Value value, Dictionary<string, Value> bindings) {
        switch (pattern, value) {
            case (WildPattern, _): return true;
            case (NamePattern p, _): bindings[p.Name] = value;
            return true;
            case (IntPattern p, Value.Integer v): return p.Value == v.Number;
            case (BoolPattern p, Value.BooleanValue v): return p.Value == v.Flag;
            case (StringPattern p, Value.StringValue v): return p.Value == v.Text;
            case (ConsPattern p, Value.ListValue v): return v.Values.Count != 0 && MatchPattern(p.Head, v.Values[0], bindings) && MatchPattern(p.Tail, new Value.ListValue(v.Values.Skip(1).ToList()), bindings);
            case (ListPattern p, Value.ListValue v): if (p.Elements.Count != v.Values.Count) return false;
            for (int i = 0; i < p.Elements.Count; i++) if (!MatchPattern(p.Elements[i], v.Values[i], bindings)) return false;
            return true;
            case (PairPattern p, Value.PairValue v): return MatchPattern(p.First, v.First, bindings) && MatchPattern(p.Second, v.Second, bindings);
            default: return false;
        }
    }
    public (Dictionary<string, Value> Environment, List<Value> Values) Group(Group group, Dictionary<string, Value> environment) {
        if (group.Recursive.HasValue) {
            Dictionary<string, Value> shared = new(environment);
            List<Value> closures = group.Bindings.Select(binding => {
                Lambda function = (Lambda)binding.Expression;
                return (Value)new Value.Closure(function.Parameter, function.Body, shared);
            }).ToList();
            for (int i = 0; i < group.Bindings.Count; i++) shared[group.Bindings[i].Name] = closures[i];
            return (new(shared), closures);
        }
        List<Value> values = group.Bindings.Select(binding => Expression(binding.Expression, environment)).ToList();
        Dictionary<string, Value> result = new(environment);
        for (int i = 0; i < group.Bindings.Count; i++) result[group.Bindings[i].Name] = values[i];
        return (result, values);
    }
    Value Apply(Value function, Value argument, Position position) {
        Calls++;
        if (function is Value.Closure closure) {
            Dictionary<string, Value> inner = new(closure.Environment);
            if (closure.Parameter.Name != null) inner[closure.Parameter.Name] = argument;
            return Expression(closure.Body, inner);
        } if (function is Value.Builtin builtin) return Program.ApplyBuiltin(builtin.Name, argument, position);
        throw new InvalidOperationException();
    }
    public Value Expression(Expr expression, Dictionary<string, Value> environment) {
        switch (expression) {
            case IntExpr e: return new Value.Integer(e.Value);
            case BoolExpr e: return new Value.BooleanValue(e.Value);
            case StringExpr e: return new Value.StringValue(e.Value);
            case NameExpr e: return environment[e.Name];
            case Lambda e: return new Value.Closure(e.Parameter, e.Body, new(environment));
            case Apply e: {
                Value function = Expression(e.Function, environment), argument = Expression(e.Argument, environment);
                return Apply(function, argument, e.Position);
            }
            case Negate e: return Checked(-((Value.Integer)Expression(e.Operand, environment)).Number, e.Position);
            case Binary e: {
                Value left = Expression(e.Left, environment);
                if (e.Op == "&&") return ((Value.BooleanValue)left).Flag ? Expression(e.Right, environment) : new Value.BooleanValue(false);
                if (e.Op == "||") return ((Value.BooleanValue)left).Flag ? new Value.BooleanValue(true) : Expression(e.Right, environment);
                Value right = Expression(e.Right, environment);
                if (e.Op is "+" or "-" or "*" or "/" or "mod") {
                    long a = ((Value.Integer)left).Number, b = ((Value.Integer)right).Number;
                    if (e.Op is "/" or "mod" && b == 0) throw new RuntimeError(e.OperatorPosition, "division by zero");
                    long value = e.Op switch {
                        "+" => a + b, "-" => a - b, "*" => a * b, "/" => a / b, _ => a - b * (a / b)
                    };
                    return Checked(value, e.OperatorPosition);
                }
                if (e.Op == "^") return new Value.StringValue(((Value.StringValue)left).Text + ((Value.StringValue)right).Text);
                if (e.Op == "::") return new Value.ListValue(new[] {
                    left
                }.Concat(((Value.ListValue)right).Values).ToList());
                int order = Compare(left, right, e.OperatorPosition);
                return new Value.BooleanValue(e.Op switch {
                    "=" => order == 0, "<>" => order != 0, "<" => order < 0, ">" => order > 0, "<=" => order <= 0, _ => order >= 0
                });
            }
            case Conditional e: return Expression(((Value.BooleanValue)Expression(e.Condition, environment)).Flag ? e.Yes : e.No, environment);
            case PairExpr e: {
                Value first = Expression(e.First, environment), second = Expression(e.Second, environment);
                return new Value.PairValue(first, second);
            }
            case ListExpr e: return new Value.ListValue(e.Elements.Select(element => Expression(element, environment)).ToList());
            case Match e: {
                Value matched = Expression(e.Value, environment);
                foreach (var (pattern, body) in e.Arms) {
                    Dictionary<string, Value> bindings = new();
                    if (MatchPattern(pattern, matched, bindings)) {
                        Dictionary<string, Value> inner = new(environment);
                        foreach (var (name, value) in bindings) inner[name] = value;
                        return Expression(body, inner);
                    }
                } throw new RuntimeError(e.Position, "match failure");
            }
            case LetIn e: {
                var (inner, _) = Group(e.Group, environment);
                return Expression(e.Body, inner);
            }
            default: throw new InvalidOperationException();
        }
    }
}
