using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

sealed class CommandError(string message) : Exception(message) {}

readonly record struct Fraction : IComparable<Fraction>
{
    public long Numerator { get; }
    public long Denominator { get; }
    public static Fraction Zero => new(0);
    public static Fraction One => new(1);
    public bool IsZero => Numerator == 0;
    public int Sign => Math.Sign(Numerator);

    public Fraction(long numerator, long denominator = 1)
    {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long divisor = Gcd(Math.Abs(numerator), denominator);
        Numerator = numerator / divisor;
        Denominator = denominator / divisor;
    }

    public static long Gcd(long a, long b)
    {
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }

    public static Fraction Parse(string text)
    {
        string[] parts = text.Split('/');
        long numerator = long.Parse(parts[0]);
        long denominator = parts.Length == 1 ? 1 : long.Parse(parts[1]);
        if (denominator == 0) throw new CommandError("ERROR ZERO DENOMINATOR");
        return new(numerator, denominator);
    }

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
        Fraction result = One;
        for (int i = 0; i < exponent; i++) result *= this;
        return result;
    }
    public override string ToString() => Denominator == 1 ? $"{Numerator}" : $"{Numerator}/{Denominator}";
}

sealed class Polynomial
{
    private readonly Fraction[] coefficients;
    public static Polynomial Zero { get; } = new();
    public static Polynomial One { get; } = new(Fraction.One);
    public static Polynomial X { get; } = new(Fraction.Zero, Fraction.One);
    public int Degree => coefficients.Length - 1;
    public bool IsZero => coefficients.Length == 0;
    public Fraction Leading => coefficients[^1];
    public Fraction this[int degree] => degree < coefficients.Length ? coefficients[degree] : Fraction.Zero;

    public Polynomial(params Fraction[] values)
    {
        int length = values.Length;
        while (length > 0 && values[length - 1].IsZero) length--;
        coefficients = values[..length];
    }

    private static Fraction[] Zeros(int count) => Enumerable.Repeat(Fraction.Zero, count).ToArray();
    public static Polynomial operator +(Polynomial a, Polynomial b)
    {
        Fraction[] result = Zeros(Math.Max(a.Degree, b.Degree) + 1);
        for (int i = 0; i < result.Length; i++) result[i] = a[i] + b[i];
        return new(result);
    }
    public static Polynomial operator -(Polynomial a, Polynomial b)
    {
        Fraction[] result = Zeros(Math.Max(a.Degree, b.Degree) + 1);
        for (int i = 0; i < result.Length; i++) result[i] = a[i] - b[i];
        return new(result);
    }
    public static Polynomial operator -(Polynomial value) => new(value.coefficients.Select(c => -c).ToArray());
    public static Polynomial operator *(Polynomial a, Polynomial b)
    {
        if (a.IsZero || b.IsZero) return Zero;
        Fraction[] result = Zeros(a.Degree + b.Degree + 1);
        for (int i = 0; i <= a.Degree; i++)
            for (int j = 0; j <= b.Degree; j++) result[i + j] += a[i] * b[j];
        return new(result);
    }
    public Polynomial Scale(Fraction factor) => new(coefficients.Select(c => c * factor).ToArray());
    public Polynomial Divide(Fraction divisor) => new(coefficients.Select(c => c / divisor).ToArray());
    public Polynomial Monic() => IsZero ? Zero : Divide(Leading);
    public Polynomial Power(int exponent)
    {
        if (exponent == 0) return One;
        if (IsZero) return Zero;
        if (Degree == 0 && Leading.Denominator == 1 && Math.Abs(Leading.Numerator) == 1)
            return Leading.Numerator == 1 || exponent % 2 == 0 ? One : this;
        Polynomial result = One;
        for (int i = 0; i < exponent; i++) result *= this;
        return result;
    }
    public Fraction Evaluate(Fraction point)
    {
        Fraction result = Fraction.Zero;
        for (int i = Degree; i >= 0; i--) result = result * point + this[i];
        return result;
    }
    public Polynomial Compose(Polynomial inner)
    {
        Polynomial result = Zero;
        for (int i = Degree; i >= 0; i--) result = result * inner + new Polynomial(this[i]);
        return result;
    }
    public Polynomial Derivative(int order = 1)
    {
        Polynomial result = this;
        for (int step = 0; step < order; step++) {
            Fraction[] next = Zeros(Math.Max(0, result.Degree));
            for (int i = 1; i <= result.Degree; i++) next[i - 1] = new Fraction(i) * result[i];
            result = new(next);
        }
        return result;
    }
    public Polynomial Integral()
    {
        if (IsZero) return Zero;
        Fraction[] result = Zeros(coefficients.Length + 1);
        for (int i = 0; i <= Degree; i++) result[i + 1] = this[i] / new Fraction(i + 1);
        return new(result);
    }
    public (Polynomial Quotient, Polynomial Remainder) Divide(Polynomial divisor)
    {
        Fraction[] quotient = Zeros(Math.Max(0, Degree - divisor.Degree + 1));
        Fraction[] remainder = (Fraction[])coefficients.Clone();
        int degree = Degree;
        while (degree >= divisor.Degree && degree >= 0) {
            Fraction factor = remainder[degree] / divisor.Leading;
            int shift = degree - divisor.Degree;
            quotient[shift] = factor;
            for (int j = 0; j <= divisor.Degree; j++) remainder[shift + j] -= factor * divisor[j];
            while (degree >= 0 && remainder[degree].IsZero) degree--;
        }
        return (new(quotient), new(remainder));
    }
    public static Polynomial Gcd(Polynomial a, Polynomial b)
    {
        while (!b.IsZero) (a, b) = (b, a.Divide(b).Remainder);
        return a.Monic();
    }
    public static (Polynomial G, Polynomial S, Polynomial T) ExtendedGcd(Polynomial a, Polynomial b)
    {
        Polynomial r0 = a, r1 = b, s0 = One, s1 = Zero, t0 = Zero, t1 = One;
        while (!r1.IsZero) {
            var (quotient, remainder) = r0.Divide(r1);
            (r0, r1) = (r1, remainder);
            (s0, s1) = (s1, s0 - quotient * s1);
            (t0, t1) = (t1, t0 - quotient * t1);
        }
        return r0.IsZero ? (r0, s0, t0) : (r0.Monic(), s0.Divide(r0.Leading), t0.Divide(r0.Leading));
    }
    public Fraction Content()
    {
        long denominator = 1, numerator = 0;
        foreach (Fraction coefficient in coefficients) {
            denominator = denominator * coefficient.Denominator / Fraction.Gcd(denominator, coefficient.Denominator);
            numerator = Fraction.Gcd(numerator, Math.Abs(coefficient.Numerator));
        }
        return new(Leading.Sign < 0 ? -numerator : numerator, denominator);
    }
    public Polynomial Primitive() => Divide(Content());
    public Polynomial SquareFreePart() => Degree < 1 ? this : Divide(Gcd(this, Derivative())).Quotient;
    public Polynomial WithoutConstant() => new(coefficients[1..]);

    public string Format(string variable = "x")
    {
        if (IsZero) return "0";
        StringBuilder result = new();
        for (int i = Degree; i >= 0; i--) {
            Fraction coefficient = this[i];
            if (coefficient.IsZero) continue;
            if (result.Length == 0) { if (coefficient.Sign < 0) result.Append('-'); }
            else result.Append(coefficient.Sign < 0 ? " - " : " + ");
            Fraction magnitude = coefficient.Abs();
            if (i == 0 || magnitude != Fraction.One) result.Append(magnitude);
            if (i > 0) result.Append(variable);
            if (i > 1) result.Append('^').Append(i);
        }
        return result.ToString();
    }
}

static class Checks
{
    public static void Product(Polynomial a, Polynomial b)
    {
        if (!a.IsZero && !b.IsZero && a.Degree + b.Degree > 30) throw new CommandError("ERROR DEGREE LIMIT");
    }
    public static void Power(Polynomial a, int exponent)
    {
        if (!a.IsZero && a.Degree * exponent > 30) throw new CommandError("ERROR DEGREE LIMIT");
    }
    public static void Composition(Polynomial a, Polynomial b)
    {
        if (a.Degree >= 1 && b.Degree >= 1 && a.Degree * b.Degree > 30) throw new CommandError("ERROR DEGREE LIMIT");
    }
    public static void Nonzero(Polynomial value)
    {
        if (value.IsZero) throw new CommandError("ERROR ZERO POLYNOMIAL");
    }
    public static void Divisor(Polynomial value)
    {
        if (value.IsZero) throw new CommandError("ERROR DIVISION BY ZERO");
    }
    public static void PositiveDegree(Polynomial value)
    {
        if (value.Degree == 0) throw new CommandError("ERROR DEGREE TOO LOW");
    }
}

abstract record Expression
{
    public abstract Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage);
}
sealed record LiteralExpression(Polynomial Value) : Expression
{
    public override Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage) => Value;
}
sealed record NameExpression(string Name, int Order) : Expression
{
    public override Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage) =>
        storage.TryGetValue(Name, out Polynomial? value) ? value.Derivative(Order) : throw new CommandError($"ERROR UNKNOWN {Name}");
}
sealed record NegativeExpression(Expression Operand) : Expression
{
    public override Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage) => -Operand.Evaluate(storage);
}
sealed record BinaryExpression(char Operation, Expression Left, Expression Right) : Expression
{
    public override Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage)
    {
        Polynomial a = Left.Evaluate(storage), b = Right.Evaluate(storage);
        switch (Operation) {
            case '+': return a + b;
            case '-': return a - b;
            case '*': Checks.Product(a, b); return a * b;
            default:
                Checks.Divisor(b);
                if (b.Degree >= 1) throw new CommandError("ERROR NONCONSTANT DIVISOR");
                return a.Divide(b[0]);
        }
    }
}
sealed record PowerExpression(Expression Operand, int Exponent) : Expression
{
    public override Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage)
    {
        Polynomial value = Operand.Evaluate(storage);
        Checks.Power(value, Exponent);
        return value.Power(Exponent);
    }
}
sealed record CallExpression(Expression Function, Expression Argument) : Expression
{
    public override Polynomial Evaluate(IReadOnlyDictionary<string, Polynomial> storage)
    {
        Polynomial function = Function.Evaluate(storage), argument = Argument.Evaluate(storage);
        Checks.Composition(function, argument);
        return function.Compose(argument);
    }
}

enum TokenKind { Number, Name, Symbol, End }
readonly record struct Token(TokenKind Kind, string Text, int Position);

sealed class Parser
{
    private readonly List<Token> tokens = [];
    private int position;
    private Token Current => tokens[position];
    private bool At(char symbol) => Current.Kind == TokenKind.Symbol && Current.Text[0] == symbol;

    public Parser(string source)
    {
        for (int i = 0; i < source.Length;) {
            if (source[i] == ' ') { i++; continue; }
            int start = i++;
            TokenKind kind;
            if (char.IsAsciiDigit(source[start])) {
                kind = TokenKind.Number;
                while (i < source.Length && char.IsAsciiDigit(source[i])) i++;
            } else if (source[start] is >= 'A' and <= 'Z') {
                kind = TokenKind.Name;
                while (i < source.Length && (source[i] is >= 'A' and <= 'Z' || char.IsAsciiDigit(source[i]))) i++;
            } else kind = TokenKind.Symbol;
            tokens.Add(new(kind, source[start..i], start + 1));
        }
        tokens.Add(new(TokenKind.End, "", source.Length + 1));
    }
    private void Syntax() => throw new CommandError(Current.Kind == TokenKind.End ? "ERROR SYNTAX AT END" : $"ERROR SYNTAX AT {Current.Position}");
    private void Expect(char symbol)
    {
        if (!At(symbol)) Syntax();
        position++;
    }
    public Expression Parse()
    {
        Expression result = ParseExpression();
        if (Current.Kind != TokenKind.End) Syntax();
        return result;
    }
    private Expression ParseExpression()
    {
        bool negative = At('-');
        if (negative) position++;
        Expression result = ParseTerm();
        if (negative) result = new NegativeExpression(result);
        while (At('+') || At('-')) {
            char operation = Current.Text[0];
            position++;
            result = new BinaryExpression(operation, result, ParseTerm());
        }
        return result;
    }
    private Expression ParseTerm()
    {
        Expression result = ParseFactor();
        while (true) {
            char operation;
            if (At('*') || At('/')) { operation = Current.Text[0]; position++; }
            else if (At('x') || At('(') || Current.Kind == TokenKind.Name) operation = '*';
            else break;
            result = new BinaryExpression(operation, result, ParseFactor());
        }
        return result;
    }
    private Expression ParseFactor()
    {
        Expression result = ParsePrimary();
        if (At('^')) {
            position++;
            if (Current.Kind != TokenKind.Number) Syntax();
            int exponent = int.Parse(Current.Text);
            position++;
            result = new PowerExpression(result, exponent);
        }
        return result;
    }
    private Expression ParsePrimary()
    {
        if (Current.Kind == TokenKind.Number) {
            Polynomial value = new(new Fraction(long.Parse(Current.Text)));
            position++;
            return new LiteralExpression(value);
        }
        if (At('x')) { position++; return new LiteralExpression(Polynomial.X); }
        if (Current.Kind == TokenKind.Name) {
            string name = Current.Text;
            position++;
            int order = 0;
            while (At('\'')) { order++; position++; }
            Expression reference = new NameExpression(name, order);
            if (!At('(')) return reference;
            position++;
            Expression argument = ParseExpression();
            Expect(')');
            return new CallExpression(reference, argument);
        }
        if (At('(')) {
            position++;
            Expression result = ParseExpression();
            Expect(')');
            return result;
        }
        Syntax();
        throw new InvalidOperationException();
    }
}

readonly record struct Endpoint(int Infinity, Fraction Value) : IComparable<Endpoint>
{
    public static Endpoint Parse(string text) => text switch {
        "-inf" => new(-1, Fraction.Zero), "inf" => new(1, Fraction.Zero), _ => new(0, Fraction.Parse(text)),
    };
    public int CompareTo(Endpoint other) => Infinity == 0 && other.Infinity == 0 ? Value.CompareTo(other.Value) : Infinity.CompareTo(other.Infinity);
    public override string ToString() => Infinity == 0 ? Value.ToString() : Infinity < 0 ? "-inf" : "inf";
}

static class Algebra
{
    public static (Fraction Content, Polynomial Remaining, List<(Fraction Root, int Count)> Roots) RationalRoots(Polynomial value)
    {
        Fraction content = value.Content();
        Polynomial remaining = value.Divide(content);
        int zeros = 0;
        while (remaining[0].IsZero) { remaining = remaining.WithoutConstant(); zeros++; }
        static List<long> Divisors(long number)
        {
            List<long> result = [];
            for (long i = 1; i <= number; i++) if (number % i == 0) result.Add(i);
            return result;
        }
        List<long> numerators = Divisors(Math.Abs(remaining[0].Numerator));
        List<long> denominators = Divisors(remaining.Leading.Numerator);
        List<Fraction> candidates = [];
        foreach (long numerator in numerators)
            foreach (long denominator in denominators)
                if (Fraction.Gcd(numerator, denominator) == 1) {
                    candidates.Add(new(numerator, denominator));
                    candidates.Add(new(-numerator, denominator));
                }
        candidates.Sort();
        List<(Fraction Root, int Count)> roots = [];
        foreach (Fraction candidate in candidates) {
            int count = 0;
            Polynomial divisor = new(new Fraction(-candidate.Numerator), new Fraction(candidate.Denominator));
            while (remaining.Degree >= 1 && remaining.Evaluate(candidate).IsZero) {
                remaining = remaining.Divide(divisor).Quotient;
                count++;
            }
            if (count > 0) roots.Add((candidate, count));
        }
        if (zeros > 0) roots.Add((Fraction.Zero, zeros));
        roots.Sort((left, right) => left.Root.CompareTo(right.Root));
        return (content, remaining, roots);
    }

    public static List<(Polynomial Factor, int Count)> SquareFreeFactors(Polynomial value)
    {
        List<(Polynomial Factor, int Count)> result = [];
        if (value.Degree < 1) return result;
        Polynomial monic = value.Monic();
        Polynomial c = Polynomial.Gcd(monic, monic.Derivative());
        Polynomial w = monic.Divide(c).Quotient;
        for (int i = 1; w.Degree >= 1; i++) {
            Polynomial y = Polynomial.Gcd(w, c);
            Polynomial factor = w.Divide(y).Quotient;
            if (factor.Degree >= 1) result.Add((factor.Primitive(), i));
            c = c.Divide(y).Quotient;
            w = y;
        }
        return result;
    }

    public static List<Polynomial> SturmSequence(Polynomial value)
    {
        Polynomial previous = value.SquareFreePart(), current = previous.Derivative();
        List<Polynomial> result = [previous];
        while (!current.IsZero) {
            result.Add(current);
            Polynomial next = -previous.Divide(current).Remainder;
            previous = current;
            current = next;
        }
        return result;
    }
    public static int Variations(List<Polynomial> sequence, Endpoint point)
    {
        int previous = 0, changes = 0;
        foreach (Polynomial value in sequence) {
            int sign = point.Infinity == 0 ? value.Evaluate(point.Value).Sign : value.Leading.Sign;
            if (point.Infinity < 0 && value.Degree % 2 != 0) sign = -sign;
            if (sign == 0) continue;
            if (previous != 0 && sign != previous) changes++;
            previous = sign;
        }
        return changes;
    }
    public static int RootCount(List<Polynomial> sequence, Endpoint left, Endpoint right) => Variations(sequence, left) - Variations(sequence, right);
    public static List<(Fraction Left, Fraction Right)> Isolate(Polynomial value, int precision)
    {
        List<Polynomial> sequence = SturmSequence(value);
        Polynomial first = sequence[0];
        Fraction maximum = Fraction.Zero;
        for (int i = 0; i < first.Degree; i++) {
            Fraction candidate = (first[i] / first.Leading).Abs();
            if (candidate.CompareTo(maximum) > 0) maximum = candidate;
        }
        Fraction beta = Fraction.One + maximum, width = new(1, 1L << precision);
        List<(Fraction Left, Fraction Right)> result = [];
        int Count(Fraction left, Fraction right) => RootCount(sequence, new(0, left), new(0, right));
        void Examine(Fraction left, Fraction right)
        {
            int count = Count(left, right);
            if (count >= 2) {
                Fraction middle = (left + right) / new Fraction(2);
                Examine(left, middle);
                Examine(middle, right);
            } else if (count == 1) {
                while ((right - left).CompareTo(width) > 0) {
                    Fraction middle = (left + right) / new Fraction(2);
                    if (Count(left, middle) >= 1) right = middle;
                    else left = middle;
                }
                result.Add((left, right));
            }
        }
        Examine(-beta, beta);
        return result;
    }
    public static Fraction Resultant(Polynomial p, Polynomial q)
    {
        Fraction result = Fraction.One;
        while (q.Degree >= 1) {
            Polynomial remainder = p.Divide(q).Remainder;
            if (remainder.IsZero) return Fraction.Zero;
            result *= q.Leading.Power(p.Degree - remainder.Degree);
            if (p.Degree * q.Degree % 2 != 0) result = -result;
            (p, q) = (q, remainder);
        }
        return result * q[0].Power(p.Degree);
    }
    public static int Descartes(Polynomial value, bool negative)
    {
        int previous = 0, count = 0;
        for (int i = value.Degree; i >= 0; i--) {
            int sign = value[i].Sign;
            if (negative && i % 2 != 0) sign = -sign;
            if (sign == 0) continue;
            if (previous != 0 && previous != sign) count++;
            previous = sign;
        }
        return count;
    }
    public static Polynomial Interpolate(Fraction[] values)
    {
        int count = values.Length / 2;
        Fraction[] x = new Fraction[count], differences = new Fraction[count];
        for (int i = 0; i < count; i++) { x[i] = values[2 * i]; differences[i] = values[2 * i + 1]; }
        for (int j = 1; j < count; j++)
            for (int i = 0; i < j; i++)
                if (x[j].CompareTo(x[i]) == 0) throw new CommandError($"ERROR DUPLICATE X {x[j]}");
        for (int j = 1; j < count; j++)
            for (int i = count - 1; i >= j; i--) differences[i] = (differences[i] - differences[i - 1]) / (x[i] - x[i - j]);
        Polynomial result = Polynomial.Zero;
        for (int i = count - 1; i >= 0; i--) result = result * new Polynomial(-x[i], Fraction.One) + new Polynomial(differences[i]);
        return result;
    }
    public static Polynomial Special(string kind, int degree)
    {
        if (kind is not ("chebyshev" or "chebyshev2" or "legendre" or "hermite" or "laguerre"))
            throw new CommandError($"ERROR UNKNOWN KIND {kind}");
        if (degree > 30) throw new CommandError("ERROR DEGREE LIMIT");
        Polynomial previous = Polynomial.One;
        Polynomial current = kind switch {
            "chebyshev2" or "hermite" => new(Fraction.Zero, new Fraction(2)),
            "laguerre" => new(Fraction.One, new Fraction(-1)), _ => Polynomial.X,
        };
        if (degree == 0) return previous;
        for (int j = 1; j < degree; j++) {
            Polynomial factor = kind switch {
                "legendre" => new(Fraction.Zero, new Fraction(2 * j + 1)),
                "laguerre" => new(new Fraction(2 * j + 1), new Fraction(-1)),
                _ => new(Fraction.Zero, new Fraction(2)),
            };
            int scale = kind is "legendre" or "laguerre" ? j : kind == "hermite" ? 2 * j : 1;
            Polynomial next = factor * current - previous.Scale(new Fraction(scale));
            if (kind is "legendre" or "laguerre") next = next.Scale(new Fraction(1, j + 1));
            previous = current;
            current = next;
        }
        return current;
    }
}

sealed class Calculator
{
    private readonly Dictionary<string, Polynomial> storage = new(StringComparer.Ordinal);
    private Polynomial Lookup(string name) => storage.TryGetValue(name, out Polynomial? value)
        ? value : throw new CommandError($"ERROR UNKNOWN {name}");

    private static int[] NameArguments(string command) => command switch {
        "PRINT" or "DELETE" or "DEGREE" or "AREA" or "TAYLOR" or "EVAL" or "ROOTS" or "FACTOR" or
        "SQFREE" or "DESCARTES" or "STURM" or "ISOLATE" or "DISCRIM" or "POWERSUM" => [1],
        "ADD" or "SUB" or "MUL" or "GCD" or "LCM" or "INVMOD" or "COMPOSE" => [2, 3],
        "POW" or "DERIV" or "INTEG" or "TANGENT" => [2],
        "DIV" => [3, 4], "XGCD" => [4, 5], "CRT" => [2, 3, 4, 5],
        "MODPOW" => [2, 4], "RESULTANT" => [1, 2], _ => [],
    };

    public List<string> Execute(string line)
    {
        List<string> output = [];
        List<(string Name, Polynomial Value)> pending = [];
        string? deletion = null;
        void Save(string name, Polynomial value)
        {
            pending.Add((name, value));
            output.Add($"{name} = {value.Format()}");
        }

        if (line.StartsWith("DEF ", StringComparison.Ordinal)) {
            string[] definition = line.Split(' ', 3);
            Expression expression = new Parser(definition[2]).Parse();
            Save(definition[1], expression.Evaluate(storage));
        } else {
            string[] words = line.Split(' ');
            string command = words[0];
            if (command == "DIV" && words[1] == words[2] || command == "XGCD" &&
                (words[1] == words[2] || words[1] == words[3] || words[2] == words[3])) {
                throw new CommandError("ERROR SAME NAME");
            }
            Polynomial[] operands = NameArguments(command).Select(index => Lookup(words[index])).ToArray();
            int[] literalArguments = command switch {
                "AREA" => [2, 3], "TANGENT" => [3], "TAYLOR" => [2],
                "EVAL" or "INTERP" => Enumerable.Range(2, words.Length - 2).ToArray(), _ => [],
            };
            Fraction[] literals = literalArguments.Select(index => Fraction.Parse(words[index])).ToArray();
            Endpoint left = default, right = default;
            if (command == "STURM") { left = Endpoint.Parse(words[2]); right = Endpoint.Parse(words[3]); }
            Polynomial a = operands.Length > 0 ? operands[0] : Polynomial.Zero;
            Polynomial b = operands.Length > 1 ? operands[1] : Polynomial.Zero;
            switch (command) {
                case "PRINT": output.Add($"{words[1]} = {a.Format()}"); break;
                case "DELETE": deletion = words[1]; output.Add($"deleted {words[1]}"); break;
                case "LIST":
                    if (storage.Count == 0) output.Add("no polynomials");
                    else foreach (string name in storage.Keys.OrderBy(name => name, StringComparer.Ordinal))
                        output.Add($"{name} = {storage[name].Format()}");
                    break;
                case "DEGREE": output.Add($"deg({words[1]}) = {(a.IsZero ? "-inf" : a.Degree.ToString())}"); break;
                case "ADD": Save(words[1], a + b); break;
                case "SUB": Save(words[1], a - b); break;
                case "MUL": Checks.Product(a, b); Save(words[1], a * b); break;
                case "POW": {
                    int exponent = int.Parse(words[3]);
                    Checks.Power(a, exponent);
                    Save(words[1], a.Power(exponent));
                    break;
                }
                case "DIV": {
                    Checks.Divisor(b);
                    var (quotient, remainder) = a.Divide(b);
                    Save(words[1], quotient);
                    Save(words[2], remainder);
                    break;
                }
                case "GCD": Save(words[1], Polynomial.Gcd(a, b)); break;
                case "XGCD": {
                    var (g, s, t) = Polynomial.ExtendedGcd(a, b);
                    Save(words[1], g); Save(words[2], s); Save(words[3], t);
                    break;
                }
                case "LCM": {
                    if (a.IsZero || b.IsZero) { Save(words[1], Polynomial.Zero); break; }
                    Polynomial gcd = Polynomial.Gcd(a, b);
                    if (a.Degree + b.Degree - gcd.Degree > 30) throw new CommandError("ERROR DEGREE LIMIT");
                    Save(words[1], (a.Divide(gcd).Quotient * b).Monic());
                    break;
                }
                case "INVMOD": {
                    Checks.Divisor(b); Checks.PositiveDegree(b);
                    var (g, s, _) = Polynomial.ExtendedGcd(a, b);
                    if (g.Degree != 0 || g[0] != Fraction.One) throw new CommandError("ERROR NOT COPRIME");
                    Save(words[1], s.Divide(b).Remainder);
                    break;
                }
                case "CRT": {
                    Polynomial a2 = operands[2], m2 = operands[3];
                    Checks.Divisor(b); Checks.Divisor(m2);
                    if (b.Degree + m2.Degree > 30) throw new CommandError("ERROR DEGREE LIMIT");
                    var (g, s, _) = Polynomial.ExtendedGcd(b, m2);
                    if (g.Degree != 0 || g[0] != Fraction.One) throw new CommandError("ERROR NOT COPRIME");
                    Polynomial r1 = a.Divide(b).Remainder, r2 = a2.Divide(m2).Remainder;
                    Polynomial u = ((r2 - r1) * s).Divide(m2).Remainder;
                    Save(words[1], r1 + b * u);
                    break;
                }
                case "MODPOW": {
                    Checks.Divisor(b);
                    if (2 * b.Degree - 2 > 30) throw new CommandError("ERROR DEGREE LIMIT");
                    Polynomial x = Polynomial.One.Divide(b).Remainder, y = a.Divide(b).Remainder;
                    int exponent = int.Parse(words[3]);
                    while (exponent > 0) {
                        if (exponent % 2 != 0) x = (x * y).Divide(b).Remainder;
                        exponent /= 2;
                        if (exponent != 0) y = (y * y).Divide(b).Remainder;
                    }
                    Save(words[1], x);
                    break;
                }
                case "DERIV": Save(words[1], a.Derivative(int.Parse(words[3]))); break;
                case "INTEG":
                    if (a.Degree == 30) throw new CommandError("ERROR DEGREE LIMIT");
                    Save(words[1], a.Integral());
                    break;
                case "AREA": {
                    Polynomial integral = a.Integral();
                    Fraction value = integral.Evaluate(literals[1]) - integral.Evaluate(literals[0]);
                    output.Add($"integral({words[1]}, {literals[0]}, {literals[1]}) = {value}");
                    break;
                }
                case "TANGENT": {
                    Fraction point = literals[0], value = a.Evaluate(point), slope = a.Derivative().Evaluate(point);
                    Save(words[1], new Polynomial(value - slope * point, slope));
                    break;
                }
                case "TAYLOR": {
                    Fraction point = literals[0];
                    Polynomial shifted = a.Compose(new Polynomial(point, Fraction.One));
                    string variable = point.IsZero ? "x" : point.Sign > 0 ? $"(x - {point})" : $"(x + {-point})";
                    output.Add($"taylor({words[1]}, {point}) = {shifted.Format(variable)}");
                    break;
                }
                case "COMPOSE": Checks.Composition(a, b); Save(words[1], a.Compose(b)); break;
                case "EVAL":
                    foreach (Fraction point in literals) output.Add($"{words[1]}({point}) = {a.Evaluate(point)}");
                    break;
                case "ROOTS": {
                    Checks.Nonzero(a);
                    var (_, _, roots) = Algebra.RationalRoots(a);
                    string result = roots.Count == 0 ? "none" : string.Join(", ", roots.Select(root => $"{root.Root} ({root.Count})"));
                    output.Add($"roots({words[1]}) = {result}");
                    break;
                }
                case "FACTOR": {
                    Checks.Nonzero(a);
                    var (content, remaining, roots) = Algebra.RationalRoots(a);
                    StringBuilder result = new($"factor({words[1]}) = {content}");
                    foreach (var (root, count) in roots) {
                        string factor = root.IsZero ? "x" : $"({new Polynomial(new Fraction(-root.Numerator), new Fraction(root.Denominator)).Format()})";
                        result.Append(" * ").Append(factor);
                        if (count >= 2) result.Append('^').Append(count);
                    }
                    if (remaining.Degree >= 1) result.Append(" * (").Append(remaining.Format()).Append(')');
                    output.Add(result.ToString());
                    break;
                }
                case "SQFREE": {
                    Checks.Nonzero(a);
                    List<(Polynomial Factor, int Count)> factors = Algebra.SquareFreeFactors(a);
                    StringBuilder result = new($"sqfree({words[1]}) = {a.Content()}");
                    foreach (var (factor, count) in factors) {
                        bool isX = factor.Degree == 1 && factor[0].IsZero && factor[1] == Fraction.One;
                        result.Append(" * ").Append(isX ? "x" : $"({factor.Format()})");
                        if (count >= 2) result.Append('^').Append(count);
                    }
                    output.Add(result.ToString());
                    break;
                }
                case "DESCARTES":
                    Checks.Nonzero(a);
                    output.Add($"descartes({words[1]}) = positive {Algebra.Descartes(a, false)}, negative {Algebra.Descartes(a, true)}");
                    break;
                case "STURM": {
                    Checks.Nonzero(a);
                    if (left.CompareTo(right) >= 0) throw new CommandError("ERROR BAD INTERVAL");
                    List<Polynomial> sequence = Algebra.SturmSequence(a);
                    output.Add($"sturm({words[1]}, {left}, {right}) = {Algebra.RootCount(sequence, left, right)}");
                    break;
                }
                case "ISOLATE": {
                    Checks.Nonzero(a);
                    int precision = int.Parse(words[2]);
                    List<(Fraction Left, Fraction Right)> intervals = Algebra.Isolate(a, precision);
                    string result = intervals.Count == 0 ? "none" : string.Join(", ", intervals.Select(interval => $"({interval.Left}, {interval.Right}]"));
                    output.Add($"isolate({words[1]}, {precision}) = {result}");
                    break;
                }
                case "RESULTANT":
                    Checks.Nonzero(a); Checks.Nonzero(b);
                    output.Add($"res({words[1]}, {words[2]}) = {Algebra.Resultant(a, b)}");
                    break;
                case "DISCRIM": {
                    Checks.Nonzero(a); Checks.PositiveDegree(a);
                    Fraction value = Algebra.Resultant(a, a.Derivative()) / a.Leading;
                    if (a.Degree * (a.Degree - 1) / 2 % 2 != 0) value = -value;
                    output.Add($"disc({words[1]}) = {value}");
                    break;
                }
                case "POWERSUM": {
                    Checks.Nonzero(a); Checks.PositiveDegree(a);
                    int count = int.Parse(words[2]);
                    Polynomial monic = a.Monic();
                    Fraction[] sums = Enumerable.Repeat(Fraction.Zero, count + 1).ToArray();
                    for (int j = 1; j <= count; j++) {
                        Fraction value = j <= a.Degree ? new Fraction(j) * monic[a.Degree - j] : Fraction.Zero;
                        for (int i = 1; i <= Math.Min(j - 1, a.Degree); i++) value += monic[a.Degree - i] * sums[j - i];
                        sums[j] = -value;
                    }
                    output.Add($"powersum({words[1]}) = {string.Join(", ", sums.Skip(1))}");
                    break;
                }
                case "INTERP": Save(words[1], Algebra.Interpolate(literals)); break;
                case "SPECIAL": Save(words[1], Algebra.Special(words[2], int.Parse(words[3]))); break;
                default: throw new InvalidOperationException();
            }
        }
        if (deletion is not null) storage.Remove(deletion);
        foreach (var (name, value) in pending) storage[name] = value;
        return output;
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        Calculator calculator = new();
        for (int i = 0; i < count; i++) {
            try {
                foreach (string output in calculator.Execute(Console.ReadLine()!)) Console.WriteLine(output);
            } catch (CommandError error) {
                Console.WriteLine(error.Message);
            }
        }
    }
}
