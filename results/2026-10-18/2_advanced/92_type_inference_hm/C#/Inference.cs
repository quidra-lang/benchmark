using System;
using System.Collections.Generic;
using System.Linq;
abstract record TypeErrorKind {
    public sealed record Message(string Text) : TypeErrorKind;
    public sealed record Function(MLType Type) : TypeErrorKind;
    public sealed record Check(MLType Expected, MLType Found, UnifyFailure Failure) : TypeErrorKind;
}
sealed class TypeError(Position position, TypeErrorKind kind) : Exception {
    public Position Position {
        get;
    } = position;
    public TypeErrorKind Kind {
        get;
    } = kind;
}
sealed record Local(string Name, Position Position, Scheme Scheme);
sealed class Inference {
    public Unifier Unifier {
        get;
    } = new();
    public List<Local> Locals {
        get;
    } = new();
    public Dictionary<Position, (MLType Type, List<Pattern> Patterns)> Matches {
        get;
    } = new();
    public void Clear() {
        Locals.Clear();
        Matches.Clear();
    }
    TypeError Message(Position position, string text) => new(position, new TypeErrorKind.Message(text));
    void Check(MLType expected, MLType found, Position position) {
        try {
            Unifier.Unify(expected, found);
        } catch (UnifyFailure failure) {
            throw new TypeError(position, new TypeErrorKind.Check(expected, found, failure));
        }
    }
    public (Dictionary<string, Scheme> Environment, List<Scheme> Schemes) Group(Group group, Dictionary<string, Scheme> environment, bool local) {
        HashSet<string> names = new();
        foreach (Binding binding in group.Bindings) {
            if (!names.Add(binding.Name)) throw Message(binding.Position, $"variable '{binding.Name}' is bound twice in this let");
            if (group.Recursive.HasValue && binding.Expression is not Lambda) throw Message(binding.Position, $"'{binding.Name}' in let rec must be a function");
        }
        Dictionary<string, Scheme> recursive = new(environment);
        List<MLType> types = new();
        if (group.Recursive.HasValue) {
            foreach (Binding binding in group.Bindings) {
                MLType type = Unifier.Fresh();
                recursive[binding.Name] = Scheme.Mono(type);
                types.Add(type);
            } for (int i = 0; i < group.Bindings.Count; i++) {
                Binding binding = group.Bindings[i];
                MLType found = Expression(binding.Expression, recursive);
                Check(types[i], found, binding.Position);
            }
        }
        else foreach (Binding binding in group.Bindings) types.Add(Expression(binding.Expression, environment));
        List<Scheme> schemes = types.Select(type => Unifier.Generalize(type, environment)).ToList();
        Dictionary<string, Scheme> result = new(environment);
        for (int i = 0; i < group.Bindings.Count; i++) {
            Binding binding = group.Bindings[i];
            Scheme scheme = schemes[i];
            result[binding.Name] = scheme;
            if (local) Locals.Add(new(binding.Name, binding.Position, scheme));
        } return (result, schemes);
    }
    public MLType Expression(Expr expression, Dictionary<string, Scheme> environment) {
        switch (expression) {
            case IntExpr: return MLType.Int;
            case BoolExpr: return MLType.Bool;
            case StringExpr: return MLType.String;
            case NameExpr e: {
                if (environment.TryGetValue(e.Name, out Scheme? scheme)) return Unifier.Instantiate(scheme);
                string? candidate = environment.Keys.Select(name => (Distance: Program.EditDistance(e.Name, name), Name: name)).Where(pair => pair.Distance <= 2 && pair.Distance < e.Name.Length).OrderBy(pair => pair.Distance).ThenBy(pair => pair.Name, StringComparer.Ordinal).Select(pair => pair.Name).FirstOrDefault();
                throw Message(e.Position, $"unbound variable '{e.Name}'" + (candidate == null ? "" : $" (did you mean '{candidate}'?)"));
            }
            case Lambda e: {
                MLType argument = Unifier.Fresh();
                Dictionary<string, Scheme> inner = new(environment);
                if (e.Parameter.Name != null) inner[e.Parameter.Name] = Scheme.Mono(argument);
                MLType result = Expression(e.Body, inner);
                return new MLType.Function(argument, result);
            }
            case Apply e: {
                MLType function = Unifier.Resolve(Expression(e.Function, environment)), expected, result;
                if (function is MLType.Variable variable) {
                    expected = Unifier.Fresh();
                    result = Unifier.Fresh();
                    Unifier.Bind(variable.Id, new MLType.Function(expected, result));
                }
                else if (function is MLType.Function f) {
                    expected = f.Argument;
                    result = f.Result;
                } else throw new TypeError(e.Function.Position, new TypeErrorKind.Function(function));
                MLType found = Expression(e.Argument, environment);
                Check(expected, found, e.Argument.Position);
                return result;
            }
            case Binary e: {
                MLType a, b, result;
                switch (e.Op) {
                    case "+": case "-": case "*": case "/": case "mod": a = b = result = MLType.Int;
                    break;
                    case "^": a = b = result = MLType.String;
                    break;
                    case "&&": case "||": a = b = result = MLType.Bool;
                    break;
                    case "::": a = Unifier.Fresh();
                    b = result = new MLType.ListType(a);
                    break;
                    default: a = b = Unifier.Fresh();
                    result = MLType.Bool;
                    break;
                }
                MLType first = Expression(e.Left, environment);
                Check(a, first, e.Left.Position);
                MLType second = Expression(e.Right, environment);
                Check(b, second, e.Right.Position);
                return result;
            }
            case Negate e: {
                MLType found = Expression(e.Operand, environment);
                Check(MLType.Int, found, e.Operand.Position);
                return MLType.Int;
            }
            case Conditional e: {
                MLType found = Expression(e.Condition, environment);
                Check(MLType.Bool, found, e.Condition.Position);
                MLType a = Expression(e.Yes, environment), b = Expression(e.No, environment);
                Check(a, b, e.No.Position);
                return a;
            }
            case PairExpr e: {
                MLType first = Expression(e.First, environment), second = Expression(e.Second, environment);
                return new MLType.PairType(first, second);
            }
            case ListExpr e: {
                MLType type = Unifier.Fresh();
                foreach (Expr element in e.Elements) {
                    MLType found = Expression(element, environment);
                    Check(type, found, element.Position);
                } return new MLType.ListType(type);
            }
            case Match e: {
                MLType type = Expression(e.Value, environment), result = Unifier.Fresh();
                foreach (var (pattern, body) in e.Arms) {
                    Dictionary<string, MLType> bindings = new();
                    MLType found = Pattern(pattern, bindings);
                    Check(type, found, pattern.Position);
                    Dictionary<string, Scheme> inner = new(environment);
                    foreach (var (name, boundType) in bindings) inner[name] = Scheme.Mono(boundType);
                    MLType bodyType = Expression(body, inner);
                    Check(result, bodyType, body.Position);
                }
                Matches[e.Position] = (type, e.Arms.Select(arm => arm.Pattern).ToList());
                return result;
            }
            case LetIn e: {
                var (inner, _) = Group(e.Group, environment, true);
                return Expression(e.Body, inner);
            }
            default: throw new InvalidOperationException();
        }
    }
    MLType Pattern(Pattern pattern, Dictionary<string, MLType> bindings) {
        switch (pattern) {
            case WildPattern: return Unifier.Fresh();
            case NamePattern p: if (bindings.ContainsKey(p.Name)) throw Message(p.Position, $"variable '{p.Name}' is bound twice in this pattern");
            MLType type = Unifier.Fresh();
            bindings[p.Name] = type;
            return type;
            case IntPattern: return MLType.Int;
            case BoolPattern: return MLType.Bool;
            case StringPattern: return MLType.String;
            case ConsPattern p: {
                MLType element = Unifier.Fresh(), head = Pattern(p.Head, bindings);
                Check(element, head, p.Head.Position);
                MLType tail = Pattern(p.Tail, bindings), list = new MLType.ListType(element);
                Check(list, tail, p.Tail.Position);
                return list;
            }
            case ListPattern p: {
                MLType element = Unifier.Fresh();
                foreach (Pattern value in p.Elements) {
                    MLType found = Pattern(value, bindings);
                    Check(element, found, value.Position);
                } return new MLType.ListType(element);
            }
            case PairPattern p: {
                MLType first = Pattern(p.First, bindings), second = Pattern(p.Second, bindings);
                return new MLType.PairType(first, second);
            }
            default: throw new InvalidOperationException();
        }
    }
}
