using System;
using System.IO;
using System.Text;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
sealed class TypePrinter(Unifier unifier, HashSet<int>? quantified = null) {
    readonly Dictionary<int, string> names = new();
    public string Write(MLType type) {
        switch (unifier.Resolve(type)) {
            case MLType.IntType: return "int";
            case MLType.BoolType: return "bool";
            case MLType.StringType: return "string";
            case MLType.Variable v: if (names.TryGetValue(v.Id, out string? old)) return old;
            int k = names.Count;
            string name = "'" + (quantified != null && !quantified.Contains(v.Id) ? "_" : "") + (char)('a' + k % 26) + (k >= 26 ? (k / 26).ToString(CultureInfo.InvariantCulture) : "");
            names[v.Id] = name;
            return name;
            case MLType.ListType l: return Wrap(l.Element, true) + " list";
            case MLType.PairType p: return Wrap(p.First, true) + " * " + Wrap(p.Second, true);
            case MLType.Function f: return Wrap(f.Argument, false) + " -> " + Write(f.Result);
            default: throw new InvalidOperationException();
        }
    }
    string Wrap(MLType type, bool pair) {
        MLType resolved = unifier.Resolve(type);
        string text = Write(resolved);
        return resolved is MLType.Function || pair && resolved is MLType.PairType ? "(" + text + ")" : text;
    }
}
abstract record Cover {
    public sealed record Wild : Cover;
    public sealed record Constructor(string Name, List<Cover> Arguments) : Cover;
}
readonly record struct Reference(Position Target, bool Tail);
sealed record Warning(Position Position, int Order, string Message);
sealed record Signature(Position Position, TypeExpression Type);
sealed class Diagnostic(Position position, string text) : Exception(text) {
    public Position Position {
        get;
    } = position;
    public string Text {
        get;
    } = text;
}
static class Program {
    public static string Quote(string value) {
        StringBuilder output = new("\"");
        foreach (char c in value) output.Append(c switch {
            '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\t' => "\\t", _ => c.ToString()
        });
        return output.Append('"').ToString();
    }
    static string ValueString(Value value) => value switch {
        Value.Integer n => n.Number.ToString(CultureInfo.InvariantCulture), Value.BooleanValue b => b.Flag ? "true" : "false", Value.StringValue s => Quote(s.Text), Value.PairValue p => $"({ValueString(p.First)}, {ValueString(p.Second)})", Value.ListValue l => "[" + string.Join("; ", l.Values.Select(ValueString)) + "]", _ => "<fun>"
    };
    public static int EditDistance(string a, string b) {
        int[] row = Enumerable.Range(0, b.Length + 1).ToArray();
        for (int i = 0; i < a.Length; i++) {
            int[] next = new int[b.Length + 1];
            next[0] = i + 1;
            for (int j = 0; j < b.Length; j++) next[j + 1] = Math.Min(Math.Min(next[j] + 1, row[j + 1] + 1), row[j] + (a[i] == b[j] ? 0 : 1));
            row = next;
        } return row[b.Length];
    }
    static string ErrorMessage(TypeError error, Unifier unifier) {
        TypePrinter printer = new(unifier);
        switch (error.Kind) {
            case TypeErrorKind.Message message: return message.Text;
            case TypeErrorKind.Function function: return "expected a function but found " + printer.Write(function.Type);
            case TypeErrorKind.Check check: {
                string text = $"expected {printer.Write(check.Expected)} but found {printer.Write(check.Found)}";
                UnifyFailure failure = check.Failure;
                if (failure.Occurs) {
                    MLType variable = failure.Expected is MLType.Variable ? failure.Expected : failure.Found, other = failure.Expected is MLType.Variable ? failure.Found : failure.Expected;
                    text += $" (infinite type {printer.Write(variable)} = {printer.Write(other)})";
                }
                else if (failure.Nested) text += $" ({printer.Write(failure.Expected)} vs {printer.Write(failure.Found)})";
                return text;
            }
            default: throw new InvalidOperationException();
        }
    }
    static MLType SignatureType(TypeExpression type, Unifier unifier, Dictionary<string, MLType> variables) {
        switch (type) {
            case TypeExpression.Primitive p: return p.Name == "int" ? MLType.Int : p.Name == "bool" ? MLType.Bool : MLType.String;
            case TypeExpression.Variable v: if (variables.TryGetValue(v.Name, out MLType? old)) return old;
            MLType fresh = unifier.Fresh();
            variables[v.Name] = fresh;
            return fresh;
            case TypeExpression.ListType l: return new MLType.ListType(SignatureType(l.Element, unifier, variables));
            case TypeExpression.PairType p: return new MLType.PairType(SignatureType(p.First, unifier, variables), SignatureType(p.Second, unifier, variables));
            case TypeExpression.Function f: return new MLType.Function(SignatureType(f.Argument, unifier, variables), SignatureType(f.Result, unifier, variables));
            default: throw new InvalidOperationException();
        }
    }
    static bool SignatureMatches(MLType inferred, MLType declared, Unifier unifier, Dictionary<int, MLType> assigned) {
        MLType a = unifier.Resolve(inferred), b = unifier.Resolve(declared);
        if (a is MLType.Variable v) {
            if (assigned.TryGetValue(v.Id, out MLType? old)) return old == b;
            assigned[v.Id] = b;
            return true;
        }
        return (a, b) switch {
            (MLType.ListType x, MLType.ListType y) => SignatureMatches(x.Element, y.Element, unifier, assigned), (MLType.PairType x, MLType.PairType y) => SignatureMatches(x.First, y.First, unifier, assigned) && SignatureMatches(x.Second, y.Second, unifier, assigned), (MLType.Function x, MLType.Function y) => SignatureMatches(x.Argument, y.Argument, unifier, assigned) && SignatureMatches(x.Result, y.Result, unifier, assigned), _ => a == b
        };
    }
    static string TypeSyntax(TypeExpression type) {
        string Wrap(TypeExpression t, bool pair) {
            string text = TypeSyntax(t);
            return t is TypeExpression.Function || pair && t is TypeExpression.PairType ? "(" + text + ")" : text;
        }
        return type switch {
            TypeExpression.Primitive p => p.Name, TypeExpression.Variable v => v.Name, TypeExpression.ListType l => Wrap(l.Element, true) + " list", TypeExpression.PairType p => Wrap(p.First, true) + " * " + Wrap(p.Second, true), TypeExpression.Function f => Wrap(f.Argument, false) + " -> " + TypeSyntax(f.Result), _ => throw new InvalidOperationException()
        };
    }
    static string PatternString(Pattern pattern) => pattern switch {
        WildPattern => "_", NamePattern p => p.Name, IntPattern p => p.Value.ToString(CultureInfo.InvariantCulture), BoolPattern p => p.Value ? "true" : "false", StringPattern p => Quote(p.Value), ListPattern p => "[" + string.Join("; ", p.Elements.Select(PatternString)) + "]", PairPattern p => $"({PatternString(p.First)}, {PatternString(p.Second)})", ConsPattern p => (p.Head is ConsPattern ? "(" + PatternString(p.Head) + ")" : PatternString(p.Head)) + " :: " + PatternString(p.Tail), _ => throw new InvalidOperationException()
    };
    static string GroupString(Group group) => "let " + (group.Recursive.HasValue ? "rec " : "") + string.Join(" and ", group.Bindings.Select(binding => {
        Expr body = binding.Expression;
        List<string> names = new() {
            binding.Name
        };
        while (body is Lambda lambda) {
            names.Add(lambda.Parameter.Name ?? "_");
            body = lambda.Body;
        } return string.Join(" ", names) + " = " + ExpressionString(body, 0);
    }));
    static bool EndsInMatch(Expr expression) => expression switch {
        Match => true, LetIn e => EndsInMatch(e.Body), Lambda e => EndsInMatch(e.Body), Conditional e => EndsInMatch(e.No), _ => false
    };
    static string ExpressionString(Expr expression, int required) {
        int strength;
        string text;
        switch (expression) {
            case IntExpr e: strength = 9;
            text = e.Value.ToString(CultureInfo.InvariantCulture);
            break;
            case BoolExpr e: strength = 9;
            text = e.Value ? "true" : "false";
            break;
            case StringExpr e: strength = 9;
            text = Quote(e.Value);
            break;
            case NameExpr e: strength = 9;
            text = e.Name;
            break;
            case Lambda e: {
                Expr body = e;
                List<string> names = new();
                while (body is Lambda lambda) {
                    names.Add(lambda.Parameter.Name ?? "_");
                    body = lambda.Body;
                } strength = 0;
                text = "fun " + string.Join(" ", names) + " -> " + ExpressionString(body, 0);
                break;
            }
            case Apply e: strength = 8;
            text = ExpressionString(e.Function, 8) + " " + ExpressionString(e.Argument, 9);
            break;
            case Binary e: {
                int k = Parser.Precedence(e.Op);
                bool right = Parser.RightAssociative(e.Op);
                strength = k;
                text = ExpressionString(e.Left, k + (right ? 1 : 0)) + " " + e.Op + " " + ExpressionString(e.Right, k + (right ? 0 : 1));
                break;
            }
            case Negate e: strength = 7;
            text = "-" + ExpressionString(e.Operand, 7);
            break;
            case Conditional e: strength = 0;
            text = $"if {ExpressionString(e.Condition, 0)} then {ExpressionString(e.Yes, 0)} else {ExpressionString(e.No, 0)}";
            break;
            case PairExpr e: strength = 9;
            text = $"({ExpressionString(e.First, 0)}, {ExpressionString(e.Second, 0)})";
            break;
            case ListExpr e: strength = 9;
            text = "[" + string.Join("; ", e.Elements.Select(element => ExpressionString(element, 0))) + "]";
            break;
            case LetIn e: strength = 0;
            text = GroupString(e.Group) + " in " + ExpressionString(e.Body, 0);
            break;
            case Match e: strength = 0;
            text = "match " + ExpressionString(e.Value, 0) + " with " + string.Join(" | ", e.Arms.Select((arm, i) => {
                string body = ExpressionString(arm.Body, 0);
                return PatternString(arm.Pattern) + " -> " + (i + 1 < e.Arms.Count && EndsInMatch(arm.Body) ? "(" + body + ")" : body);
            }));
            break;
            default: throw new InvalidOperationException();
        }
        return strength < required ? "(" + text + ")" : text;
    }
    static string ItemString(Item item) => item switch {
        Item.Signature s => $"val {s.Name} : {TypeSyntax(s.Type)};;", Item.Declaration d => GroupString(d.Group) + ";;", Item.Expression e => ExpressionString(e.Expr, 0) + ";;", _ => throw new InvalidOperationException()
    };
    static Cover CoverPattern(Pattern pattern) {
        switch (pattern) {
            case WildPattern: case NamePattern: return new Cover.Wild();
            case IntPattern p: return new Cover.Constructor("i" + p.Value, new());
            case StringPattern p: return new Cover.Constructor("s" + Quote(p.Value), new());
            case BoolPattern p: return new Cover.Constructor(p.Value ? "true" : "false", new());
            case ListPattern p: {
                Cover tail = new Cover.Constructor("nil", new());
                foreach (Pattern head in p.Elements.AsEnumerable().Reverse()) tail = new Cover.Constructor("cons", new() {
                    CoverPattern(head), tail
                });
                return tail;
            }
            case ConsPattern p: return new Cover.Constructor("cons", new() {
                CoverPattern(p.Head), CoverPattern(p.Tail)
            });
            case PairPattern p: return new Cover.Constructor("pair", new() {
                CoverPattern(p.First), CoverPattern(p.Second)
            });
            default: throw new InvalidOperationException();
        }
    }
    static List<MLType> ConstructorArguments(MLType type, string name) => type switch {
        MLType.ListType l when name == "cons" => new() {
            l.Element, type
        }, MLType.PairType p => new() {
            p.First, p.Second
        }, _ => new()
    };
    static List<List<Cover>> Specialize(List<List<Cover>> matrix, string name, int arity) {
        List<List<Cover>> result = new();
        foreach (List<Cover> row in matrix) {
            List<Cover> prefix;
            if (row[0] is Cover.Wild) prefix = Enumerable.Range(0, arity).Select(_ => (Cover)new Cover.Wild()).ToList();
            else if (row[0] is Cover.Constructor constructor && constructor.Name == name) prefix = new(constructor.Arguments);
            else continue;
            prefix.AddRange(row.Skip(1));
            result.Add(prefix);
        } return result;
    }
    static bool Useful(List<List<Cover>> matrix, List<Cover> vector, List<MLType> types) {
        if (vector.Count == 0) return matrix.Count == 0;
        if (vector[0] is Cover.Constructor constructor) return Useful(Specialize(matrix, constructor.Name, constructor.Arguments.Count), constructor.Arguments.Concat(vector.Skip(1)).ToList(), ConstructorArguments(types[0], constructor.Name).Concat(types.Skip(1)).ToList());
        List<string> family = types[0] switch {
            MLType.BoolType => new() {
                "false", "true"
            }, MLType.ListType => new() {
                "nil", "cons"
            }, MLType.PairType => new() {
                "pair"
            }, _ => new()
        };
        HashSet<string> present = matrix.Select(row => row[0]).OfType<Cover.Constructor>().Select(c => c.Name).ToHashSet();
        if (family.Count > 0 && family.All(present.Contains)) {
            foreach (string name in family) {
                List<MLType> arguments = ConstructorArguments(types[0], name);
                if (Useful(Specialize(matrix, name, arguments.Count), Enumerable.Range(0, arguments.Count).Select(_ => (Cover)new Cover.Wild()).Concat(vector.Skip(1)).ToList(), arguments.Concat(types.Skip(1)).ToList())) return true;
            } return false;
        }
        return Useful(matrix.Where(row => row[0] is Cover.Wild).Select(row => row.Skip(1).ToList()).ToList(), vector.Skip(1).ToList(), types.Skip(1).ToList());
    }
    static List<(string Name, Position Position)> PatternNames(Pattern pattern) => pattern switch {
        NamePattern p => new() {
            (p.Name, p.Position)
        }, ConsPattern p => PatternNames(p.Head).Concat(PatternNames(p.Tail)).ToList(), PairPattern p => PatternNames(p.First).Concat(PatternNames(p.Second)).ToList(), ListPattern p => p.Elements.SelectMany(PatternNames).ToList(), _ => new()
    };
    static Dictionary<string, Position> AddScope(Dictionary<string, Position> scope, IEnumerable<(string Name, Position Position)> names) {
        Dictionary<string, Position> result = new(scope);
        foreach (var (name, position) in names) result[name] = position;
        return result;
    }
    static List<Reference> PureReferences(Expr expression, Dictionary<string, Position> scope, bool tail) {
        switch (expression) {
            case NameExpr e: return scope.TryGetValue(e.Name, out Position target) ? new() {
                new(target, false)
            } : new();
            case Lambda e: {
                Dictionary<string, Position> inner = new(scope);
                if (e.Parameter.Name != null) inner[e.Parameter.Name] = e.Parameter.Position;
                return PureReferences(e.Body, inner, false);
            }
            case Apply e: {
                Expr head = e;
                List<Expr> arguments = new();
                while (head is Apply application) {
                    arguments.Add(application.Argument);
                    head = application.Function;
                } List<Reference> references = head is NameExpr name ? scope.TryGetValue(name.Name, out Position called) ? new() {
                    new(called, tail)
                } : new() : PureReferences(head, scope, false);
                foreach (Expr argument in arguments.AsEnumerable().Reverse()) references.AddRange(PureReferences(argument, scope, false));
                return references;
            }
            case Binary e: return PureReferences(e.Left, scope, false).Concat(PureReferences(e.Right, scope, tail && e.Op is "&&" or "||")).ToList();
            case Negate e: return PureReferences(e.Operand, scope, false);
            case Conditional e: return PureReferences(e.Condition, scope, false).Concat(PureReferences(e.Yes, scope, tail)).Concat(PureReferences(e.No, scope, tail)).ToList();
            case PairExpr e: return PureReferences(e.First, scope, false).Concat(PureReferences(e.Second, scope, false)).ToList();
            case ListExpr e: return e.Elements.SelectMany(element => PureReferences(element, scope, false)).ToList();
            case Match e: return PureReferences(e.Value, scope, false).Concat(e.Arms.SelectMany(arm => PureReferences(arm.Body, AddScope(scope, PatternNames(arm.Pattern)), tail))).ToList();
            case LetIn e: {
                Dictionary<string, Position> inner = AddScope(scope, e.Group.Bindings.Select(binding => (binding.Name, binding.Position)));
                return e.Group.Bindings.SelectMany(binding => PureReferences(binding.Expression, e.Group.Recursive.HasValue ? inner : scope, false)).Concat(PureReferences(e.Body, inner, tail)).ToList();
            }
            default: return new();
        }
    }
    sealed class Inspection {
        public List<Warning> Warnings {
            get;
        } = new();
        public Dictionary<Position, string> Classifications {
            get;
        } = new();
        readonly Dictionary<Position, string> candidates = new();
        public Dictionary<string, Position> Group(Group group, Dictionary<string, Position> scope, bool top, Inference context) {
            Dictionary<string, Position> inner = new(scope);
            foreach (Binding binding in group.Bindings) {
                inner[binding.Name] = binding.Position;
                if (!top) candidates[binding.Position] = binding.Name;
            }
            Dictionary<string, Position> rhs = group.Recursive.HasValue ? inner : scope;
            foreach (Binding binding in group.Bindings) Walk(binding.Expression, rhs, context);
            if (group.Recursive.HasValue) {
                HashSet<Position> names = group.Bindings.Select(binding => binding.Position).ToHashSet();
                List<Reference> references = group.Bindings.SelectMany(binding => PureReferences(binding.Expression, inner, false)).ToList();
                if (references.All(reference => !names.Contains(reference.Target))) Warnings.Add(new(group.Recursive.Value, 3, "unused rec flag"));
                foreach (Binding binding in group.Bindings) {
                    Expr body = binding.Expression;
                    Dictionary<string, Position> bodyScope = new(inner);
                    while (body is Lambda lambda) {
                        if (lambda.Parameter.Name != null) bodyScope[lambda.Parameter.Name] = lambda.Parameter.Position;
                        body = lambda.Body;
                    } List<Reference> refs = PureReferences(body, bodyScope, true).Where(reference => names.Contains(reference.Target)).ToList();
                    if (refs.Count > 0) Classifications[binding.Position] = refs.All(reference => reference.Tail) ? "tail recursive" : "recursive";
                }
            }
            return inner;
        }
        public void Walk(Expr expression, Dictionary<string, Position> scope, Inference context) {
            switch (expression) {
                case Lambda e: {
                    Dictionary<string, Position> inner = new(scope);
                    if (e.Parameter.Name != null) {
                        candidates[e.Parameter.Position] = e.Parameter.Name;
                        inner[e.Parameter.Name] = e.Parameter.Position;
                    } Walk(e.Body, inner, context);
                    break;
                }
                case Apply e: Walk(e.Function, scope, context);
                Walk(e.Argument, scope, context);
                break;
                case PairExpr e: Walk(e.First, scope, context);
                Walk(e.Second, scope, context);
                break;
                case Binary e: Walk(e.Left, scope, context);
                Walk(e.Right, scope, context);
                break;
                case Negate e: Walk(e.Operand, scope, context);
                break;
                case Conditional e: Walk(e.Condition, scope, context);
                Walk(e.Yes, scope, context);
                Walk(e.No, scope, context);
                break;
                case ListExpr e: foreach (Expr element in e.Elements) Walk(element, scope, context);
                break;
                case LetIn e: {
                    Dictionary<string, Position> inner = Group(e.Group, scope, false, context);
                    Walk(e.Body, inner, context);
                    break;
                }
                case Match e: {
                    var (originalType, patterns) = context.Matches[e.Position];
                    MLType type = context.Unifier.Resolve(originalType);
                    List<List<Cover>> matrix = new();
                    for (int i = 0; i < patterns.Count; i++) {
                        Pattern pattern = patterns[i];
                        Cover candidate = CoverPattern(pattern);
                        if (i > 0 && !Useful(matrix, new() {
                            candidate
                        }, new() {
                            type
                        })) Warnings.Add(new(pattern.Position, 2, "this match case is unused"));
                        matrix.Add(new() {
                            candidate
                        });
                    }
                    if (Useful(matrix, new() {
                        new Cover.Wild()
                    }, new() {
                        type
                    })) Warnings.Add(new(e.Position, 1, "this match is not exhaustive"));
                    Walk(e.Value, scope, context);
                    foreach (var (pattern, body) in e.Arms) {
                        List<(string, Position)> names = PatternNames(pattern);
                        foreach (var (name, position) in names) candidates[position] = name;
                        Walk(body, AddScope(scope, names), context);
                    } break;
                }
            }
        }
        public void Finish(List<Reference> references) {
            HashSet<Position> used = references.Select(reference => reference.Target).ToHashSet();
            foreach (var (position, name) in candidates) if (!name.StartsWith('_') && !used.Contains(position)) Warnings.Add(new(position, 4, $"unused variable '{name}'"));
            Warnings.Sort((a, b) => {
                int order = a.Position.CompareTo(b.Position);
                return order == 0 ? a.Order.CompareTo(b.Order) : order;
            });
        }
    }
    static Inspection Inspect(Item item, Dictionary<string, Position> scope, Inference context) {
        Inspection inspection = new();
        List<Reference> references;
        if (item is Item.Declaration declaration) {
            Dictionary<string, Position> inner = inspection.Group(declaration.Group, scope, true, context);
            references = declaration.Group.Bindings.SelectMany(binding => PureReferences(binding.Expression, declaration.Group.Recursive.HasValue ? inner : scope, false)).ToList();
        }
        else if (item is Item.Expression expression) {
            inspection.Walk(expression.Expr, scope, context);
            references = PureReferences(expression.Expr, scope, false);
        } else references = new();
        inspection.Finish(references);
        return inspection;
    }
    static (Dictionary<string, Scheme> Types, Dictionary<string, Value> Values) Builtins(Unifier unifier) {
        Dictionary<string, Scheme> types = new();
        MLType a = unifier.Fresh(), b = unifier.Fresh(), fst = new MLType.Function(new MLType.PairType(a, b), a);
        types["fst"] = new(fst, unifier.Variables(fst));
        MLType c = unifier.Fresh(), d = unifier.Fresh(), snd = new MLType.Function(new MLType.PairType(c, d), d);
        types["snd"] = new(snd, unifier.Variables(snd));
        types["not"] = Scheme.Mono(new MLType.Function(MLType.Bool, MLType.Bool));
        types["string_of_int"] = Scheme.Mono(new MLType.Function(MLType.Int, MLType.String));
        MLType result = unifier.Fresh(), fail = new MLType.Function(MLType.String, result);
        types["failwith"] = new(fail, unifier.Variables(fail));
        return (types, new[] {
            "fst", "snd", "not", "string_of_int", "failwith"
        }.ToDictionary(name => name, name => (Value)new Value.Builtin(name)));
    }
    public static Value ApplyBuiltin(string name, Value argument, Position position) => name switch {
        "fst" => ((Value.PairValue)argument).First, "snd" => ((Value.PairValue)argument).Second, "not" => new Value.BooleanValue(!((Value.BooleanValue)argument).Flag), "string_of_int" => new Value.StringValue(((Value.Integer)argument).Number.ToString(CultureInfo.InvariantCulture)), "failwith" => throw new RuntimeError(position, "failure " + Quote(((Value.StringValue)argument).Text)), _ => throw new InvalidOperationException()
    };
    static void Report(Position position, string kind, string message, List<List<string>> sources, List<string> output) {
        string name = new[] {
            "prelude.ml", "program.ml"
        }[position.File];
        output.Add($"{name}:{position.Line}:{position.Column}: {kind}: {message}");
        if (position.Line <= sources[position.File].Count) {
            output.Add("    " + sources[position.File][position.Line - 1]);
            output.Add(new string(' ', position.Column + 3) + "^");
        }
    }
    static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n");
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        string[] fileNames = {
            "prelude.ml", "program.ml"
        };
        List<string> texts = fileNames.Select(name => File.ReadAllText("input/" + name)).ToList();
        List<List<string>> sources = texts.Select(text => text.Split('\n').SkipLast(1).ToList()).ToList();
        Inference context = new();
        Evaluator evaluator = new();
        var (typeEnvironment, valueEnvironment) = Builtins(context.Unifier);
        Dictionary<string, Position> scope = new();
        List<string> types = new(), values = new(), errors = new(), formatted = new();
        int[,] statistics = new int[2, 7];
        for (int file = 0; file < 2; file++) {
            types.Add($"== {fileNames[file]} ==");
            values.Add($"== {fileNames[file]} ==");
            formatted.Add($"(* {fileNames[file]} *)");
            Dictionary<string, Signature> pending = new();
            Parser parser = new(Lexer.Lex(texts[file], file));
            evaluator.Calls = 0;
            while (parser.Peek.Kind != "eof") {
                statistics[file, 0]++;
                Item item;
                try {
                    item = parser.ReadItem();
                } catch (SyntaxError error) {
                    Token token = error.Token;
                    string message = token.Kind == "invalid" ? token.Value : token.Kind == "eof" ? "unexpected end of file" : $"unexpected '{token.Spelling}'";
                    statistics[file, 2]++;
                    Report(token.Position, "syntax error", message, sources, errors);
                    parser.Recover();
                    continue;
                }
                formatted.Add(ItemString(item));
                if (item is Item.Signature signatureItem) {
                    if (pending.TryGetValue(signatureItem.Name, out Signature? old)) {
                        statistics[file, 5]++;
                        Report(old.Position, "warning", $"signature for '{signatureItem.Name}' is never used", sources, errors);
                    } pending[signatureItem.Name] = new(signatureItem.Position, signatureItem.Type);
                    continue;
                }
                context.Clear();
                Dictionary<string, Scheme> nextTypes;
                List<Scheme> schemes;
                MLType? expressionType;
                try {
                    if (item is Item.Declaration declaration) {
                        List<Signature?> signatures = declaration.Group.Bindings.Select(binding => {
                            pending.Remove(binding.Name, out Signature? signature);
                            return signature;
                        }).ToList();
                        var (next, inferred) = context.Group(declaration.Group, typeEnvironment, false);
                        for (int i = 0; i < signatures.Count; i++) if (signatures[i] is {
                        } signature) {
                            MLType declared = SignatureType(signature.Type, context.Unifier, new());
                            if (!SignatureMatches(inferred[i].Type, declared, context.Unifier, new())) {
                                TypePrinter printer = new(context.Unifier);
                                throw new Diagnostic(declaration.Group.Bindings[i].Position, $"'{declaration.Group.Bindings[i].Name}' has type {printer.Write(inferred[i].Type)} but its signature is {printer.Write(declared)}");
                            } inferred[i] = new(declared, context.Unifier.Variables(declared));
                            next[declaration.Group.Bindings[i].Name] = inferred[i];
                        }
                        nextTypes = next;
                        schemes = inferred;
                        expressionType = null;
                    } else {
                        expressionType = context.Expression(((Item.Expression)item).Expr, typeEnvironment);
                        nextTypes = typeEnvironment;
                        schemes = new();
                    }
                } catch (TypeError error) {
                    statistics[file, 3]++;
                    Report(error.Position, "type error", ErrorMessage(error, context.Unifier), sources, errors);
                    continue;
                } catch (Diagnostic error) {
                    statistics[file, 3]++;
                    Report(error.Position, "type error", error.Text, sources, errors);
                    continue;
                }
                Inspection inspected = Inspect(item, scope, context);
                string Classification(Position position) => inspected.Classifications.TryGetValue(position, out string? classification) ? " (" + classification + ")" : "";
                if (item is Item.Declaration typedDeclaration) for (int i = 0; i < typedDeclaration.Group.Bindings.Count; i++) {
                    Binding binding = typedDeclaration.Group.Bindings[i];
                    types.Add($"{binding.Name} : {new TypePrinter(context.Unifier).Write(schemes[i].Type)}" + Classification(binding.Position));
                } else types.Add("- : " + new TypePrinter(context.Unifier).Write(expressionType!));
                foreach (Local local in context.Locals.OrderBy(entry => entry.Position)) types.Add($"  {local.Name} ({local.Position.Line}:{local.Position.Column}) : {new TypePrinter(context.Unifier, local.Scheme.Quantified).Write(local.Scheme.Type)}" + Classification(local.Position));
                foreach (Warning warning in inspected.Warnings) {
                    statistics[file, 5]++;
                    Report(warning.Position, "warning", warning.Message, sources, errors);
                }
                Dictionary<string, Value> nextValues;
                List<Value> evaluated;
                try {
                    if (item is Item.Declaration declaration) (nextValues, evaluated) = evaluator.Group(declaration.Group, valueEnvironment);
                    else {
                        evaluated = new() {
                            evaluator.Expression(((Item.Expression)item).Expr, valueEnvironment)
                        };
                        nextValues = valueEnvironment;
                    }
                } catch (RuntimeError error) {
                    statistics[file, 4]++;
                    Report(error.Position, "runtime error", error.Reason, sources, errors);
                    continue;
                }
                if (item is Item.Declaration valueDeclaration) {
                    for (int i = 0; i < valueDeclaration.Group.Bindings.Count; i++) {
                        Binding binding = valueDeclaration.Group.Bindings[i];
                        values.Add(binding.Name + " = " + ValueString(evaluated[i]));
                        scope[binding.Name] = binding.Position;
                    } statistics[file, 1] += valueDeclaration.Group.Bindings.Count;
                } else values.Add("- = " + ValueString(evaluated[0]));
                typeEnvironment = nextTypes;
                valueEnvironment = nextValues;
            }
            foreach (var (name, signature) in pending.OrderBy(pair => pair.Value.Position)) {
                statistics[file, 5]++;
                Report(signature.Position, "warning", $"signature for '{name}' is never used", sources, errors);
            } statistics[file, 6] = evaluator.Calls;
        }
        errors.Add("== summary ==");
        for (int file = 0; file < 2; file++) errors.Add($"{fileNames[file]}: items={statistics[file, 0]} bindings={statistics[file, 1]} syntax={statistics[file, 2]} type={statistics[file, 3]} runtime={statistics[file, 4]} warnings={statistics[file, 5]} calls={statistics[file, 6]}");
        Write("types.txt", types);
        Write("values.txt", values);
        Write("errors.txt", errors);
        Write("formatted.ml", formatted);
    }
}
