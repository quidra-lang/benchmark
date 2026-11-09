import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.StringJoiner;
import java.util.TreeMap;

public class Main {
    static final int INVALID = 1, DIVBYZERO = 2, OVERFLOW = 4, UNDERFLOW = 8, INEXACT = 16;
    enum Mode { RNE, RNA, RTZ, RUP, RDN }
    enum Kind {
        ZERO("zero"), SUBNORMAL("subnormal"), NORMAL("normal"), INFINITY("infinity"), QNAN("qnan"), SNAN("snan");
        final String text;
        Kind(String text) { this.text = text; }
        @Override public String toString() { return text; }
    }
    enum Operation { ADD, SUB, MUL, DIV, SQRT, FMA }

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    record Term(boolean negative, long magnitude, int exponent) {
        Term product(Term other) {
            return new Term(negative != other.negative, magnitude * other.magnitude, exponent + other.exponent);
        }
        Term negated() { return new Term(!negative, magnitude, exponent); }
        Exact exact() { return new Exact(negative, magnitude, exponent, 1); }
        String decimal() {
            if (magnitude == 0) return "0";
            Scaled value = exact().scaled(0);
            StringBuilder out = new StringBuilder(negative ? "-" : "");
            out.append(value.numerator / value.denominator);
            long remainder = value.numerator % value.denominator;
            if (remainder != 0) out.append('.');
            while (remainder != 0) {
                remainder *= 10;
                out.append((char) ('0' + remainder / value.denominator));
                remainder %= value.denominator;
            }
            return out.toString();
        }
    }

    static Term sumTerms(Mode mode, Term... terms) {
        int exponent = 0;
        boolean any = false, sameZero = true;
        for (Term term : terms) {
            if (term.magnitude != 0) {
                if (!any || term.exponent < exponent) exponent = term.exponent;
                any = true;
                sameZero = false;
            } else if (term.negative != terms[0].negative) sameZero = false;
        }
        long sum = 0;
        for (Term term : terms) {
            if (term.magnitude == 0) continue;
            long aligned = term.magnitude << (term.exponent - exponent);
            sum += term.negative ? -aligned : aligned;
        }
        if (sum == 0) return new Term(sameZero ? terms[0].negative : mode == Mode.RDN, 0, 0);
        return new Term(sum < 0, Math.abs(sum), exponent);
    }

    record Scaled(long numerator, long denominator) {}
    record Exact(boolean negative, long numerator, int exponent, long denominator) {
        Exact {
            if (numerator == 0) {
                exponent = 0;
                denominator = 1;
            } else {
                long a = numerator, b = denominator;
                while (b != 0) { long remainder = a % b; a = b; b = remainder; }
                numerator /= a;
                denominator /= a;
                int shift = Long.numberOfTrailingZeros(numerator);
                numerator >>= shift;
                exponent += shift;
                shift = Long.numberOfTrailingZeros(denominator);
                denominator >>= shift;
                exponent -= shift;
            }
        }
        Scaled scaled(int quantum) {
            int shift = exponent - quantum;
            return shift >= 0 ? new Scaled(numerator << shift, denominator) : new Scaled(numerator, denominator << -shift);
        }
        int floorLog() {
            int power = Long.numberOfLeadingZeros(denominator) - Long.numberOfLeadingZeros(numerator);
            boolean below = power >= 0 ? numerator < (denominator << power) : (numerator << -power) < denominator;
            return exponent + power - (below ? 1 : 0);
        }
        String fraction() {
            if (numerator == 0) return "0";
            Scaled value = scaled(0);
            String sign = negative ? "-" : "";
            return sign + value.numerator + (value.denominator == 1 ? "" : "/" + value.denominator);
        }
    }

    static long integerSqrt(long value) {
        if (value == 0) return 0;
        long root = value, next = (value + 1) / 2;
        while (next < root) {
            root = next;
            next = (root + value / root) / 2;
        }
        return root;
    }

    record Quantized(long whole, boolean inexact, int half) {
        static Quantized of(Exact value, int quantum, boolean squareRoot) {
            Scaled scaled = value.scaled(squareRoot ? 2 * quantum : quantum);
            long numerator = scaled.numerator, denominator = scaled.denominator;
            if (!squareRoot) {
                long remainder = numerator % denominator;
                return new Quantized(numerator / denominator, remainder != 0, Long.compare(remainder, denominator - remainder));
            }
            long whole = integerSqrt(numerator / denominator), midpoint = 2 * whole + 1;
            return new Quantized(whole, whole * whole * denominator != numerator,
                Long.compare(4 * numerator, midpoint * midpoint * denominator));
        }
        long rounded(Mode mode, boolean negative) {
            boolean increment = switch (mode) {
                case RNE -> half > 0 || half == 0 && (whole & 1) != 0;
                case RNA -> half >= 0;
                case RTZ -> false;
                case RUP -> inexact && !negative;
                case RDN -> inexact && negative;
            };
            return whole + (increment ? 1 : 0);
        }
    }

    record Rounded(int pattern, int flags) {
        Rounded(int pattern) { this(pattern, 0); }
    }
    record Input(int pattern, Exact number) {}
    record Bounds(long minimum, long maximum) {}

    static final class Format {
        final String name;
        final int e, m, w, bias, emin, emax, sign, base, infinity, nan;
        Format(String name, int e, int m) {
            this.name = name;
            this.e = e;
            this.m = m;
            w = 1 + e + m;
            bias = (1 << (e - 1)) - 1;
            emin = 1 - bias;
            emax = bias;
            sign = 1 << (e + m);
            base = 1 << m;
            infinity = ((1 << e) - 1) << m;
            nan = infinity | base / 2;
        }
        boolean negative(int p) { return (p & sign) != 0; }
        boolean zero(int p) { return (p & (sign - 1)) == 0; }
        int signed(int p, boolean negative) { return p | (negative ? sign : 0); }
        Kind kind(int p) {
            int magnitude = p & (sign - 1), fraction = p & (base - 1);
            if (magnitude >= infinity) {
                if (fraction == 0) return Kind.INFINITY;
                return fraction >= base / 2 ? Kind.QNAN : Kind.SNAN;
            }
            if (magnitude == 0) return Kind.ZERO;
            return magnitude < base ? Kind.SUBNORMAL : Kind.NORMAL;
        }
        boolean finite(int p) { return kind(p).ordinal() <= Kind.NORMAL.ordinal(); }
        boolean isNaN(int p) { return kind(p) == Kind.QNAN || kind(p) == Kind.SNAN; }
        Term term(int p) {
            int field = (p & (sign - 1)) >> m, fraction = p & (base - 1);
            return new Term(negative(p), field == 0 ? fraction : base + fraction,
                field == 0 ? emin - m : field - bias - m);
        }
        Rounded overflow(Mode mode, boolean negative) {
            boolean toInfinity = mode == Mode.RNE || mode == Mode.RNA || mode == Mode.RUP && !negative || mode == Mode.RDN && negative;
            return new Rounded(signed(toInfinity ? infinity : infinity - 1, negative), OVERFLOW | INEXACT);
        }
        Rounded round(Exact value, Mode mode, boolean squareRoot) {
            if (value.numerator == 0) return new Rounded(signed(0, value.negative));
            int t = value.floorLog();
            if (squareRoot) t = Math.floorDiv(t, 2);
            if (t > emax) return overflow(mode, value.negative);
            int quantum = Math.max(t, emin) - m;
            Quantized divided = Quantized.of(value, quantum, squareRoot);
            long significand = divided.rounded(mode, value.negative);
            if (significand == 2L * base) { significand = base; quantum++; }
            if (quantum > emax - m) return overflow(mode, value.negative);
            int flags = divided.inexact ? INEXACT : 0;
            if (divided.inexact && t < emin) {
                boolean tiny = t < emin - 1 || Quantized.of(value, t - m, squareRoot).rounded(mode, value.negative) < 2L * base;
                if (tiny) flags |= UNDERFLOW;
            }
            int magnitude = significand < base ? (int) significand
                : (quantum + m + bias) << m | (int) (significand - base);
            return new Rounded(signed(magnitude, value.negative), flags);
        }
        Rounded roundTerm(Term term, Mode mode) { return round(term.exact(), mode, false); }
        Rounded roundSum(Mode mode, Term... terms) { return roundTerm(sumTerms(mode, terms), mode); }

        Rounded arithmetic(Operation operation, int a, int b, int c, Mode mode) {
            if (operation == Operation.SUB) { b ^= sign; operation = Operation.ADD; }
            int[] inputs = {a, b, c};
            int count = operation == Operation.SQRT ? 1 : operation == Operation.FMA ? 3 : 2;
            boolean hasNaN = false;
            int nanFlags = 0;
            for (int i = 0; i < count; i++) {
                hasNaN |= isNaN(inputs[i]);
                if (kind(inputs[i]) == Kind.SNAN) nanFlags |= INVALID;
            }
            if (hasNaN) return new Rounded(nan, nanFlags);
            boolean ai = kind(a) == Kind.INFINITY, bi = kind(b) == Kind.INFINITY;
            boolean negative = negative(a) != negative(b);
            Rounded invalid = new Rounded(nan, INVALID);
            return switch (operation) {
                case ADD -> {
                    if (ai && bi && negative) yield invalid;
                    if (ai || bi) yield new Rounded(ai ? a : b);
                    yield roundSum(mode, term(a), term(b));
                }
                case MUL -> {
                    if (ai || bi) yield zero(a) || zero(b) ? invalid : new Rounded(signed(infinity, negative));
                    yield roundTerm(term(a).product(term(b)), mode);
                }
                case DIV -> {
                    if (ai) yield bi ? invalid : new Rounded(signed(infinity, negative));
                    if (bi) yield new Rounded(signed(0, negative));
                    if (zero(b)) yield zero(a) ? invalid : new Rounded(signed(infinity, negative), DIVBYZERO);
                    if (zero(a)) yield new Rounded(signed(0, negative));
                    Term x = term(a), y = term(b);
                    yield round(new Exact(negative, x.magnitude, x.exponent - y.exponent, y.magnitude), mode, false);
                }
                case SQRT -> {
                    if (zero(a)) yield new Rounded(a);
                    if (negative(a)) yield invalid;
                    if (ai) yield new Rounded(a);
                    yield round(term(a).exact(), mode, true);
                }
                case FMA -> {
                    if (ai || bi) {
                        if (zero(a) || zero(b) || kind(c) == Kind.INFINITY && negative(c) != negative) yield invalid;
                        yield new Rounded(signed(infinity, negative));
                    }
                    if (kind(c) == Kind.INFINITY) yield new Rounded(c);
                    yield roundSum(mode, term(a).product(term(b)), term(c));
                }
                case SUB -> throw new AssertionError();
            };
        }

        Input rawOperand(String word, boolean encoding) {
            if (word.startsWith("0b") || word.startsWith("0x")) {
                boolean binary = word.startsWith("0b");
                int width = binary ? w : (w + 3) / 4;
                if (encoding || word.length() - 2 != width) throw new CommandError("ERROR BAD OPERAND " + word);
                int p = Integer.parseInt(word.substring(2), binary ? 2 : 16);
                if (p >= 2 * sign) throw new CommandError("ERROR BAD OPERAND " + word);
                return new Input(p, null);
            }
            switch (word) {
                case "nan": return new Input(nan, null);
                case "inf": return new Input(infinity, null);
                case "-inf": return new Input(infinity | sign, null);
            }
            boolean negative = word.startsWith("-");
            String digits = negative ? word.substring(1) : word;
            int slash = digits.indexOf('/'), dot = digits.indexOf('.');
            long numerator, denominator = 1;
            if (slash >= 0) {
                numerator = Long.parseLong(digits.substring(0, slash));
                denominator = Long.parseLong(digits.substring(slash + 1));
                if (denominator == 0) throw new CommandError("ERROR BAD OPERAND " + word);
            } else if (dot >= 0) {
                numerator = Long.parseLong(digits.substring(0, dot) + digits.substring(dot + 1));
                for (int i = dot + 1; i < digits.length(); i++) denominator *= 10;
            } else numerator = Long.parseLong(digits);
            return new Input(0, new Exact(negative, numerator, 0, denominator));
        }
        int operand(String word) {
            Input value = rawOperand(word, false);
            return value.number == null ? value.pattern : round(value.number, Mode.RNE, false).pattern;
        }
        String bits(int p) { return (negative(p) ? 1 : 0) + "|" + binary((p & (sign - 1)) >> m, e) + "|" + binary(p & (base - 1), m); }
        String hex(int p) { return String.format(Locale.ROOT, "0x%0" + (w + 3) / 4 + "X", p); }
        String value(int p) {
            return switch (kind(p)) {
                case QNAN, SNAN -> "nan";
                case INFINITY -> negative(p) ? "-inf" : "inf";
                case ZERO -> negative(p) ? "-0" : "0";
                default -> term(p).decimal();
            };
        }
        String pattern(int p) { return bits(p) + " " + hex(p) + " " + value(p); }
        String result(Rounded result) { return pattern(result.pattern) + " " + flagText(result.flags); }
        String difference(int p, Term exactSum) {
            return finite(p) ? sumTerms(Mode.RNE, term(p), exactSum.negated()).exact().fraction() : value(p);
        }
        long orderKey(int p) { return negative(p) ? -(long) (p - sign) - 1 : p; }
        int nextUp(int p) {
            if (p == infinity) return p;
            if (zero(p)) return 1;
            return negative(p) ? p - 1 : p + 1;
        }
    }

    static String binary(int value, int width) {
        String digits = Integer.toBinaryString(value);
        return "0".repeat(width - digits.length()) + digits;
    }
    static String flagText(int flags) {
        String[] names = {"invalid", "divbyzero", "overflow", "underflow", "inexact"};
        StringJoiner out = new StringJoiner(",");
        for (int i = 0; i < names.length; i++) if ((flags & (1 << i)) != 0) out.add(names[i]);
        return "flags=" + (out.length() == 0 ? "none" : out.toString());
    }
    static Mode parseMode(String word) {
        try { return Mode.valueOf(word); }
        catch (IllegalArgumentException error) { throw new CommandError("ERROR BAD MODE " + word); }
    }
    static Mode optionalMode(String[] words, int index) { return index == words.length ? Mode.RNE : parseMode(words[index]); }
    static Bounds integerRange(String word) {
        return switch (word) {
            case "I8" -> new Bounds(-128, 127);
            case "U8" -> new Bounds(0, 255);
            case "I16" -> new Bounds(-32768, 32767);
            case "U16" -> new Bounds(0, 65535);
            case "I32" -> new Bounds(-2147483648L, 2147483647L);
            case "U32" -> new Bounds(0, 4294967295L);
            default -> throw new CommandError("ERROR BAD TYPE " + word);
        };
    }
    static String relation(long a, long b) { return a < b ? "LT" : a == b ? "EQ" : "GT"; }
    static void line(StringBuilder out, String pattern, Object... args) { out.append(String.format(Locale.ROOT, pattern, args)).append('\n'); }

    static String summation(Format f, String[] words) {
        String command = words[0];
        Mode mode = parseMode(words[2]);
        List<Integer> values = new ArrayList<>();
        int leftCount = 0;
        for (int i = 3; i < words.length; i++) {
            if (words[i].equals("|")) leftCount = values.size();
            else values.add(f.operand(words[i]));
        }
        if (command.equals("DOT") && leftCount != values.size() - leftCount) throw new CommandError("ERROR LENGTH MISMATCH");
        for (int p : values) if (!f.finite(p)) throw new CommandError("ERROR NOT FINITE");
        StringBuilder out = new StringBuilder();
        if (command.equals("DOT")) {
            Term[] terms = new Term[leftCount];
            for (int i = 0; i < leftCount; i++) terms[i] = f.term(values.get(i)).product(f.term(values.get(leftCount + i)));
            Term exactSum = sumTerms(mode, terms);
            Rounded first = f.arithmetic(Operation.MUL, values.getFirst(), values.get(leftCount), 0, mode);
            Rounded naive = first, chained = first;
            for (int i = 1; i < leftCount; i++) {
                Rounded multiplied = f.arithmetic(Operation.MUL, values.get(i), values.get(leftCount + i), 0, mode);
                Rounded added = f.arithmetic(Operation.ADD, naive.pattern, multiplied.pattern, 0, mode);
                naive = new Rounded(added.pattern, naive.flags | multiplied.flags | added.flags);
            }
            for (int i = 1; i < leftCount; i++) {
                Rounded fused = f.arithmetic(Operation.FMA, values.get(i), values.get(leftCount + i), chained.pattern, mode);
                chained = new Rounded(fused.pattern, chained.flags | fused.flags);
            }
            line(out, "DOT %s %s n=%d", f.name, mode, leftCount);
            line(out, "NAIVE %s", f.result(naive));
            line(out, "CHAINED %s", f.result(chained));
            line(out, "EXACT %s", exactSum.decimal());
            line(out, "FUSED %s", f.result(f.roundTerm(exactSum, mode)));
            line(out, "DIFF naive=%s chained=%s", f.difference(naive.pattern, exactSum), f.difference(chained.pattern, exactSum));
            return out.toString();
        }
        Term[] terms = values.stream().map(f::term).toArray(Term[]::new);
        Term exactSum = sumTerms(mode, terms);
        Rounded result = new Rounded(values.getFirst());
        int compensation = 0;
        line(out, "%s %s %s count=%d", command, f.name, mode, values.size());
        for (int i = 1; i < values.size(); i++) {
            if (command.equals("SUM")) {
                Rounded next = f.arithmetic(Operation.ADD, result.pattern, values.get(i), 0, mode);
                result = new Rounded(next.pattern, result.flags | next.flags);
                line(out, "PARTIAL %d %s", i + 1, f.result(next));
            } else {
                Rounded y = f.arithmetic(Operation.SUB, values.get(i), compensation, 0, mode);
                Rounded t = f.arithmetic(Operation.ADD, result.pattern, y.pattern, 0, mode);
                Rounded d = f.arithmetic(Operation.SUB, t.pattern, result.pattern, 0, mode);
                Rounded c = f.arithmetic(Operation.SUB, d.pattern, y.pattern, 0, mode);
                int flags = y.flags | t.flags | d.flags | c.flags;
                result = new Rounded(t.pattern, result.flags | flags);
                compensation = c.pattern;
                line(out, "KSTEP %d sum=%s comp=%s %s", i + 1, f.value(result.pattern), f.value(compensation), flagText(flags));
            }
        }
        line(out, "RESULT %s", f.result(result));
        line(out, "EXACT %s", exactSum.decimal());
        line(out, "ROUNDED %s", f.result(f.roundTerm(exactSum, mode)));
        line(out, "DIFF %s", f.difference(result.pattern, exactSum));
        return out.toString();
    }

    static String table(Format f) {
        if (f.w > 8) throw new CommandError("ERROR TABLE TOO LARGE");
        StringBuilder out = new StringBuilder();
        line(out, "TABLE %s count=%d", f.name, f.infinity);
        for (int p = 0; p < f.infinity; p++) {
            String gap = p + 1 == f.infinity ? "-" : sumTerms(Mode.RNE, f.term(p + 1), f.term(p).negated()).decimal();
            line(out, "ENTRY %d %s gap=%s", p, f.pattern(p), gap);
        }
        line(out, "MAX %s", f.pattern(f.infinity - 1));
        line(out, "MINNORMAL %s", f.pattern(f.base));
        line(out, "MINSUBNORMAL %s", f.pattern(1));
        line(out, "EPSILON %s", new Term(false, 1, -f.m).decimal());
        line(out, "PATTERNS finite=%d infinite=2 nan=%d total=%d", 2 * f.infinity, 2 * (f.base - 1), 2 * f.sign);
        return out.toString();
    }

    static Format findFormat(Map<String, Format> formats, String name) {
        Format f = formats.get(name);
        if (f == null) throw new CommandError("ERROR UNKNOWN FORMAT " + name);
        return f;
    }

    static String execute(Map<String, Format> formats, String[] words) {
        String command = words[0];
        StringBuilder out = new StringBuilder();
        if (command.equals("FORMAT")) {
            if (formats.containsKey(words[1])) throw new CommandError("ERROR FORMAT EXISTS " + words[1]);
            int e = Integer.parseInt(words[2]), m = Integer.parseInt(words[3]);
            if (e < 2 || e > 5 || m < 1 || m > 10) throw new CommandError("ERROR BAD FORMAT");
            Format f = new Format(words[1], e, m);
            formats.put(f.name, f);
            line(out, "FORMAT %s e=%d m=%d bits=%d bias=%d emin=%d emax=%d", f.name, e, m, f.w, f.bias, f.emin, f.emax);
            return out.toString();
        }
        Format f = findFormat(formats, words[1]);
        if (command.equals("TABLE")) return table(f);
        if (command.equals("SUM") || command.equals("KAHAN") || command.equals("DOT")) return summation(f, words);
        if (command.equals("CONVERT")) {
            Format g = findFormat(formats, words[2]);
            int a = f.operand(words[3]);
            Mode mode = optionalMode(words, 4);
            Rounded result = switch (f.kind(a)) {
                case QNAN -> new Rounded(g.nan);
                case SNAN -> new Rounded(g.nan, INVALID);
                case INFINITY -> new Rounded(g.signed(g.infinity, f.negative(a)));
                case ZERO -> new Rounded(g.signed(0, f.negative(a)));
                default -> g.roundTerm(f.term(a), mode);
            };
            line(out, "CONVERT %s %s %s %s", f.name, g.name, mode, g.result(result));
            return out.toString();
        }
        if (command.equals("ENCODE")) {
            Input value = f.rawOperand(words[2], true);
            Mode mode = optionalMode(words, 3);
            Rounded result = value.number == null ? new Rounded(value.pattern) : f.round(value.number, mode, false);
            String source = value.number == null ? f.value(value.pattern) : value.number.fraction();
            line(out, "ENCODE %s %s %s %s", f.name, mode, source, f.result(result));
            return out.toString();
        }
        int a = f.operand(words[2]);
        switch (command) {
            case "DECODE" -> {
                Kind kind = f.kind(a);
                int exponent = (a & (f.sign - 1)) >> f.m, fraction = a & (f.base - 1);
                line(out, "DECODE %s %s %s %s sign=%d", f.name, f.bits(a), f.hex(a), kind, f.negative(a) ? 1 : 0);
                if (f.finite(a)) {
                    Term term = f.term(a);
                    line(out, "FIELDS exponent=%d fraction=%d unbiased=%d significand=%d.%s", exponent, fraction,
                        term.exponent + f.m, kind == Kind.NORMAL ? 1 : 0, binary(fraction, f.m));
                    line(out, "VALUE %s %s", term.exact().fraction(), f.value(a));
                } else if (kind == Kind.INFINITY) line(out, "FIELDS exponent=%d fraction=%d", exponent, fraction);
                else line(out, "FIELDS exponent=%d fraction=%d payload=%d", exponent, fraction, fraction % (f.base / 2));
            }
            case "COMPARE" -> {
                int b = f.operand(words[3]);
                long ak = f.orderKey(a), bk = f.orderKey(b);
                String numeric = f.isNaN(a) || f.isNaN(b) ? "UN" : f.zero(a) && f.zero(b) ? "EQ" : relation(ak, bk);
                int flags = f.kind(a) == Kind.SNAN || f.kind(b) == Kind.SNAN ? INVALID : 0;
                line(out, "COMPARE %s %s %s %s total=%s %s", f.name, f.hex(a), f.hex(b), numeric, relation(ak, bk), flagText(flags));
            }
            case "TOINT" -> {
                Bounds bounds = integerRange(words[3]);
                Mode mode = optionalMode(words, 4);
                boolean invalid = !f.finite(a);
                long result = 0;
                int flags = 0;
                if (!invalid) {
                    Exact value = f.term(a).exact();
                    Quantized divided = Quantized.of(value, 0, false);
                    long magnitude = divided.rounded(mode, value.negative);
                    result = value.negative ? -magnitude : magnitude;
                    invalid = result < bounds.minimum || result > bounds.maximum;
                    flags = divided.inexact ? INEXACT : 0;
                }
                if (invalid) line(out, "TOINT %s %s %s invalid flags=invalid", f.name, words[3], mode);
                else line(out, "TOINT %s %s %s %d %s", f.name, words[3], mode, result, flagText(flags));
            }
            case "NEXTUP", "NEXTDOWN", "ULP" -> {
                Rounded result;
                if (f.isNaN(a)) result = new Rounded(f.nan, f.kind(a) == Kind.SNAN ? INVALID : 0);
                else {
                    int pattern = switch (command) {
                        case "NEXTUP" -> f.nextUp(a);
                        case "NEXTDOWN" -> f.nextUp(a ^ f.sign) ^ f.sign;
                        default -> f.kind(a) == Kind.INFINITY ? f.infinity
                            : f.roundTerm(new Term(false, 1, f.term(a).exponent), Mode.RNE).pattern;
                    };
                    result = new Rounded(pattern);
                }
                line(out, "%s %s %s", command, f.name, f.result(result));
            }
            default -> {
                Operation operation = Operation.valueOf(command);
                int arity = operation == Operation.SQRT ? 1 : operation == Operation.FMA ? 3 : 2;
                int b = arity >= 2 ? f.operand(words[3]) : 0;
                int c = arity == 3 ? f.operand(words[4]) : 0;
                Mode mode = optionalMode(words, arity + 2);
                line(out, "%s %s %s %s", command, f.name, mode, f.result(f.arithmetic(operation, a, b, c, mode)));
            }
        }
        return out.toString();
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        int count = Integer.parseInt(input.readLine());
        Map<String, Format> formats = new TreeMap<>();
        formats.put("HALF", new Format("HALF", 5, 10));
        formats.put("E5M2", new Format("E5M2", 5, 2));
        formats.put("E4M3", new Format("E4M3", 4, 3));
        for (int i = 0; i < count; i++) {
            try { output.write(execute(formats, input.readLine().split(" "))); }
            catch (CommandError error) { output.write(error.getMessage() + "\n"); }
        }
        output.flush();
    }
}
