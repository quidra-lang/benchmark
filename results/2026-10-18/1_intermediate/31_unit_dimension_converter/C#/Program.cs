using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

sealed class CommandError(string message) : Exception("ERROR " + message) {}

readonly record struct Fraction : IComparable<Fraction>
{
    public long Numerator { get; }
    public long Denominator { get; }
    public static Fraction One => new(1);
    public bool IsZero => Numerator == 0;

    public Fraction(long numerator, long denominator = 1)
    {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long a = Math.Abs(numerator), b = denominator;
        while (b != 0) (a, b) = (b, a % b);
        Numerator = numerator / a;
        Denominator = denominator / a;
    }

    public static Fraction Parse(string text)
    {
        bool negative = text.StartsWith('-');
        string body = negative ? text[1..] : text;
        int separator = body.IndexOfAny(['.', '/']);
        string first = separator < 0 ? body : body[..separator];
        string second = separator < 0 ? "1" : body[(separator + 1)..];
        if (!Digits(first) || !Digits(second)) throw new CommandError($"BAD NUMBER {text}");
        long numerator = long.Parse(first), denominator = 1;
        if (separator >= 0 && body[separator] == '/') {
            denominator = long.Parse(second);
            if (denominator == 0) throw new CommandError($"BAD NUMBER {text}");
        } else if (separator >= 0) {
            for (int i = 0; i < second.Length; i++) denominator *= 10;
            numerator = numerator * denominator + long.Parse(second);
        }
        return new(negative ? -numerator : numerator, denominator);
    }

    private static bool Digits(string text) => text.Length > 0 && text.All(c => c is >= '0' and <= '9');
    public static Fraction operator +(Fraction a, Fraction b) =>
        new(a.Numerator * b.Denominator + b.Numerator * a.Denominator, a.Denominator * b.Denominator);
    public static Fraction operator -(Fraction a, Fraction b) =>
        new(a.Numerator * b.Denominator - b.Numerator * a.Denominator, a.Denominator * b.Denominator);
    public static Fraction operator *(Fraction a, Fraction b) =>
        new(a.Numerator * b.Numerator, a.Denominator * b.Denominator);
    public static Fraction operator /(Fraction a, Fraction b) =>
        new(a.Numerator * b.Denominator, a.Denominator * b.Numerator);
    public static Fraction operator -(Fraction a) => new(-a.Numerator, a.Denominator);
    public Fraction Abs() => new(Math.Abs(Numerator), Denominator);
    public int CompareTo(Fraction other) =>
        (Numerator * other.Denominator).CompareTo(other.Numerator * Denominator);
    public Fraction Power(int exponent)
    {
        Fraction factor = exponent < 0 ? One / this : this, result = One;
        for (int i = 0; i < Math.Abs(exponent); i++) result *= factor;
        return result;
    }
    public string Decimal()
    {
        long magnitude = Math.Abs(Numerator);
        return $"{(Numerator < 0 ? "-" : "")}{magnitude / Denominator}.{magnitude % Denominator * 1_000_000 / Denominator:D6}";
    }
    public override string ToString() => Denominator == 1 ? $"{Numerator}" : $"{Numerator}/{Denominator}";
}

readonly record struct Dimension(long Kg = 0, long M = 0, long S = 0, long A = 0,
                                 long K = 0, long Mol = 0, long Cd = 0)
{
    public bool IsZero => this == new Dimension();
    public bool IsEven => Exponents().All(value => value % 2 == 0);
    private long[] Exponents() => [Kg, M, S, A, K, Mol, Cd];
    public static Dimension operator +(Dimension a, Dimension b) =>
        new(a.Kg + b.Kg, a.M + b.M, a.S + b.S, a.A + b.A, a.K + b.K, a.Mol + b.Mol, a.Cd + b.Cd);
    public static Dimension operator -(Dimension a, Dimension b) =>
        new(a.Kg - b.Kg, a.M - b.M, a.S - b.S, a.A - b.A, a.K - b.K, a.Mol - b.Mol, a.Cd - b.Cd);
    public Dimension Scale(long k) => new(Kg * k, M * k, S * k, A * k, K * k, Mol * k, Cd * k);
    public Dimension Half() => new(Kg / 2, M / 2, S / 2, A / 2, K / 2, Mol / 2, Cd / 2);
    public override string ToString()
    {
        string[] symbols = ["kg", "m", "s", "A", "K", "mol", "cd"];
        long[] values = Exponents();
        List<string> parts = [];
        for (int i = 0; i < values.Length; i++)
            if (values[i] != 0) parts.Add(values[i] == 1 ? symbols[i] : $"{symbols[i]}^{values[i]}");
        return parts.Count == 0 ? "1" : string.Join(' ', parts);
    }
}

readonly record struct Quantity(Fraction Value, Dimension Dimension);
sealed record Definition(Fraction Value, string Expression);
sealed record Unit(string Symbol, Quantity Quantity, bool Prefix, Definition? Definition = null);

enum TokenKind { Number, Identifier, Unit, Symbol, Invalid, End }
readonly record struct Token(TokenKind Kind, string Text, int Position);

abstract class Parser
{
    private readonly string source;
    private readonly List<Token> tokens = [];
    private int index;
    protected Token Current => tokens[index];

    protected Parser(string source, bool quantity)
    {
        this.source = source;
        for (int i = 0; i < source.Length;) {
            int start = i++;
            char c = source[start];
            TokenKind kind;
            if (IsLetter(c)) {
                while (i < source.Length && IsLetter(source[i])) i++;
                kind = TokenKind.Identifier;
            } else if (IsDigit(c)) {
                while (i < source.Length && IsDigit(source[i])) i++;
                if (quantity && i + 1 < source.Length && source[i] == '.' && IsDigit(source[i + 1])) {
                    i += 2;
                    while (i < source.Length && IsDigit(source[i])) i++;
                }
                kind = TokenKind.Number;
            } else if (quantity && c == '[' && source.IndexOf(']', i) is int end && end > i) {
                i = end + 1;
                kind = TokenKind.Unit;
            } else kind = (quantity ? "+-*/^()," : "*/^()-").Contains(c) ? TokenKind.Symbol : TokenKind.Invalid;
            tokens.Add(new(kind, source[start..i], start + 1));
        }
        tokens.Add(new(TokenKind.End, "", source.Length + 1));
    }

    public static bool IsLetter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    private static bool IsDigit(char c) => c is >= '0' and <= '9';
    protected Token Advance() => tokens[index++];
    protected bool Take(string text)
    {
        if (Current.Text != text) return false;
        index++;
        return true;
    }
    protected void Expect(string text) { if (!Take(text)) throw Syntax(); }
    protected CommandError Syntax() => new($"SYNTAX {source} AT {(Current.Kind == TokenKind.End ? "END" : Current.Position.ToString())}");
    protected void Finish() { if (Current.Kind != TokenKind.End) throw Syntax(); }
    protected string Exponent()
    {
        string sign = Take("-") ? "-" : "";
        if (Current.Kind != TokenKind.Number || Current.Text.Contains('.')) throw Syntax();
        return sign + Advance().Text;
    }
}

abstract record UnitNode;
sealed record UnitName(string Name) : UnitNode;
sealed record UnitNumber(string Text) : UnitNode;
sealed record UnitPower(UnitNode Atom, string Exponent) : UnitNode;
sealed record UnitProduct(IReadOnlyList<(char Operator, UnitNode Term)> Terms) : UnitNode;

sealed class UnitParser(string source) : Parser(source, false)
{
    public UnitNode Parse() { UnitNode result = Expression(); Finish(); return result; }
    private UnitNode Expression()
    {
        List<(char, UnitNode)> terms = [('*', Term())];
        while (Current.Text is "*" or "/") {
            char op = Advance().Text[0];
            terms.Add((op, Term()));
        }
        return new UnitProduct(terms);
    }
    private UnitNode Term()
    {
        UnitNode atom;
        if (Current.Kind == TokenKind.Identifier) atom = new UnitName(Advance().Text);
        else if (Current.Kind == TokenKind.Number && Current.Text[0] != '0') atom = new UnitNumber(Advance().Text);
        else if (Take("(")) { atom = Expression(); Expect(")"); }
        else throw Syntax();
        return Take("^") ? new UnitPower(atom, Exponent()) : atom;
    }
}

abstract record QuantityNode;
sealed record Literal(string Number, string? Unit) : QuantityNode;
sealed record Variable(string Name) : QuantityNode;
sealed record Binary(char Operator, QuantityNode Left, QuantityNode Right) : QuantityNode;
sealed record Power(QuantityNode Base, string Exponent) : QuantityNode;
sealed record Negative(QuantityNode Operand) : QuantityNode;
sealed record Call(string Name, IReadOnlyList<QuantityNode> Arguments) : QuantityNode;

sealed class QuantityParser(string source) : Parser(source, true)
{
    public QuantityNode Parse() { QuantityNode result = Expression(); Finish(); return result; }
    private QuantityNode Expression()
    {
        QuantityNode node = Product();
        while (Current.Text is "+" or "-") {
            char op = Advance().Text[0];
            node = new Binary(op, node, Product());
        }
        return node;
    }
    private QuantityNode Product()
    {
        QuantityNode node = Unary();
        while (Current.Text is "*" or "/") {
            char op = Advance().Text[0];
            node = new Binary(op, node, Unary());
        }
        return node;
    }
    private QuantityNode Unary()
    {
        if (Take("-")) return new Negative(Unary());
        QuantityNode node = Primary();
        return Take("^") ? new Power(node, Exponent()) : node;
    }
    private QuantityNode Primary()
    {
        if (Current.Kind == TokenKind.Number) {
            string number = Advance().Text;
            return new Literal(number, Current.Kind == TokenKind.Unit ? Advance().Text[1..^1] : null);
        }
        if (Current.Kind == TokenKind.Unit) return new Literal("1", Advance().Text[1..^1]);
        if (Current.Kind == TokenKind.Identifier) {
            string name = Advance().Text;
            if (!Take("(")) return new Variable(name);
            List<QuantityNode> arguments = [Expression()];
            while (Take(",")) arguments.Add(Expression());
            Expect(")");
            return new Call(name, arguments);
        }
        if (Take("(")) { QuantityNode node = Expression(); Expect(")"); return node; }
        throw Syntax();
    }
}

sealed record ParsedUnit(UnitNode Tree, Quantity Quantity, IReadOnlyList<string> Names);
sealed record Reduced(Fraction Coefficient, Dictionary<string, long> Exponents);

sealed class Calculator
{
    private static readonly Dictionary<string, Dimension> Kinds = new(StringComparer.Ordinal) {
        ["dimensionless"] = new(), ["length"] = new(M: 1), ["mass"] = new(Kg: 1),
        ["time"] = new(S: 1), ["current"] = new(A: 1), ["temperature"] = new(K: 1),
        ["amount"] = new(Mol: 1), ["luminous_intensity"] = new(Cd: 1), ["area"] = new(M: 2),
        ["volume"] = new(M: 3), ["speed"] = new(M: 1, S: -1), ["acceleration"] = new(M: 1, S: -2),
        ["density"] = new(Kg: 1, M: -3), ["momentum"] = new(Kg: 1, M: 1, S: -1),
        ["force"] = new(Kg: 1, M: 1, S: -2), ["energy"] = new(Kg: 1, M: 2, S: -2),
        ["power"] = new(Kg: 1, M: 2, S: -3), ["pressure"] = new(Kg: 1, M: -1, S: -2),
        ["frequency"] = new(S: -1), ["charge"] = new(S: 1, A: 1),
        ["voltage"] = new(Kg: 1, M: 2, S: -3, A: -1), ["resistance"] = new(Kg: 1, M: 2, S: -3, A: -2),
        ["conductance"] = new(Kg: -1, M: -2, S: 3, A: 2), ["capacitance"] = new(Kg: -1, M: -2, S: 4, A: 2),
        ["magnetic_flux"] = new(Kg: 1, M: 2, S: -2, A: -1), ["flux_density"] = new(Kg: 1, S: -2, A: -1),
        ["inductance"] = new(Kg: 1, M: 2, S: -2, A: -2), ["illuminance"] = new(M: -2, Cd: 1),
        ["catalytic_activity"] = new(S: -1, Mol: 1)
    };
    private static readonly (string Symbol, Fraction Factor)[] Prefixes = [
        ("G", new(1_000_000_000)), ("M", new(1_000_000)), ("k", new(1000)), ("h", new(100)), ("da", new(10)),
        ("d", new(1, 10)), ("c", new(1, 100)), ("m", new(1, 1000)), ("u", new(1, 1_000_000)), ("n", new(1, 1_000_000_000))
    ];
    private readonly List<Unit> units = [];
    private readonly Dictionary<string, Quantity> variables = new(StringComparer.Ordinal);

    public Calculator()
    {
        void Add(string symbol, long numerator, long denominator, string kind, bool prefix) =>
            units.Add(new(symbol, new(new(numerator, denominator), Kinds[kind]), prefix));
        Add("m", 1, 1, "length", true); Add("g", 1, 1000, "mass", true);
        Add("s", 1, 1, "time", true); Add("A", 1, 1, "current", true); Add("K", 1, 1, "temperature", true);
        Add("mol", 1, 1, "amount", true); Add("cd", 1, 1, "luminous_intensity", true);
        Add("N", 1, 1, "force", true); Add("J", 1, 1, "energy", true); Add("W", 1, 1, "power", true);
        Add("Pa", 1, 1, "pressure", true); Add("Hz", 1, 1, "frequency", true); Add("C", 1, 1, "charge", true);
        Add("V", 1, 1, "voltage", true); Add("ohm", 1, 1, "resistance", true);
        Add("S", 1, 1, "conductance", true); Add("F", 1, 1, "capacitance", true);
        Add("Wb", 1, 1, "magnetic_flux", true); Add("T", 1, 1, "flux_density", true);
        Add("H", 1, 1, "inductance", true); Add("lx", 1, 1, "illuminance", true);
        Add("kat", 1, 1, "catalytic_activity", true); Add("L", 1, 1000, "volume", true);
        Add("t", 1000, 1, "mass", false); Add("min", 60, 1, "time", false);
        Add("h", 3600, 1, "time", false); Add("day", 86400, 1, "time", false);
        Add("in", 127, 5000, "length", false); Add("ft", 381, 1250, "length", false);
        Add("yd", 1143, 1250, "length", false); Add("mi", 201168, 125, "length", false);
        Add("nmi", 1852, 1, "length", false); Add("ha", 10000, 1, "area", false);
        Add("kn", 463, 900, "speed", false); Add("bar", 100000, 1, "pressure", true);
        Add("atm", 101325, 1, "pressure", false); Add("Torr", 20265, 152, "pressure", false);
        Add("cal", 523, 125, "energy", true); Add("Wh", 3600, 1, "energy", true);
        Add("Ah", 3600, 1, "charge", true); Add("dC", 1, 1, "temperature", false); Add("dF", 5, 9, "temperature", false);
    }

    private Quantity? Resolve(string name)
    {
        Unit? exact = units.Find(unit => unit.Symbol == name);
        if (exact is not null) return exact.Quantity;
        foreach (var prefix in Prefixes)
            foreach (Unit unit in units)
                if (unit.Definition is null && unit.Prefix && name == prefix.Symbol + unit.Symbol)
                    return new(prefix.Factor * unit.Quantity.Value, unit.Quantity.Dimension);
        return null;
    }
    private static string Kind(Dimension dimension) => Kinds.FirstOrDefault(pair => pair.Value == dimension).Key ?? "-";
    private string Simplified(Dimension dimension) =>
        units.Find(unit => unit.Quantity.Dimension == dimension && unit.Quantity.Value == Fraction.One)?.Symbol ?? dimension.ToString();
    private static string Format(Fraction value, string unit) => $"{value} {unit} ({value.Decimal()})";
    private string Format(Quantity quantity) => Format(quantity.Value, Simplified(quantity.Dimension));
    private static void Match(Dimension a, Dimension b)
    {
        if (a != b) throw new CommandError($"DIMENSION MISMATCH {a} vs {b}");
    }
    private static int CheckExponent(string text)
    {
        long value = long.Parse(text);
        if (value is < -3 or 0 or > 3) throw new CommandError($"BAD EXPONENT {text}");
        return (int)value;
    }
    private static void CheckName(string name, bool variable)
    {
        if (name.Length is < 1 or > 12 || !name.All(Parser.IsLetter) ||
            variable && name is ("abs" or "sqrt" or "min" or "max")) throw new CommandError($"BAD NAME {name}");
    }

    private ParsedUnit ParseUnit(string text)
    {
        UnitNode tree = new UnitParser(text).Parse();
        List<string> names = [];
        HashSet<string> seen = new(StringComparer.Ordinal);
        void Validate(UnitNode node)
        {
            switch (node) {
                case UnitName name:
                    if (Resolve(name.Name) is null) throw new CommandError($"UNKNOWN UNIT {name.Name}");
                    if (seen.Add(name.Name)) names.Add(name.Name);
                    break;
                case UnitPower power: Validate(power.Atom); CheckExponent(power.Exponent); break;
                case UnitProduct product: foreach (var term in product.Terms) Validate(term.Term); break;
            }
        }
        Validate(tree);
        return new(tree, UnitValue(tree), names);
    }
    private Quantity UnitValue(UnitNode node)
    {
        switch (node) {
            case UnitName name: return Resolve(name.Name)!.Value;
            case UnitNumber number: return new(new(long.Parse(number.Text)), new());
            case UnitPower power:
                Quantity atom = UnitValue(power.Atom);
                int exponent = (int)long.Parse(power.Exponent);
                return new(atom.Value.Power(exponent), atom.Dimension.Scale(exponent));
            case UnitProduct product:
                Quantity result = new(Fraction.One, new());
                foreach (var term in product.Terms) {
                    Quantity value = UnitValue(term.Term);
                    result = term.Operator == '*'
                        ? new(result.Value * value.Value, result.Dimension + value.Dimension)
                        : new(result.Value / value.Value, result.Dimension - value.Dimension);
                }
                return result;
            default: throw new InvalidOperationException();
        }
    }
    private static Reduced Reduce(UnitNode node)
    {
        switch (node) {
            case UnitName name: return new(Fraction.One, new(StringComparer.Ordinal) { [name.Name] = 1 });
            case UnitNumber number: return new(new(long.Parse(number.Text)), new(StringComparer.Ordinal));
            case UnitPower power:
                Reduced atom = Reduce(power.Atom);
                int exponent = (int)long.Parse(power.Exponent);
                return new(atom.Coefficient.Power(exponent), atom.Exponents.ToDictionary(pair => pair.Key, pair => pair.Value * exponent, StringComparer.Ordinal));
            case UnitProduct product:
                Fraction coefficient = Fraction.One;
                Dictionary<string, long> exponents = new(StringComparer.Ordinal);
                foreach (var term in product.Terms) {
                    Reduced value = Reduce(term.Term);
                    coefficient = term.Operator == '*' ? coefficient * value.Coefficient : coefficient / value.Coefficient;
                    foreach (var pair in value.Exponents)
                        exponents[pair.Key] = exponents.GetValueOrDefault(pair.Key) + (term.Operator == '*' ? pair.Value : -pair.Value);
                }
                return new(coefficient, exponents);
            default: throw new InvalidOperationException();
        }
    }
    private static string ReducedText(ParsedUnit parsed)
    {
        Reduced reduced = Reduce(parsed.Tree);
        List<string> parts = [];
        if (reduced.Coefficient != Fraction.One) parts.Add(reduced.Coefficient.ToString());
        foreach (string name in parsed.Names) {
            long exponent = reduced.Exponents[name];
            if (exponent != 0) parts.Add(exponent == 1 ? name : $"{name}^{exponent}");
        }
        return parts.Count == 0 ? "1" : string.Join(' ', parts);
    }
    private static long IntegerRoot(long number)
    {
        long low = 0, high = number + 1;
        while (high - low > 1) {
            long middle = low + (high - low) / 2;
            if (middle <= number / middle) low = middle;
            else high = middle;
        }
        return low;
    }
    private Quantity Evaluate(QuantityNode node)
    {
        switch (node) {
            case Literal literal:
                if (literal.Unit is null) return new(Fraction.Parse(literal.Number), new());
                Quantity unit = ParseUnit(literal.Unit).Quantity;
                return new(Fraction.Parse(literal.Number) * unit.Value, unit.Dimension);
            case Variable variable:
                if (!variables.TryGetValue(variable.Name, out Quantity stored)) throw new CommandError($"UNKNOWN VARIABLE {variable.Name}");
                return stored;
            case Negative negative:
                Quantity operand = Evaluate(negative.Operand);
                return new(-operand.Value, operand.Dimension);
            case Power power:
                Quantity basis = Evaluate(power.Base);
                int exponent = CheckExponent(power.Exponent);
                if (basis.Value.IsZero && exponent < 0) throw new CommandError("DIVISION BY ZERO");
                return new(basis.Value.Power(exponent), basis.Dimension.Scale(exponent));
            case Binary binary:
                Quantity left = Evaluate(binary.Left);
                Quantity right = Evaluate(binary.Right);
                if (binary.Operator is '+' or '-') {
                    Match(left.Dimension, right.Dimension);
                    return new(binary.Operator == '+' ? left.Value + right.Value : left.Value - right.Value, left.Dimension);
                }
                if (binary.Operator == '*') return new(left.Value * right.Value, left.Dimension + right.Dimension);
                if (right.Value.IsZero) throw new CommandError("DIVISION BY ZERO");
                return new(left.Value / right.Value, left.Dimension - right.Dimension);
            case Call call:
                if (call.Name is not ("abs" or "sqrt" or "min" or "max")) throw new CommandError($"UNKNOWN FUNCTION {call.Name}");
                int count = call.Name is "abs" or "sqrt" ? 1 : 2;
                if (call.Arguments.Count != count) throw new CommandError($"BAD ARGUMENTS {call.Name}");
                Quantity a = Evaluate(call.Arguments[0]);
                if (call.Name == "abs") return new(a.Value.Abs(), a.Dimension);
                if (call.Name == "sqrt") {
                    if (a.Value.Numerator < 0) throw new CommandError("NEGATIVE ROOT");
                    if (!a.Dimension.IsEven) throw new CommandError($"ODD DIMENSION {a.Dimension}");
                    long p = IntegerRoot(a.Value.Numerator), q = IntegerRoot(a.Value.Denominator);
                    if (p * p != a.Value.Numerator || q * q != a.Value.Denominator) throw new CommandError("NOT EXACT");
                    return new(new(p, q), a.Dimension.Half());
                }
                Quantity b = Evaluate(call.Arguments[1]);
                Match(a.Dimension, b.Dimension);
                int comparison = a.Value.CompareTo(b.Value);
                return call.Name == "min" ? (comparison <= 0 ? a : b) : (comparison >= 0 ? a : b);
            default: throw new InvalidOperationException();
        }
    }
    private List<Unit> Matching(Dimension dimension)
    {
        List<Unit> selected = units.FindAll(unit => unit.Quantity.Dimension == dimension);
        selected.Sort((a, b) => {
            int comparison = a.Quantity.Value.CompareTo(b.Quantity.Value);
            return comparison != 0 ? comparison : StringComparer.Ordinal.Compare(a.Symbol, b.Symbol);
        });
        return selected;
    }

    public string Execute(string line)
    {
        string[] words = line.Split(' ');
        string command = words[0];
        switch (command) {
            case "DEFINE": {
                CheckName(words[1], false);
                Fraction value = Fraction.Parse(words[3]);
                Quantity unit = ParseUnit(words[4]).Quantity;
                if (Kinds.ContainsKey(words[1]) || Resolve(words[1]) is not null) throw new CommandError($"NAME TAKEN {words[1]}");
                if (value.Numerator <= 0) throw new CommandError($"NOT POSITIVE {words[3]}");
                Quantity defined = new(value * unit.Value, unit.Dimension);
                units.Add(new(words[1], defined, false, new(value, words[4])));
                return $"DEFINE {words[1]} factor={defined.Value} dim={defined.Dimension} kind={Kind(defined.Dimension)}";
            }
            case "UNDEF": {
                int index = units.FindIndex(unit => unit.Symbol == words[1]);
                if (index >= 0 && units[index].Definition is null) throw new CommandError($"BUILTIN UNIT {words[1]}");
                if (index < 0) throw new CommandError($"NOT DEFINED {words[1]}");
                units.RemoveAt(index);
                return $"UNDEF {words[1]}";
            }
            case "DEFS": {
                List<Unit> users = units.FindAll(unit => unit.Definition is not null);
                List<string> lines = [$"DEFS count={users.Count}"];
                foreach (Unit unit in users)
                    lines.Add($"DEF {unit.Symbol} = {unit.Definition!.Value} {unit.Definition.Expression} factor={unit.Quantity.Value} dim={unit.Quantity.Dimension}");
                return string.Join('\n', lines);
            }
            case "CONVERT": case "INVERT": {
                Fraction value = Fraction.Parse(words[1]);
                Quantity a = ParseUnit(words[2]).Quantity;
                Quantity b = ParseUnit(words[4]).Quantity;
                if (command == "CONVERT") Match(a.Dimension, b.Dimension);
                else {
                    if (a.Dimension.IsZero || !(a.Dimension + b.Dimension).IsZero)
                        throw new CommandError($"NOT RECIPROCAL {a.Dimension} vs {b.Dimension}");
                    if (value.IsZero) throw new CommandError("DIVISION BY ZERO");
                }
                Fraction result = command == "CONVERT" ? value * a.Value / b.Value : (Fraction.One / (value * a.Value)) / b.Value;
                return $"{command} {value} {words[2]} = {Format(result, words[4])}";
            }
            case "DIM": case "REDUCE": case "SIMPLIFY": {
                ParsedUnit parsed = ParseUnit(words[1]);
                Quantity unit = parsed.Quantity;
                return command switch {
                    "DIM" => $"DIM {words[1]} = {unit.Dimension} factor={unit.Value} kind={Kind(unit.Dimension)}",
                    "REDUCE" => $"REDUCE {words[1]} = {ReducedText(parsed)}",
                    _ => $"SIMPLIFY {words[1]} = {Format(unit)}"
                };
            }
            case "ADD": case "SUB": case "MUL": case "DIV": case "COMPARE": {
                Fraction x = Fraction.Parse(words[1]);
                Quantity a = ParseUnit(words[2]).Quantity;
                Fraction y = Fraction.Parse(words[3]);
                Quantity b = ParseUnit(words[4]).Quantity;
                Quantity? target = words.Length == 7 ? ParseUnit(words[6]).Quantity : null;
                if (command == "COMPARE") {
                    Match(a.Dimension, b.Dimension);
                    Fraction left = x * a.Value, right = y * b.Value;
                    int comparison = left.CompareTo(right);
                    string relation = comparison < 0 ? "<" : comparison > 0 ? ">" : "=";
                    string ratio = right.IsZero ? "undefined" : (left / right).ToString();
                    return $"COMPARE {x} {words[2]} {relation} {y} {words[4]} ratio={ratio}";
                }
                char op = command switch { "ADD" => '+', "SUB" => '-', "MUL" => '*', _ => '/' };
                string prefix = $"{command} {x} {words[2]} {op} {y} {words[4]} = ";
                if (command is "ADD" or "SUB") {
                    Match(a.Dimension, b.Dimension);
                    if (target is Quantity destination) Match(a.Dimension, destination.Dimension);
                    Fraction left = x * a.Value, right = y * b.Value;
                    Fraction result = (command == "ADD" ? left + right : left - right) / (target?.Value ?? a.Value);
                    return prefix + Format(result, target is null ? words[2] : words[6]);
                }
                Dimension dimension = command == "MUL" ? a.Dimension + b.Dimension : a.Dimension - b.Dimension;
                if (command == "DIV" && y.IsZero) throw new CommandError("DIVISION BY ZERO");
                if (target is Quantity output) Match(dimension, output.Dimension);
                Fraction product = command == "MUL" ? x * y : x / y;
                Fraction first = x * a.Value, second = y * b.Value;
                Fraction coherent = command == "MUL" ? first * second : first / second;
                if (target is Quantity converted) return prefix + Format(coherent / converted.Value, words[6]);
                string rightUnit = command == "DIV" && (words[4].Contains('*') || words[4].Contains('/')) ? $"({words[4]})" : words[4];
                return prefix + $"{product} {words[2]}{op}{rightUnit} = {Format(coherent, Simplified(dimension))}";
            }
            case "TEMP": {
                Fraction value = Fraction.Parse(words[1]);
                foreach (string scale in new[] { words[2], words[4] })
                    if (scale is not ("C" or "F" or "K" or "R")) throw new CommandError($"UNKNOWN SCALE {scale}");
                Fraction kelvin = words[2] switch {
                    "C" => value + new Fraction(5463, 20),
                    "F" => (value + new Fraction(45967, 100)) * new Fraction(5) / new Fraction(9),
                    "R" => value * new Fraction(5) / new Fraction(9), _ => value
                };
                if (kelvin.Numerator < 0) throw new CommandError("BELOW ABSOLUTE ZERO");
                Fraction result = words[4] switch {
                    "C" => kelvin - new Fraction(5463, 20),
                    "F" => kelvin * new Fraction(9) / new Fraction(5) - new Fraction(45967, 100),
                    "R" => kelvin * new Fraction(9) / new Fraction(5), _ => kelvin
                };
                return $"TEMP {value} {words[2]} = {Format(result, words[4])}";
            }
            case "LIST": {
                Dimension dimension = Kinds.TryGetValue(words[1], out Dimension kind) ? kind : ParseUnit(words[1]).Quantity.Dimension;
                List<Unit> selected = Matching(dimension);
                List<string> lines = [$"LIST {words[1]} dim={dimension} kind={Kind(dimension)} count={selected.Count}"];
                foreach (Unit unit in selected)
                    lines.Add($"UNIT {unit.Symbol} factor={unit.Quantity.Value} origin={(unit.Definition is null ? "builtin" : "user")} prefix={(unit.Prefix ? "yes" : "no")}");
                return string.Join('\n', lines);
            }
            case "TABLE": case "AUTO": case "SPLIT": {
                Fraction value = Fraction.Parse(words[1]);
                Quantity unit = ParseUnit(words[2]).Quantity;
                if (command == "TABLE") {
                    List<Unit> selected = Matching(unit.Dimension);
                    List<string> lines = [$"TABLE {value} {words[2]} dim={unit.Dimension} count={selected.Count}"];
                    foreach (Unit row in selected) lines.Add("ROW " + Format(value * unit.Value / row.Quantity.Value, row.Symbol));
                    return string.Join('\n', lines);
                }
                if (command == "AUTO") {
                    Unit? basis = units.Find(candidate => candidate.Definition is null && candidate.Prefix && candidate.Quantity.Dimension == unit.Dimension);
                    if (basis is null) throw new CommandError($"NO PREFIXABLE UNIT {unit.Dimension}");
                    Fraction scaled = value * unit.Value / basis.Quantity.Value, magnitude = scaled.Abs();
                    int exponent = 0;
                    if (magnitude.CompareTo(Fraction.One) >= 0) {
                        while (exponent < 9 && magnitude.CompareTo(new Fraction(10).Power(exponent + 3)) >= 0) exponent += 3;
                    } else if (!magnitude.IsZero) {
                        while (exponent > -9 && magnitude.CompareTo(new Fraction(10).Power(exponent)) < 0) exponent -= 3;
                    }
                    string prefix = exponent switch { 9 => "G", 6 => "M", 3 => "k", -3 => "m", -6 => "u", -9 => "n", _ => "" };
                    return $"AUTO {value} {words[2]} = {Format(scaled / new Fraction(10).Power(exponent), prefix + basis.Symbol)}";
                }
                string[] parts = words[4].Split(',');
                List<Quantity> destinations = [];
                foreach (string part in parts) destinations.Add(ParseUnit(part).Quantity);
                if (value.Numerator < 0) throw new CommandError("NEGATIVE VALUE");
                foreach (Quantity destination in destinations) Match(unit.Dimension, destination.Dimension);
                for (int i = 1; i < destinations.Count; i++)
                    if (destinations[i - 1].Value.CompareTo(destinations[i].Value) <= 0) throw new CommandError("UNIT ORDER");
                Fraction remaining = value * unit.Value;
                List<string> pieces = [];
                for (int i = 0; i < parts.Length - 1; i++) {
                    Fraction quotient = remaining / destinations[i].Value;
                    long whole = quotient.Numerator / quotient.Denominator;
                    remaining -= new Fraction(whole) * destinations[i].Value;
                    pieces.Add($"{whole} {parts[i]}");
                }
                pieces.Add(Format(remaining / destinations[^1].Value, parts[^1]));
                return $"SPLIT {value} {words[2]} = {string.Join(' ', pieces)}";
            }
            case "LET": {
                CheckName(words[1], true);
                Quantity value = Evaluate(new QuantityParser(words[3]).Parse());
                variables[words[1]] = value;
                return $"LET {words[1]} = {Format(value)}";
            }
            case "EVAL": {
                Quantity value = Evaluate(new QuantityParser(words[1]).Parse());
                if (words.Length == 4) {
                    Quantity unit = ParseUnit(words[3]).Quantity;
                    Match(value.Dimension, unit.Dimension);
                    return $"EVAL {words[1]} = {Format(value.Value / unit.Value, words[3])}";
                }
                return $"EVAL {words[1]} = {Format(value)}";
            }
            case "VARS": {
                List<string> lines = [$"VARS count={variables.Count}"];
                foreach (string name in variables.Keys.Order(StringComparer.Ordinal)) lines.Add($"VAR {name} = {Format(variables[name])}");
                return string.Join('\n', lines);
            }
            default: throw new CommandError($"UNKNOWN COMMAND {command}");
        }
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Calculator calculator = new();
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) {
            string line = Console.ReadLine()!;
            try { Console.WriteLine(calculator.Execute(line)); }
            catch (CommandError error) { Console.WriteLine(error.Message); }
        }
    }
}
