using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Text;
using static Binary;

sealed class CommandError(string message) : Exception(message) {}
readonly record struct Echelon(uint[] Rows, int[] Columns);
readonly record struct Decoded(uint Error, uint Word, uint Message);

static class Binary
{
    public static void Fail(string reason) => throw new CommandError(reason);
    public static bool Bit(uint word, int length, int column) => ((word >> (length - column - 1)) & 1) != 0;
    public static int Weight(uint word) => BitOperations.PopCount(word);
    public static int Degree(uint word) => word == 0 ? -1 : BitOperations.Log2(word);
    public static string Yes(bool value) => value ? "yes" : "no";
    public static uint ParseBits(string text)
    {
        uint word = 0;
        foreach (char digit in text) word = (word << 1) | (uint)(digit - '0');
        return word;
    }
    public static string Bits(uint word, int length)
    {
        char[] text = new char[length];
        for (int column = 0; column < length; column++) text[column] = Bit(word, length, column) ? '1' : '0';
        return new string(text);
    }
    public static (uint Quotient, uint Remainder) Divide(uint dividend, uint divisor)
    {
        uint quotient = 0;
        int degree = Degree(divisor);
        while (dividend != 0 && Degree(dividend) >= degree)
        {
            int shift = Degree(dividend) - degree;
            quotient ^= 1u << shift;
            dividend ^= divisor << shift;
        }
        return (quotient, dividend);
    }
    public static uint[] Basis(IEnumerable<uint> rows, int length)
    {
        uint[] pivots = new uint[length];
        List<uint> kept = [];
        foreach (uint original in rows)
        {
            uint row = original;
            for (int column = 0; column < length; column++)
            {
                if (!Bit(row, length, column)) continue;
                if (pivots[column] != 0) row ^= pivots[column];
                else { pivots[column] = row; kept.Add(original); break; }
            }
        }
        return kept.ToArray();
    }
    public static Echelon Rref(IEnumerable<uint> original, int length)
    {
        uint[] rows = original.ToArray();
        List<int> columns = [];
        for (int column = 0; column < length; column++)
        {
            int pivot = columns.Count, found = pivot;
            while (found < rows.Length && !Bit(rows[found], length, column)) found++;
            if (found == rows.Length) continue;
            (rows[pivot], rows[found]) = (rows[found], rows[pivot]);
            for (int row = 0; row < rows.Length; row++) if (row != pivot && Bit(rows[row], length, column)) rows[row] ^= rows[pivot];
            columns.Add(column);
        }
        return new Echelon(rows[..columns.Count], columns.ToArray());
    }
    public static uint[] Nullspace(IEnumerable<uint> rows, int length)
    {
        Echelon reduced = Rref(rows, length);
        List<uint> result = [];
        for (int column = 0; column < length; column++)
        {
            if (reduced.Columns.Contains(column)) continue;
            uint word = 1u << (length - column - 1);
            for (int row = 0; row < reduced.Rows.Length; row++)
                if (Bit(reduced.Rows[row], length, column)) word |= 1u << (length - reduced.Columns[row] - 1);
            result.Add(word);
        }
        return result.ToArray();
    }
    public static uint[] Span(uint[] rows)
    {
        List<uint> words = [0];
        foreach (uint row in rows)
        {
            int count = words.Count;
            for (int index = 0; index < count; index++) words.Add(words[index] ^ row);
        }
        return words.ToArray();
    }
    public static int[] Distribution(IEnumerable<uint> words, int length)
    {
        int[] counts = new int[length + 1];
        foreach (uint word in words) counts[Weight(word)]++;
        return counts;
    }
    public static string WeightList(int[] counts) => string.Join(" ", Enumerable.Range(0, counts.Length).Where(i => counts[i] != 0).Select(i => $"{i}:{counts[i]}"));
    public static void CheckDimension(int n, int k)
    {
        if (k < 1 || k > 12 || n - k < 1 || n - k > 12) Fail($"bad dimension {n} {k}");
    }
    public static uint RemoveBit(uint word, int length, int column)
    {
        int low = length - column - 1;
        return ((word >> (low + 1)) << low) | (word & ((1u << low) - 1));
    }
    public static uint[] ReedMuller(int order, int variables)
    {
        int length = 1 << variables;
        if (order == 0) return [(1u << length) - 1];
        List<uint> rows = [];
        foreach (uint row in ReedMuller(Math.Min(order, variables - 1), variables - 1)) rows.Add((row << (length / 2)) | row);
        rows.AddRange(ReedMuller(order - 1, variables - 1));
        return rows.ToArray();
    }
    public static long Gcd(long a, long b)
    {
        a = Math.Abs(a); b = Math.Abs(b);
        while (b != 0) (a, b) = (b, a % b);
        return a;
    }
    private static readonly long[,] Choose = BuildChoose();
    private static long[,] BuildChoose()
    {
        long[,] result = new long[25, 25];
        for (int n = 0; n <= 24; n++)
        {
            result[n, 0] = result[n, n] = 1;
            for (int k = 1; k < n; k++) result[n, k] = result[n - 1, k - 1] + result[n - 1, k];
        }
        return result;
    }
    public static long Binomial(int n, int k) => k < 0 || k > n ? 0 : Choose[n, k];
    public static long Volume(int n, int radius)
    {
        long result = 0;
        for (int i = 0; i <= radius; i++) result += Binomial(n, i);
        return result;
    }
    public static long Krawtchouk(int n, int degree, int x)
    {
        long result = 0;
        for (int y = 0; y <= degree; y++) result += (y % 2 == 0 ? 1 : -1) * Binomial(x, y) * Binomial(n - x, degree - y);
        return result;
    }
}

sealed class Code
{
    public int N { get; }
    public int K { get; }
    public uint[] G { get; }
    public uint[] H { get; }
    public uint[] Words { get; }
    public uint? Polynomial { get; }
    private readonly Dictionary<uint, uint> messages = [];
    private uint[]? leaders;
    public string Encoder => Polynomial.HasValue ? "polynomial" : "matrix";

    public Code(int n, uint[] generator, uint[]? check = null, uint? polynomial = null)
    {
        N = n; K = generator.Length;
        CheckDimension(N, K);
        G = generator; H = check ?? Nullspace(G, N); Polynomial = polynomial;
        Words = new uint[1 << K];
        for (int message = 0; message < Words.Length; message++)
        {
            uint word = Encode((uint)message);
            Words[message] = word; messages.Add(word, (uint)message);
        }
        Array.Sort(Words);
    }
    public uint Encode(uint message)
    {
        if (Polynomial is uint polynomial)
        {
            uint shifted = message << (N - K);
            return shifted | Divide(shifted, polynomial).Remainder;
        }
        uint result = 0;
        for (int row = 0; row < K; row++) if (Bit(message, K, row)) result ^= G[row];
        return result;
    }
    public uint Syndrome(uint word)
    {
        uint result = 0;
        foreach (uint row in H) result = (result << 1) | (uint)(Weight(row & word) % 2);
        return result;
    }
    public uint Message(uint word) => messages[word];
    public bool Contains(uint word) => messages.ContainsKey(word);
    public uint[] Leaders()
    {
        if (leaders is not null) return leaders;
        uint[] result = new uint[1 << (N - K)];
        Array.Fill(result, uint.MaxValue);
        result[0] = 0;
        int remaining = result.Length - 1;
        for (int count = 1; remaining > 0; count++)
        {
            for (uint word = (1u << count) - 1; word < (1u << N);)
            {
                uint syndrome = Syndrome(word);
                if (result[syndrome] == uint.MaxValue)
                {
                    result[syndrome] = word;
                    if (--remaining == 0) break;
                }
                uint lowest = word & unchecked(0u - word), next = word + lowest;
                word = next | (((next ^ word) >> 2) / lowest);
            }
        }
        return leaders = result;
    }
    public Decoded Decode(uint received)
    {
        uint error = Leaders()[Syndrome(received)], word = received ^ error;
        return new Decoded(error, word, messages[word]);
    }
    public string DecodedText(Decoded result) => $"codeword {Bits(result.Word, N)} message {Bits(result.Message, K)} error {Bits(result.Error, N)} weight {Weight(result.Error)}";
}

enum CommandKind
{
    Gen, Pcheck, Hamming, Simplex, Repetition, Parity, Rm, Cyclic, Dual, Extend, Puncture, Shorten, Augment, Expurgate,
    Permute, Directsum, Uuv, Product, List, Delete, Show, Info, Systematic, Weights, Covering, Burst, Trellis, Stdarray,
    Equal, Encode, Syndrome, Decode, Bounded, Coset, Erasure, Interleave, Crc, Crccheck, Factor, Macwilliams, Bounds
}
enum ArgumentKind { Name, Code, Number, Bits, Erasure }
sealed record Format(CommandKind Kind, ArgumentKind[] Fixed, ArgumentKind? Repeated = null, int Maximum = 0);
sealed record Command(CommandKind Kind, string[] Args);

sealed class Laboratory
{
    private readonly SortedDictionary<string, Code> codes = new(StringComparer.Ordinal);
    private static readonly Dictionary<string, Format> Formats = new(StringComparer.Ordinal)
    {
        ["GEN"] = new(CommandKind.Gen, [ArgumentKind.Name], ArgumentKind.Bits, 24),
        ["PCHECK"] = new(CommandKind.Pcheck, [ArgumentKind.Name], ArgumentKind.Bits, 24),
        ["HAMMING"] = new(CommandKind.Hamming, [ArgumentKind.Name, ArgumentKind.Number]),
        ["SIMPLEX"] = new(CommandKind.Simplex, [ArgumentKind.Name, ArgumentKind.Number]),
        ["REPETITION"] = new(CommandKind.Repetition, [ArgumentKind.Name, ArgumentKind.Number]),
        ["PARITY"] = new(CommandKind.Parity, [ArgumentKind.Name, ArgumentKind.Number]),
        ["RM"] = new(CommandKind.Rm, [ArgumentKind.Name, ArgumentKind.Number, ArgumentKind.Number]),
        ["CYCLIC"] = new(CommandKind.Cyclic, [ArgumentKind.Name, ArgumentKind.Number, ArgumentKind.Bits]),
        ["DUAL"] = new(CommandKind.Dual, [ArgumentKind.Name, ArgumentKind.Code]),
        ["EXTEND"] = new(CommandKind.Extend, [ArgumentKind.Name, ArgumentKind.Code]),
        ["PUNCTURE"] = new(CommandKind.Puncture, [ArgumentKind.Name, ArgumentKind.Code, ArgumentKind.Number]),
        ["SHORTEN"] = new(CommandKind.Shorten, [ArgumentKind.Name, ArgumentKind.Code, ArgumentKind.Number]),
        ["AUGMENT"] = new(CommandKind.Augment, [ArgumentKind.Name, ArgumentKind.Code]),
        ["EXPURGATE"] = new(CommandKind.Expurgate, [ArgumentKind.Name, ArgumentKind.Code]),
        ["PERMUTE"] = new(CommandKind.Permute, [ArgumentKind.Name, ArgumentKind.Code], ArgumentKind.Number, 24),
        ["DIRECTSUM"] = new(CommandKind.Directsum, [ArgumentKind.Name, ArgumentKind.Code, ArgumentKind.Code]),
        ["UUV"] = new(CommandKind.Uuv, [ArgumentKind.Name, ArgumentKind.Code, ArgumentKind.Code]),
        ["PRODUCT"] = new(CommandKind.Product, [ArgumentKind.Name, ArgumentKind.Code, ArgumentKind.Code]),
        ["LIST"] = new(CommandKind.List, []),
        ["DELETE"] = new(CommandKind.Delete, [ArgumentKind.Code]),
        ["SHOW"] = new(CommandKind.Show, [ArgumentKind.Code]),
        ["INFO"] = new(CommandKind.Info, [ArgumentKind.Code]),
        ["SYSTEMATIC"] = new(CommandKind.Systematic, [ArgumentKind.Code]),
        ["WEIGHTS"] = new(CommandKind.Weights, [ArgumentKind.Code]),
        ["COVERING"] = new(CommandKind.Covering, [ArgumentKind.Code]),
        ["BURST"] = new(CommandKind.Burst, [ArgumentKind.Code]),
        ["TRELLIS"] = new(CommandKind.Trellis, [ArgumentKind.Code]),
        ["STDARRAY"] = new(CommandKind.Stdarray, [ArgumentKind.Code]),
        ["EQUAL"] = new(CommandKind.Equal, [ArgumentKind.Code, ArgumentKind.Code]),
        ["ENCODE"] = new(CommandKind.Encode, [ArgumentKind.Code, ArgumentKind.Bits]),
        ["SYNDROME"] = new(CommandKind.Syndrome, [ArgumentKind.Code, ArgumentKind.Bits]),
        ["DECODE"] = new(CommandKind.Decode, [ArgumentKind.Code, ArgumentKind.Bits]),
        ["BOUNDED"] = new(CommandKind.Bounded, [ArgumentKind.Code, ArgumentKind.Number, ArgumentKind.Bits]),
        ["COSET"] = new(CommandKind.Coset, [ArgumentKind.Code, ArgumentKind.Bits]),
        ["ERASURE"] = new(CommandKind.Erasure, [ArgumentKind.Code, ArgumentKind.Erasure]),
        ["INTERLEAVE"] = new(CommandKind.Interleave, [ArgumentKind.Code, ArgumentKind.Number, ArgumentKind.Number], ArgumentKind.Bits, 8),
        ["CRC"] = new(CommandKind.Crc, [ArgumentKind.Bits, ArgumentKind.Bits]),
        ["CRCCHECK"] = new(CommandKind.Crccheck, [ArgumentKind.Bits, ArgumentKind.Bits]),
        ["FACTOR"] = new(CommandKind.Factor, [ArgumentKind.Number]),
        ["MACWILLIAMS"] = new(CommandKind.Macwilliams, [ArgumentKind.Number], ArgumentKind.Number, 25),
        ["BOUNDS"] = new(CommandKind.Bounds, [ArgumentKind.Number, ArgumentKind.Number]),
    };
    private static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    private static bool Digit(char c) => c is >= '0' and <= '9';
    private static bool Valid(string text, ArgumentKind kind)
    {
        if (text.Length == 0) return false;
        return kind switch
        {
            ArgumentKind.Name or ArgumentKind.Code => text.Length <= 8 && Letter(text[0]) && text.All(c => Letter(c) || Digit(c)),
            ArgumentKind.Number => text.Length <= 4 && (text.Length == 1 || text[0] != '0') && text.All(Digit),
            ArgumentKind.Bits => text.Length <= 30 && text.All(c => c is '0' or '1'),
            ArgumentKind.Erasure => text.Length <= 30 && text.All(c => c is '0' or '1' or '?'),
            _ => false,
        };
    }
    private Command Parse(string line)
    {
        string[] words = line.Split(' ');
        if (!Formats.TryGetValue(words[0], out Format? format)) throw new CommandError("unknown command " + words[0]);
        string[] args = words[1..];
        int extra = args.Length - format.Fixed.Length;
        if (format.Repeated.HasValue ? extra < 1 || extra > format.Maximum : extra != 0) Fail("bad arguments");
        for (int i = 0; i < args.Length; i++) if (!Valid(args[i], i < format.Fixed.Length ? format.Fixed[i] : format.Repeated!.Value)) Fail("bad arguments");
        for (int i = 0; i < format.Fixed.Length; i++) if (format.Fixed[i] == ArgumentKind.Code && !codes.ContainsKey(args[i])) Fail("no code " + args[i]);
        return new Command(format.Kind, args);
    }
    private static bool Defining(CommandKind kind) => kind is CommandKind.Gen or CommandKind.Pcheck or CommandKind.Hamming or CommandKind.Simplex
        or CommandKind.Repetition or CommandKind.Parity or CommandKind.Rm or CommandKind.Cyclic or CommandKind.Dual or CommandKind.Extend
        or CommandKind.Puncture or CommandKind.Shorten or CommandKind.Augment or CommandKind.Expurgate or CommandKind.Permute
        or CommandKind.Directsum or CommandKind.Uuv or CommandKind.Product;

    private List<string> Define(CommandKind kind, string[] args)
    {
        string name = args[0];
        int n = 0;
        uint[] g = [], h;
        uint[]? check = null;
        uint? polynomial = null;
        switch (kind)
        {
            case CommandKind.Gen: case CommandKind.Pcheck:
                n = args[1].Length;
                if (args.Skip(1).Any(word => word.Length != n)) Fail("bad length");
                uint[] basis = Basis(args.Skip(1).Select(ParseBits), n);
                if (kind == CommandKind.Gen) g = basis;
                else { check = basis; g = Nullspace(check, n); }
                break;
            case CommandKind.Hamming: case CommandKind.Simplex:
                int r = int.Parse(args[1]);
                if (r < 2 || r > 4) Fail("bad parameter");
                n = (1 << r) - 1; h = new uint[r];
                for (int column = 1; column <= n; column++) for (int row = 0; row < r; row++) h[row] = (h[row] << 1) | (Bit((uint)column, r, row) ? 1u : 0u);
                if (kind == CommandKind.Hamming) { check = h; g = Nullspace(h, n); }
                else g = h;
                break;
            case CommandKind.Repetition: case CommandKind.Parity:
                n = int.Parse(args[1]);
                if (n < 2 || n > 24) Fail("bad parameter");
                g = kind == CommandKind.Repetition ? [(1u << n) - 1] : Enumerable.Range(0, n - 1).Select(row => (1u << (n - row - 1)) | 1u).ToArray();
                break;
            case CommandKind.Rm:
                int order = int.Parse(args[1]), variables = int.Parse(args[2]);
                if (variables < 1 || variables > 4 || order > variables) Fail("bad parameter");
                n = 1 << variables; g = ReedMuller(order, variables);
                break;
            case CommandKind.Cyclic:
                n = int.Parse(args[1]);
                string text = args[2];
                if (n < 2 || n > 24 || text[0] == '0' || text.Length < 2 || text.Length > n) Fail("bad parameter");
                uint divisor = ParseBits(text); polynomial = divisor;
                if (Divide((1u << n) | 1, divisor).Remainder != 0) Fail("not a divisor");
                int d = text.Length - 1, k = n - d;
                g = Enumerable.Range(0, k).Select(row => divisor << (k - row - 1)).ToArray();
                h = new uint[d];
                for (int column = 0; column < n; column++)
                {
                    uint remainder = Divide(1u << (n - column - 1), divisor).Remainder;
                    for (int row = 0; row < d; row++) h[row] = (h[row] << 1) | (Bit(remainder, d, row) ? 1u : 0u);
                }
                check = h;
                break;
            case CommandKind.Dual:
                Code dual = codes[args[1]];
                n = dual.N; g = dual.H; check = dual.G;
                break;
            case CommandKind.Extend:
                Code extended = codes[args[1]];
                n = extended.N + 1; g = extended.G.Select(row => (row << 1) | (uint)(Weight(row) % 2)).ToArray();
                break;
            case CommandKind.Puncture: case CommandKind.Shorten:
                Code source = codes[args[1]];
                int position = int.Parse(args[2]) - 1;
                if (position < 0 || position >= source.N) Fail("bad position");
                List<uint> rows = source.G.ToList();
                if (kind == CommandKind.Shorten)
                {
                    int pivot = rows.FindIndex(row => Bit(row, source.N, position));
                    if (pivot >= 0)
                    {
                        uint z = rows[pivot]; rows.RemoveAt(pivot);
                        for (int i = 0; i < rows.Count; i++) if (Bit(rows[i], source.N, position)) rows[i] ^= z;
                    }
                }
                n = source.N - 1; g = rows.Select(row => RemoveBit(row, source.N, position)).ToArray();
                if (kind == CommandKind.Puncture) g = Basis(g, n);
                break;
            case CommandKind.Augment:
                Code augmented = codes[args[1]];
                n = augmented.N; g = Basis(augmented.G.Append((1u << n) - 1), n);
                break;
            case CommandKind.Expurgate:
                Code expurgated = codes[args[1]];
                n = expurgated.N; List<uint> even = expurgated.G.ToList();
                int odd = even.FindIndex(row => Weight(row) % 2 != 0);
                if (odd >= 0)
                {
                    uint z = even[odd]; even.RemoveAt(odd);
                    for (int i = 0; i < even.Count; i++) if (Weight(even[i]) % 2 != 0) even[i] ^= z;
                }
                g = even.ToArray();
                break;
            case CommandKind.Permute:
                Code permuted = codes[args[1]];
                n = permuted.N; int[] permutation = args.Skip(2).Select(int.Parse).ToArray();
                if (permutation.Length != n || permutation.Any(column => column < 1 || column > n) || permutation.Distinct().Count() != n) Fail("bad permutation");
                g = permuted.G.Select(row => permutation.Aggregate(0u, (word, column) => (word << 1) | (Bit(row, n, column - 1) ? 1u : 0u))).ToArray();
                break;
            case CommandKind.Directsum: case CommandKind.Uuv: case CommandKind.Product:
                Code a = codes[args[1]], b = codes[args[2]];
                if (kind == CommandKind.Uuv && a.N != b.N) Fail("bad length");
                n = kind == CommandKind.Product ? a.N * b.N : a.N + b.N;
                CheckDimension(n, kind == CommandKind.Product ? a.K * b.K : a.K + b.K);
                List<uint> combined = [];
                if (kind == CommandKind.Product)
                {
                    foreach (uint x in a.G) foreach (uint y in b.G)
                    {
                        uint word = 0;
                        for (int column = 0; column < a.N; column++) word = (word << b.N) | (Bit(x, a.N, column) ? y : 0);
                        combined.Add(word);
                    }
                }
                else
                {
                    foreach (uint row in a.G) combined.Add((row << b.N) | (kind == CommandKind.Uuv ? row : 0));
                    combined.AddRange(b.G);
                }
                g = combined.ToArray();
                break;
            default: throw new InvalidOperationException();
        }
        Code code = new(n, g, check, polynomial);
        bool replaced = codes.ContainsKey(name);
        codes[name] = code;
        return [$"{(replaced ? "redefined" : "defined")} {name} n {n} k {code.K}"];
    }
    private static List<string> Systematic(string name, Code code)
    {
        int n = code.N, k = code.K;
        uint[] rows = (uint[])code.G.Clone();
        int[] permutation = Enumerable.Range(1, n).ToArray();
        for (int pivot = 0; pivot < k; pivot++)
        {
            int column = pivot;
            while (!rows.Skip(pivot).Any(row => Bit(row, n, column))) column++;
            if (column != pivot)
            {
                uint mask = (1u << (n - pivot - 1)) | (1u << (n - column - 1));
                for (int row = 0; row < k; row++) if (Bit(rows[row], n, pivot) != Bit(rows[row], n, column)) rows[row] ^= mask;
                (permutation[pivot], permutation[column]) = (permutation[column], permutation[pivot]);
            }
            int found = pivot;
            while (!Bit(rows[found], n, pivot)) found++;
            (rows[pivot], rows[found]) = (rows[found], rows[pivot]);
            for (int row = 0; row < k; row++) if (row != pivot && Bit(rows[row], n, pivot)) rows[row] ^= rows[pivot];
        }
        List<string> output = [$"systematic {name} perm {string.Join(" ", permutation)}"];
        output.AddRange(rows.Select(row => "G " + Bits(row, n)));
        for (int column = k; column < n; column++)
        {
            uint row = 0;
            foreach (uint value in rows) row = (row << 1) | (Bit(value, n, column) ? 1u : 0u);
            row = (row << (n - k)) | (1u << (n - column - 1));
            output.Add("H " + Bits(row, n));
        }
        return output;
    }
    private static List<string> Burst(string name, Code code)
    {
        int detect = code.N;
        foreach (uint word in code.Words) if (word != 0) detect = Math.Min(detect, Degree(word) - BitOperations.TrailingZeroCount(word));
        bool[] seen = new bool[1 << (code.N - code.K)];
        seen[0] = true;
        for (int length = 1; length <= code.N; length++)
        {
            for (int start = 0; start + length <= code.N; start++)
            {
                uint limit = length == 1 ? 1u : 1u << (length - 2);
                for (uint middle = 0; middle < limit; middle++)
                {
                    uint pattern = length == 1 ? 1u : (1u << (length - 1)) | (middle << 1) | 1;
                    uint syndrome = code.Syndrome(pattern << (code.N - start - length));
                    if (seen[syndrome]) return [$"burst {name} detect {detect} correct {length - 1}"];
                    seen[syndrome] = true;
                }
            }
        }
        throw new InvalidOperationException();
    }
    private static List<string> Interleave(string name, Code code, string[] args)
    {
        int start = int.Parse(args[1]), length = int.Parse(args[2]), depth = args.Length - 3;
        if (args.Skip(3).Any(word => word.Length != code.K)) Fail("bad length");
        if (start < 1 || length < 1 || start + length - 1 > depth * code.N) Fail("bad burst");
        uint[] sentWords = args.Skip(3).Select(word => code.Encode(ParseBits(word))).ToArray(), receivedWords = new uint[depth];
        StringBuilder sent = new(), received = new();
        for (int column = 0; column < code.N; column++) for (int row = 0; row < depth; row++)
        {
            int position = column * depth + row + 1;
            bool original = Bit(sentWords[row], code.N, column), changed = original ^ (position >= start && position < start + length);
            sent.Append(original ? '1' : '0'); received.Append(changed ? '1' : '0');
            receivedWords[row] = (receivedWords[row] << 1) | (changed ? 1u : 0u);
        }
        List<string> output = [$"interleave {name} depth {depth} burst {start} {length}", "sent " + sent, "recv " + received];
        int correct = 0;
        for (int row = 0; row < depth; row++)
        {
            Decoded decoded = code.Decode(receivedWords[row]);
            string message = Bits(decoded.Message, code.K);
            bool ok = message == args[row + 3];
            if (ok) correct++;
            output.Add($"row {row + 1} errors {Weight(receivedWords[row] ^ sentWords[row])} corrected {Weight(decoded.Error)} message {message} {(ok ? "ok" : "wrong")}");
        }
        output.Add($"result ok {correct} wrong {depth - correct}");
        return output;
    }
    private static List<string> Independent(CommandKind kind, string[] args)
    {
        if (kind is CommandKind.Crc or CommandKind.Crccheck)
        {
            string generator = args[0], text = args[1];
            if (generator[0] == '0' || generator.Length < 2 || generator.Length > 17) Fail("bad parameter");
            int degree = generator.Length - 1;
            if (kind == CommandKind.Crc && text.Length + degree > 30) Fail("bad length");
            uint word = ParseBits(text), divisor = ParseBits(generator);
            uint remainder = Divide(kind == CommandKind.Crc ? word << degree : word, divisor).Remainder;
            string suffix = Bits(remainder, degree);
            return [kind == CommandKind.Crc ? $"crc remainder {suffix} frame {text}{suffix}" : $"crccheck {(remainder == 0 ? "ok" : "error")} remainder {suffix}"];
        }
        int n = int.Parse(args[0]);
        if (kind == CommandKind.Bounds)
        {
            int distance = int.Parse(args[1]);
            if (distance < 1 || distance > n || n > 24) Fail("bad parameter");
            long volume = Volume(n, (distance - 1) / 2);
            int hamming = 0, griesmer = 0, sum = 0;
            for (int k = 0; k <= n; k++) if ((1L << k) * volume <= (1L << n)) hamming = k;
            for (int k = 1; k <= n; k++)
            {
                int denominator = 1 << (k - 1);
                sum += (distance + denominator - 1) / denominator;
                if (sum <= n) griesmer = k;
            }
            return [$"bounds n {n} d {distance} singleton {n - distance + 1} hamming {hamming} griesmer {griesmer}"];
        }
        if (n < 1 || n > 24) Fail("bad parameter");
        if (kind == CommandKind.Factor)
        {
            uint remaining = (1u << n) | 1;
            int divisors = 1;
            List<string> factors = [];
            for (uint candidate = 2; 2 * Degree(candidate) <= Degree(remaining); candidate++)
            {
                int exponent = 0;
                while (Divide(remaining, candidate).Remainder == 0) { remaining = Divide(remaining, candidate).Quotient; exponent++; }
                if (exponent > 0) { factors.Add($"{Bits(candidate, Degree(candidate) + 1)}^{exponent}"); divisors *= exponent + 1; }
            }
            if (remaining > 1) { factors.Add(Bits(remaining, Degree(remaining) + 1) + "^1"); divisors *= 2; }
            return [$"factor {n} {string.Join(" ", factors)} divisors {divisors}"];
        }
        if (args.Length != n + 2) Fail("bad length");
        if (int.Parse(args[1]) != 1) Fail("bad parameter");
        long[] counts = args.Skip(1).Select(long.Parse).ToArray();
        long size = counts.Sum();
        bool feasible = (size & (size - 1)) == 0;
        List<string> transformed = [];
        for (int j = 0; j <= n; j++)
        {
            long numerator = 0;
            for (int x = 0; x <= n; x++) numerator += counts[x] * Krawtchouk(n, j, x);
            long divisor = Gcd(numerator, size), p = numerator / divisor, q = size / divisor;
            transformed.Add(q == 1 ? p.ToString() : $"{p}/{q}");
            if (q != 1 || p < 0) feasible = false;
        }
        return [$"macwilliams n {n} size {size}", "dual " + string.Join(" ", transformed), "feasible " + Yes(feasible)];
    }
    public List<string> Process(string line)
    {
        Command command = Parse(line);
        CommandKind kind = command.Kind;
        string[] args = command.Args;
        if (Defining(kind)) return Define(kind, args);
        if (kind is CommandKind.Crc or CommandKind.Crccheck or CommandKind.Factor or CommandKind.Macwilliams or CommandKind.Bounds) return Independent(kind, args);
        if (kind == CommandKind.List)
        {
            List<string> output = [$"codes {codes.Count}"];
            foreach ((string id, Code value) in codes) output.Add($"{id} n {value.N} k {value.K} encoder {value.Encoder}");
            return output;
        }
        string name = args[0];
        if (kind == CommandKind.Delete) { codes.Remove(name); return ["deleted " + name]; }
        Code code = codes[name];
        int n = code.N, k = code.K;
        switch (kind)
        {
            case CommandKind.Show:
            {
                List<string> output = [$"code {name} n {n} k {k} encoder {code.Encoder}"];
                if (code.Polynomial is uint polynomial) output.Add($"poly g {Bits(polynomial, n - k + 1)} h {Bits(Divide((1u << n) | 1, polynomial).Quotient, k + 1)}");
                output.AddRange(code.G.Select(row => "G " + Bits(row, n)));
                output.AddRange(code.H.Select(row => "H " + Bits(row, n)));
                return output;
            }
            case CommandKind.Info:
            {
                int distance = code.Words.Where(word => word != 0).Min(Weight), t = (distance - 1) / 2;
                long gcd = Gcd(n, k);
                bool cyclic = code.G.All(row => code.Contains(((row << 1) & ((1u << n) - 1)) | (row >> (n - 1))));
                string generator = cyclic ? Bits(code.Words[1], Degree(code.Words[1]) + 1) : "no";
                return [$"info {name} n {n} k {k} rate {k / gcd}/{n / gcd} d {distance} t {t} perfect {Yes(Volume(n, t) == (1L << (n - k)))} mds {Yes(distance == n - k + 1)} cyclic {generator}"];
            }
            case CommandKind.Systematic: return Systematic(name, code);
            case CommandKind.Weights:
            {
                int[] a = Distribution(code.Words, n), b = Distribution(Span(code.H), n);
                bool orthogonal = code.G.All(x => code.G.All(y => Weight(x & y) % 2 == 0));
                return ["weights " + name + " " + WeightList(a), "dual " + name + " " + WeightList(b),
                    $"duality {name} self-orthogonal {Yes(orthogonal)} self-dual {Yes(orthogonal && n == 2 * k)} formally-self-dual {Yes(a.SequenceEqual(b))}"];
            }
            case CommandKind.Covering:
            {
                int[] counts = Distribution(code.Leaders(), n);
                int radius = Array.FindLastIndex(counts, count => count != 0);
                return [$"covering {name} radius {radius} leaders " + string.Join(" ", Enumerable.Range(0, radius + 1).Select(i => $"{i}:{counts[i]}"))];
            }
            case CommandKind.Burst: return Burst(name, code);
            case CommandKind.Trellis:
            {
                List<int> profile = [];
                for (int cut = 0; cut <= n; cut++)
                {
                    int right = n - cut;
                    int value = Basis(code.G.Select(row => row >> right), cut).Length + Basis(code.G.Select(row => row & ((1u << right) - 1)), right).Length - k;
                    profile.Add(value);
                }
                return [$"trellis {name} profile {string.Join(" ", profile)} max {profile.Max()}"];
            }
            case CommandKind.Stdarray:
            {
                if (n - k > 6 || k > 4) Fail("too large");
                uint[] leaders = code.Leaders();
                List<string> standard = [$"stdarray {name} rows {leaders.Length} columns {code.Words.Length}"];
                foreach (int syndrome in Enumerable.Range(0, leaders.Length).OrderBy(s => Weight(leaders[s])).ThenBy(s => leaders[s]))
                    standard.Add(Bits((uint)syndrome, n - k) + ": " + string.Join(" ", code.Words.Select(word => Bits(word ^ leaders[syndrome], n))));
                return standard;
            }
            case CommandKind.Equal:
            {
                Code other = codes[args[1]];
                if (n != other.N) return [$"equal {name} {args[1]} no lengths {n} {other.N}"];
                int common = k + other.K - Basis(code.G.Concat(other.G), n).Length;
                return [$"equal {name} {args[1]} {Yes(k == common && other.K == common)} intersection {common}"];
            }
            case CommandKind.Encode:
                if (args[1].Length != k) Fail("bad length");
                return [$"encode {name} message {args[1]} codeword {Bits(code.Encode(ParseBits(args[1])), n)}"];
            case CommandKind.Syndrome: case CommandKind.Decode: case CommandKind.Bounded: case CommandKind.Coset:
            {
                string text = args[kind == CommandKind.Bounded ? 2 : 1];
                if (text.Length != n) Fail("bad length");
                uint word = ParseBits(text), s = code.Syndrome(word);
                if (kind == CommandKind.Syndrome) return [$"syndrome {name} {Bits(s, n - k)} codeword {Yes(s == 0)}"];
                Decoded decoded = code.Decode(word);
                if (kind == CommandKind.Coset) return [$"coset {name} syndrome {Bits(s, n - k)} leader {Bits(decoded.Error, n)} weights {WeightList(Distribution(code.Words.Select(value => value ^ word), n))}"];
                if (kind == CommandKind.Bounded && Weight(decoded.Error) > int.Parse(args[1])) return [$"bounded {name} fail weight {Weight(decoded.Error)}"];
                return [$"{(kind == CommandKind.Bounded ? "bounded" : "decode")} {name} {code.DecodedText(decoded)}"];
            }
            case CommandKind.Erasure:
            {
                string erasedText = args[1];
                if (erasedText.Length != n) Fail("bad length");
                uint mask = 0, known = 0;
                int erased = 0;
                foreach (char digit in erasedText)
                {
                    mask = (mask << 1) | (digit != '?' ? 1u : 0u); known = (known << 1) | (digit == '1' ? 1u : 0u);
                    if (digit == '?') erased++;
                }
                uint[] candidates = code.Words.Where(value => (value & mask) == known).ToArray();
                string result = $"erasure {name} erased {erased} candidates {candidates.Length}";
                if (candidates.Length == 1) result += $" codeword {Bits(candidates[0], n)} message {Bits(code.Message(candidates[0]), k)}";
                return [result];
            }
            case CommandKind.Interleave: return Interleave(name, code, args);
            default: throw new InvalidOperationException();
        }
    }
}

static class Program
{
    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!);
        Laboratory laboratory = new();
        for (int i = 0; i < count; i++)
        {
            string line = Console.ReadLine()!;
            try { foreach (string output in laboratory.Process(line)) Console.WriteLine(output); }
            catch (CommandError error) { Console.WriteLine("error: " + error.Message); }
        }
    }
}
