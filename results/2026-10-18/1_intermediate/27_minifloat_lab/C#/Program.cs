using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using static IntegerMath;

enum Mode { Rne, Rna, Rtz, Rup, Rdn }
enum Operation { Add, Sub, Mul, Div, Sqrt, Fma }
enum RealKind { Finite, Infinity, NaN }
[Flags]
enum FpFlags { None = 0, Invalid = 1, DivByZero = 2, Overflow = 4, Underflow = 8, Inexact = 16 }

sealed class CommandError(string message) : Exception(message);
readonly record struct Result(int Pattern, FpFlags Flags = FpFlags.None);
readonly record struct Units(long Integer, bool Inexact);
readonly record struct Fields(bool Negative, int Exponent, int Fraction, int Q);

static class IntegerMath
{
    public static int BitLength(long value)
    {
        int length = 0;
        for (; value != 0; value >>= 1) length++;
        return length;
    }

    public static (long Numerator, long Denominator) Scaled(long numerator, long denominator, int exponent) =>
        exponent >= 0 ? (numerator << exponent, denominator) : (numerator, denominator << -exponent);

    public static long Gcd(long a, long b)
    {
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }

    public static long IntegerSqrt(long value)
    {
        if (value == 0) return 0;
        long root = 1L << ((BitLength(value) + 1) / 2);
        while (true)
        {
            long next = (root + value / root) / 2;
            if (next >= root) return root;
            root = next;
        }
    }

    public static bool Increment(Mode mode, bool negative, long integer, bool inexact, long halfway)
    {
        if (!inexact) return false;
        return mode switch
        {
            Mode.Rne => halfway > 0 || halfway == 0 && integer % 2 != 0,
            Mode.Rna => halfway >= 0,
            Mode.Rtz => false,
            Mode.Rup => !negative,
            Mode.Rdn => negative,
            _ => throw new ArgumentOutOfRangeException(nameof(mode))
        };
    }

    public static Units RoundUnits(Exact value, int exponent, Mode mode)
    {
        var (n, d) = Scaled(value.Numerator, value.Denominator, value.Exponent - exponent);
        long integer = n / d, remainder = n % d;
        if (Increment(mode, value.Negative, integer, remainder != 0, 2 * remainder - d)) integer++;
        return new(integer, remainder != 0);
    }

    public static Units RoundSqrtUnits(Exact value, int exponent, Mode mode)
    {
        var (n, d) = Scaled(value.Numerator, value.Denominator, value.Exponent - 2 * exponent);
        long integer = IntegerSqrt(n / d);
        bool inexact = integer * integer * d != n;
        long midpoint = 2 * integer + 1;
        if (Increment(mode, false, integer, inexact, 4 * n - d * midpoint * midpoint)) integer++;
        return new(integer, inexact);
    }
}

// A magnitude is Numerator * 2^Exponent / Denominator; its sign also preserves -0.
readonly record struct Exact(long Numerator, int Exponent = 0, long Denominator = 1, bool Negative = false)
{
    public Exact Negated() => this with { Negative = !Negative };

    public int Log2Floor()
    {
        int exponent = BitLength(Numerator) - BitLength(Denominator) + Exponent;
        var (n, d) = Scaled(Numerator, Denominator, Exponent - exponent);
        return n < d ? exponent - 1 : exponent;
    }

    public string Fraction()
    {
        if (Numerator == 0) return "0";
        var (n, d) = Scaled(Numerator, Denominator, Exponent);
        long factor = Gcd(n, d);
        n /= factor;
        d /= factor;
        return (Negative ? "-" : "") + n + (d == 1 ? "" : "/" + d);
    }

    public string Decimal(bool keepZeroSign = false)
    {
        var (n, d) = Scaled(Numerator, Denominator, Exponent);
        var text = new StringBuilder();
        if (Negative && (Numerator != 0 || keepZeroSign)) text.Append('-');
        text.Append(n / d);
        long remainder = n % d;
        if (remainder != 0)
        {
            text.Append('.');
            while (remainder != 0)
            {
                remainder *= 10;
                text.Append((char)('0' + remainder / d));
                remainder %= d;
            }
        }
        return text.ToString();
    }

    public static Exact Product(Exact a, Exact b) =>
        new(a.Numerator * b.Numerator, a.Exponent + b.Exponent, a.Denominator * b.Denominator, a.Negative != b.Negative);

    public static Exact Sum(IReadOnlyList<Exact> terms, Mode mode)
    {
        int? exponent = null;
        foreach (var term in terms)
            if (term.Numerator != 0 && (exponent is null || term.Exponent < exponent.Value)) exponent = term.Exponent;
        if (exponent is null)
        {
            bool same = terms.All(term => term.Negative == terms[0].Negative);
            return new(0, Negative: same ? terms[0].Negative : mode == Mode.Rdn);
        }
        // Terms in sums and differences are dyadic, so their denominators are 1.
        long numerator = 0;
        foreach (var term in terms)
        {
            if (term.Numerator == 0) continue;
            long aligned = term.Numerator << (term.Exponent - exponent.Value);
            numerator += term.Negative ? -aligned : aligned;
        }
        return new(Math.Abs(numerator), exponent.Value, Negative: numerator < 0 || numerator == 0 && mode == Mode.Rdn);
    }
}

static class Notation
{
    public static string ModeText(Mode mode) => mode.ToString().ToUpperInvariant();
    public static string Binary(int value, int width) => Convert.ToString(value, 2).PadLeft(width, '0');
    public static string Relation(int a, int b) => a < b ? "LT" : a > b ? "GT" : "EQ";

    public static string FlagsText(FpFlags flags)
    {
        (FpFlags Flag, string Name)[] names =
        [
            (FpFlags.Invalid, "invalid"), (FpFlags.DivByZero, "divbyzero"), (FpFlags.Overflow, "overflow"),
            (FpFlags.Underflow, "underflow"), (FpFlags.Inexact, "inexact")
        ];
        var raised = new List<string>();
        foreach (var (flag, name) in names) if ((flags & flag) != 0) raised.Add(name);
        return "flags=" + (raised.Count == 0 ? "none" : string.Join(',', raised));
    }
}

sealed record MiniFormat(string Name, int E, int M)
{
    public int Width => 1 + E + M;
    public int Bias => (1 << (E - 1)) - 1;
    public int MinExponent => 1 - Bias;
    public int MaxExponent => Bias;
    public int Hidden => 1 << M;
    public int ExponentMask => (1 << E) - 1;
    public int SignBit => 1 << (E + M);
    public int Infinity => ExponentMask * Hidden;
    public int NaN => Infinity + Hidden / 2;
    public int Maximum => Infinity - 1;

    public Fields Fields(int pattern)
    {
        int exponent = (pattern >> M) & ExponentMask;
        return new((pattern & SignBit) != 0, exponent, pattern & (Hidden - 1), (exponent == 0 ? MinExponent : exponent - Bias) - M);
    }
    public bool IsNaN(int pattern) => Fields(pattern).Exponent == ExponentMask && Fields(pattern).Fraction != 0;
    public bool IsSignaling(int pattern) => IsNaN(pattern) && Fields(pattern).Fraction < Hidden / 2;
    public bool IsInfinity(int pattern) => (pattern & (SignBit - 1)) == Infinity;
    public bool IsZero(int pattern) => (pattern & (SignBit - 1)) == 0;
    public bool IsFinite(int pattern) => Fields(pattern).Exponent != ExponentMask;
    public int Zero(bool negative) => negative ? SignBit : 0;
    public int Inf(bool negative) => Zero(negative) + Infinity;
    public int Flip(int pattern) => pattern ^ SignBit;

    public Exact Exact(int pattern)
    {
        var fields = Fields(pattern);
        return new(fields.Exponent == 0 ? fields.Fraction : Hidden + fields.Fraction, fields.Q, Negative: fields.Negative);
    }
    public string Bits(int pattern)
    {
        var fields = Fields(pattern);
        return $"{(fields.Negative ? 1 : 0)}|{Notation.Binary(fields.Exponent, E)}|{Notation.Binary(fields.Fraction, M)}";
    }
    public string Hex(int pattern) => "0x" + pattern.ToString($"X{(Width + 3) / 4}", CultureInfo.InvariantCulture);
    public string Value(int pattern) => IsNaN(pattern) ? "nan" : IsInfinity(pattern) ? (Fields(pattern).Negative ? "-inf" : "inf") : Exact(pattern).Decimal(true);
    public string PatternText(int pattern) => $"{Bits(pattern)} {Hex(pattern)} {Value(pattern)}";
    public string ResultText(Result result) => $"{PatternText(result.Pattern)} {Notation.FlagsText(result.Flags)}";

    Result Overflow(bool negative, Mode mode)
    {
        bool infinity = mode is Mode.Rne or Mode.Rna || mode == Mode.Rup && !negative || mode == Mode.Rdn && negative;
        return new(Zero(negative) + (infinity ? Infinity : Maximum), FpFlags.Overflow | FpFlags.Inexact);
    }

    Result RoundNonzero(bool negative, int t, Mode mode, Func<int, Units> unitsAt)
    {
        if (t > MaxExponent) return Overflow(negative, mode);
        int exponent = Math.Max(t, MinExponent) - M;
        var units = unitsAt(exponent);
        long n = units.Integer;
        if (n == 2 * Hidden) { n = Hidden; exponent++; }
        if (exponent > MaxExponent - M) return Overflow(negative, mode);
        int magnitude = n >= Hidden ? (exponent + M + Bias) * Hidden + (int)n - Hidden : (int)n;
        var flags = units.Inexact ? FpFlags.Inexact : FpFlags.None;
        if (units.Inexact && t < MinExponent && (t < MinExponent - 1 || unitsAt(t - M).Integer < 2 * Hidden)) flags |= FpFlags.Underflow;
        return new(Zero(negative) + magnitude, flags);
    }

    public Result Round(Exact value, Mode mode) => value.Numerator == 0 ? new(Zero(value.Negative))
        : RoundNonzero(value.Negative, value.Log2Floor(), mode, exponent => RoundUnits(value, exponent, mode));

    public Result Sqrt(Exact value, Mode mode)
    {
        int log = value.Log2Floor();
        int exponent = log >= 0 ? log / 2 : -((-log + 1) / 2);
        return RoundNonzero(false, exponent, mode, q => RoundSqrtUnits(value, q, mode));
    }
}

readonly record struct RealInput(RealKind Kind, Exact Number)
{
    public string Text => Kind == RealKind.Finite ? Number.Fraction() : Kind == RealKind.NaN ? "nan" : Number.Negative ? "-inf" : "inf";
}

static class Parsing
{
    public static Mode ModeAt(string[] words, int index) => index == words.Length ? Mode.Rne : words[index] switch
    {
        "RNE" => Mode.Rne, "RNA" => Mode.Rna, "RTZ" => Mode.Rtz, "RUP" => Mode.Rup, "RDN" => Mode.Rdn,
        _ => throw new CommandError($"BAD MODE {words[index]}")
    };

    public static RealInput Real(string word)
    {
        if (word == "nan") return new(RealKind.NaN, new(0));
        if (word is "inf" or "-inf") return new(RealKind.Infinity, new(0, Negative: word == "-inf"));
        if (word.StartsWith("0b", StringComparison.Ordinal) || word.StartsWith("0x", StringComparison.Ordinal)) throw new CommandError($"BAD OPERAND {word}");
        bool negative = word[0] == '-';
        string body = negative ? word[1..] : word;
        int slash = body.IndexOf('/');
        if (slash >= 0)
        {
            long n = long.Parse(body[..slash]), d = long.Parse(body[(slash + 1)..]);
            if (d == 0) throw new CommandError($"BAD OPERAND {word}");
            return new(RealKind.Finite, new(n, Denominator: d, Negative: negative));
        }
        int dot = body.IndexOf('.');
        long denominator = 1;
        if (dot >= 0)
        {
            for (int i = dot + 1; i < body.Length; i++) denominator *= 10;
            body = body.Remove(dot, 1);
        }
        return new(RealKind.Finite, new(long.Parse(body), Denominator: denominator, Negative: negative));
    }

    public static Result Encoded(MiniFormat format, RealInput input, Mode mode) => input.Kind switch
    {
        RealKind.NaN => new(format.NaN),
        RealKind.Infinity => new(format.Inf(input.Number.Negative)),
        _ => format.Round(input.Number, mode)
    };

    public static int Operand(MiniFormat format, string word)
    {
        bool bits = word.StartsWith("0b", StringComparison.Ordinal), hex = word.StartsWith("0x", StringComparison.Ordinal);
        if (bits || hex)
        {
            if (word.Length - 2 != (bits ? format.Width : (format.Width + 3) / 4)) throw new CommandError($"BAD OPERAND {word}");
            int pattern = Convert.ToInt32(word[2..], bits ? 2 : 16);
            if (pattern >= 1 << format.Width) throw new CommandError($"BAD OPERAND {word}");
            return pattern;
        }
        return Encoded(format, Real(word), Mode.Rne).Pattern;
    }
}

static class Arithmetic
{
    public static Result Apply(MiniFormat format, Operation operation, Mode mode, params int[] inputs)
    {
        if (inputs.Any(format.IsNaN)) return new(format.NaN, inputs.Any(format.IsSignaling) ? FpFlags.Invalid : FpFlags.None);
        int a = inputs[0];
        bool negative = format.Fields(a).Negative;
        var invalid = new Result(format.NaN, FpFlags.Invalid);
        if (operation == Operation.Sqrt)
        {
            if (format.IsZero(a)) return new(a);
            if (negative) return invalid;
            if (format.IsInfinity(a)) return new(a);
            return format.Sqrt(format.Exact(a), mode);
        }
        int b = operation == Operation.Sub ? format.Flip(inputs[1]) : inputs[1];
        bool sigma = negative != format.Fields(b).Negative;
        if (operation is Operation.Add or Operation.Sub)
        {
            if (format.IsInfinity(a) && format.IsInfinity(b) && sigma) return invalid;
            if (format.IsInfinity(a)) return new(a);
            if (format.IsInfinity(b)) return new(b);
            return format.Round(Exact.Sum([format.Exact(a), format.Exact(b)], mode), mode);
        }
        if (operation == Operation.Mul)
        {
            if (format.IsInfinity(a) || format.IsInfinity(b)) return format.IsZero(a) || format.IsZero(b) ? invalid : new(format.Inf(sigma));
            if (format.IsZero(a) || format.IsZero(b)) return new(format.Zero(sigma));
            return format.Round(Exact.Product(format.Exact(a), format.Exact(b)), mode);
        }
        if (operation == Operation.Div)
        {
            if (format.IsInfinity(a)) return format.IsInfinity(b) ? invalid : new(format.Inf(sigma));
            if (format.IsInfinity(b)) return new(format.Zero(sigma));
            if (format.IsZero(b)) return format.IsZero(a) ? invalid : new(format.Inf(sigma), FpFlags.DivByZero);
            if (format.IsZero(a)) return new(format.Zero(sigma));
            var x = format.Exact(a);
            var y = format.Exact(b);
            return format.Round(new(x.Numerator * y.Denominator, x.Exponent - y.Exponent, x.Denominator * y.Numerator, sigma), mode);
        }
        int c = inputs[2];
        if (format.IsInfinity(a) || format.IsInfinity(b))
        {
            if (format.IsZero(a) || format.IsZero(b) || format.IsInfinity(c) && format.Fields(c).Negative != sigma) return invalid;
            return new(format.Inf(sigma));
        }
        if (format.IsInfinity(c)) return new(c);
        return format.Round(Exact.Sum([Exact.Product(format.Exact(a), format.Exact(b)), format.Exact(c)], mode), mode);
    }

    public static int NextUp(MiniFormat format, int pattern) => pattern == format.Infinity ? pattern
        : format.IsZero(pattern) ? 1 : pattern + (format.Fields(pattern).Negative ? -1 : 1);

    public static string Difference(MiniFormat format, int pattern, Exact exact) => !format.IsFinite(pattern) ? format.Value(pattern)
        : Exact.Sum([format.Exact(pattern), exact.Negated()], Mode.Rne).Fraction();
}

sealed class Laboratory
{
    readonly Dictionary<string, MiniFormat> formats = new(StringComparer.Ordinal)
    {
        ["HALF"] = new("HALF", 5, 10), ["E5M2"] = new("E5M2", 5, 2), ["E4M3"] = new("E4M3", 4, 3)
    };
    static readonly Dictionary<string, (long Minimum, long Maximum)> integerTypes = new(StringComparer.Ordinal)
    {
        ["I8"] = (-128, 127), ["U8"] = (0, 255), ["I16"] = (-32768, 32767), ["U16"] = (0, 65535),
        ["I32"] = (-2147483648L, 2147483647L), ["U32"] = (0, 4294967295L)
    };
    static readonly Dictionary<string, Operation> operations = new(StringComparer.Ordinal)
    {
        ["ADD"] = Operation.Add, ["SUB"] = Operation.Sub, ["MUL"] = Operation.Mul,
        ["DIV"] = Operation.Div, ["SQRT"] = Operation.Sqrt, ["FMA"] = Operation.Fma
    };
    readonly List<string> output = [];
    void Emit(string line) => output.Add(line);
    MiniFormat Format(string name) => formats.TryGetValue(name, out var format) ? format : throw new CommandError($"UNKNOWN FORMAT {name}");

    static int[] Operands(MiniFormat format, string[] words, int begin, int end)
    {
        int[] patterns = new int[end - begin];
        for (int i = begin; i < end; i++) patterns[i - begin] = Parsing.Operand(format, words[i]);
        return patterns;
    }

    void Summary(MiniFormat format, Mode mode, int[] patterns, Result result)
    {
        var exact = Exact.Sum(patterns.Select(format.Exact).ToArray(), mode);
        Emit($"RESULT {format.ResultText(result)}");
        Emit($"EXACT {exact.Decimal()}");
        Emit($"ROUNDED {format.ResultText(format.Round(exact, mode))}");
        Emit($"DIFF {Arithmetic.Difference(format, result.Pattern, exact)}");
    }

    void Summation(string command, MiniFormat format, Mode mode, int[] patterns)
    {
        if (!patterns.All(format.IsFinite)) throw new CommandError("NOT FINITE");
        Emit($"{command} {format.Name} {Notation.ModeText(mode)} count={patterns.Length}");
        int sum = patterns[0], compensation = 0;
        var flags = FpFlags.None;
        for (int i = 1; i < patterns.Length; i++)
        {
            if (command == "SUM")
            {
                var added = Arithmetic.Apply(format, Operation.Add, mode, sum, patterns[i]);
                sum = added.Pattern;
                flags |= added.Flags;
                Emit($"PARTIAL {i + 1} {format.ResultText(added)}");
            }
            else
            {
                var y = Arithmetic.Apply(format, Operation.Sub, mode, patterns[i], compensation);
                var t = Arithmetic.Apply(format, Operation.Add, mode, sum, y.Pattern);
                var d = Arithmetic.Apply(format, Operation.Sub, mode, t.Pattern, sum);
                var c = Arithmetic.Apply(format, Operation.Sub, mode, d.Pattern, y.Pattern);
                sum = t.Pattern;
                compensation = c.Pattern;
                var step = y.Flags | t.Flags | d.Flags | c.Flags;
                flags |= step;
                Emit($"KSTEP {i + 1} sum={format.Value(sum)} comp={format.Value(compensation)} {Notation.FlagsText(step)}");
            }
        }
        Summary(format, mode, patterns, new(sum, flags));
    }

    void Dot(MiniFormat format, Mode mode, int[] a, int[] b)
    {
        if (a.Length != b.Length) throw new CommandError("LENGTH MISMATCH");
        if (!a.All(format.IsFinite) || !b.All(format.IsFinite)) throw new CommandError("NOT FINITE");
        var naive = Arithmetic.Apply(format, Operation.Mul, mode, a[0], b[0]);
        var chained = naive;
        for (int i = 1; i < a.Length; i++)
        {
            var product = Arithmetic.Apply(format, Operation.Mul, mode, a[i], b[i]);
            var added = Arithmetic.Apply(format, Operation.Add, mode, naive.Pattern, product.Pattern);
            naive = new(added.Pattern, naive.Flags | product.Flags | added.Flags);
            var fused = Arithmetic.Apply(format, Operation.Fma, mode, a[i], b[i], chained.Pattern);
            chained = new(fused.Pattern, chained.Flags | fused.Flags);
        }
        var terms = new Exact[a.Length];
        for (int i = 0; i < a.Length; i++) terms[i] = Exact.Product(format.Exact(a[i]), format.Exact(b[i]));
        var exact = Exact.Sum(terms, mode);
        Emit($"DOT {format.Name} {Notation.ModeText(mode)} n={a.Length}");
        Emit($"NAIVE {format.ResultText(naive)}");
        Emit($"CHAINED {format.ResultText(chained)}");
        Emit($"EXACT {exact.Decimal()}");
        Emit($"FUSED {format.ResultText(format.Round(exact, mode))}");
        Emit($"DIFF naive={Arithmetic.Difference(format, naive.Pattern, exact)} chained={Arithmetic.Difference(format, chained.Pattern, exact)}");
    }

    void Table(MiniFormat format)
    {
        if (format.Width > 8) throw new CommandError("TABLE TOO LARGE");
        int count = format.Infinity;
        Emit($"TABLE {format.Name} count={count}");
        for (int pattern = 0; pattern < count; pattern++)
        {
            string gap = pattern == count - 1 ? "-" : Exact.Sum([format.Exact(pattern + 1), format.Exact(pattern).Negated()], Mode.Rne).Decimal();
            Emit($"ENTRY {pattern} {format.PatternText(pattern)} gap={gap}");
        }
        Emit($"MAX {format.PatternText(format.Maximum)}");
        Emit($"MINNORMAL {format.PatternText(format.Hidden)}");
        Emit($"MINSUBNORMAL {format.PatternText(1)}");
        Emit($"EPSILON {new Exact(1, -format.M).Decimal()}");
        Emit($"PATTERNS finite={2 * count} infinite=2 nan={2 * (format.Hidden - 1)} total={1 << format.Width}");
    }

    public IReadOnlyList<string> Execute(string line)
    {
        output.Clear();
        string[] words = line.Split(' ');
        string command = words[0];
        if (command == "FORMAT")
        {
            string name = words[1];
            int e = int.Parse(words[2]), m = int.Parse(words[3]);
            if (formats.ContainsKey(name)) throw new CommandError($"FORMAT EXISTS {name}");
            if (e < 2 || e > 5 || m < 1 || m > 10) throw new CommandError("BAD FORMAT");
            var format = new MiniFormat(name, e, m);
            formats.Add(name, format);
            Emit($"FORMAT {name} e={e} m={m} bits={format.Width} bias={format.Bias} emin={format.MinExponent} emax={format.MaxExponent}");
            return output;
        }
        var f = Format(words[1]);
        if (command == "ENCODE")
        {
            var input = Parsing.Real(words[2]);
            var mode = Parsing.ModeAt(words, 3);
            Emit($"ENCODE {f.Name} {Notation.ModeText(mode)} {input.Text} {f.ResultText(Parsing.Encoded(f, input, mode))}");
        }
        else if (command == "CONVERT")
        {
            var g = Format(words[2]);
            int a = Parsing.Operand(f, words[3]);
            var mode = Parsing.ModeAt(words, 4);
            Result result = f.IsNaN(a) ? new(g.NaN, f.IsSignaling(a) ? FpFlags.Invalid : FpFlags.None)
                : f.IsInfinity(a) ? new(g.Inf(f.Fields(a).Negative)) : g.Round(f.Exact(a), mode);
            Emit($"CONVERT {f.Name} {g.Name} {Notation.ModeText(mode)} {g.ResultText(result)}");
        }
        else if (command is "SUM" or "KAHAN" or "DOT")
        {
            var mode = Parsing.ModeAt(words, 2);
            if (command == "DOT")
            {
                int separator = Array.IndexOf(words, "|");
                var a = Operands(f, words, 3, separator);
                var b = Operands(f, words, separator + 1, words.Length);
                Dot(f, mode, a, b);
            }
            else Summation(command, f, mode, Operands(f, words, 3, words.Length));
        }
        else if (command == "TABLE") Table(f);
        else if (operations.TryGetValue(command, out var op))
        {
            int count = op == Operation.Sqrt ? 1 : op == Operation.Fma ? 3 : 2;
            var patterns = Operands(f, words, 2, 2 + count);
            var mode = Parsing.ModeAt(words, 2 + count);
            Emit($"{command} {f.Name} {Notation.ModeText(mode)} {f.ResultText(Arithmetic.Apply(f, op, mode, patterns))}");
        }
        else
        {
            int a = Parsing.Operand(f, words[2]);
            var fields = f.Fields(a);
            if (command == "DECODE")
            {
                string classification = f.IsNaN(a) ? (f.IsSignaling(a) ? "snan" : "qnan") : f.IsInfinity(a) ? "infinity"
                    : f.IsZero(a) ? "zero" : fields.Exponent == 0 ? "subnormal" : "normal";
                Emit($"DECODE {f.Name} {f.Bits(a)} {f.Hex(a)} {classification} sign={(fields.Negative ? 1 : 0)}");
                string heading = $"FIELDS exponent={fields.Exponent} fraction={fields.Fraction}";
                if (f.IsFinite(a))
                {
                    Emit($"{heading} unbiased={fields.Q + f.M} significand={(fields.Exponent == 0 ? 0 : 1)}.{Notation.Binary(fields.Fraction, f.M)}");
                    Emit($"VALUE {f.Exact(a).Fraction()} {f.Value(a)}");
                }
                else Emit(f.IsNaN(a) ? $"{heading} payload={fields.Fraction % (f.Hidden / 2)}" : heading);
            }
            else if (command == "COMPARE")
            {
                int b = Parsing.Operand(f, words[3]);
                int Key(int pattern) => f.Fields(pattern).Negative ? -(pattern - f.SignBit) - 1 : pattern;
                string order = Notation.Relation(Key(a), Key(b));
                string numeric = f.IsNaN(a) || f.IsNaN(b) ? "UN" : f.IsZero(a) && f.IsZero(b) ? "EQ" : order;
                var flags = f.IsSignaling(a) || f.IsSignaling(b) ? FpFlags.Invalid : FpFlags.None;
                Emit($"COMPARE {f.Name} {f.Hex(a)} {f.Hex(b)} {numeric} total={order} {Notation.FlagsText(flags)}");
            }
            else if (command == "TOINT")
            {
                if (!integerTypes.TryGetValue(words[3], out var range)) throw new CommandError($"BAD TYPE {words[3]}");
                var mode = Parsing.ModeAt(words, 4);
                string prefix = $"TOINT {f.Name} {words[3]} {Notation.ModeText(mode)}";
                if (!f.IsFinite(a)) Emit($"{prefix} invalid flags=invalid");
                else
                {
                    var units = RoundUnits(f.Exact(a), 0, mode);
                    long integer = fields.Negative ? -units.Integer : units.Integer;
                    Emit(integer < range.Minimum || integer > range.Maximum ? $"{prefix} invalid flags=invalid"
                        : $"{prefix} {integer} {Notation.FlagsText(units.Inexact ? FpFlags.Inexact : FpFlags.None)}");
                }
            }
            else
            {
                Result result;
                if (f.IsNaN(a)) result = new(f.NaN, f.IsSignaling(a) ? FpFlags.Invalid : FpFlags.None);
                else if (command == "NEXTUP") result = new(Arithmetic.NextUp(f, a));
                else if (command == "NEXTDOWN") result = new(f.Flip(Arithmetic.NextUp(f, f.Flip(a))));
                else result = new(f.IsInfinity(a) ? f.Infinity : f.Round(new(1, fields.Q), Mode.Rne).Pattern);
                Emit($"{command} {f.Name} {f.ResultText(result)}");
            }
        }
        return output;
    }
}

static class Program
{
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Console.Out.NewLine = "\n";
        int count = int.Parse(Console.ReadLine()!);
        var laboratory = new Laboratory();
        for (int i = 0; i < count; i++)
        {
            try { foreach (string line in laboratory.Execute(Console.ReadLine()!)) Console.WriteLine(line); }
            catch (CommandError error) { Console.WriteLine($"ERROR {error.Message}"); }
        }
    }
}
