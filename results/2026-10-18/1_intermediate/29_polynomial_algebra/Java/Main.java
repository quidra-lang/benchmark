import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;
import java.util.TreeMap;

public class Main {
    static final class CommandError extends RuntimeException {
        CommandError(String message) { super("ERROR " + message); }
    }
    static long gcd(long a, long b) {
        a = Math.abs(a); b = Math.abs(b);
        while (b != 0) { long remainder = a % b; a = b; b = remainder; }
        return a;
    }
    record Fraction(long n, long d) implements Comparable<Fraction> {
        static final Fraction ZERO = new Fraction(0), ONE = new Fraction(1);
        Fraction {
            if (d < 0) { n = -n; d = -d; }
            long divisor = gcd(n, d);
            n /= divisor; d /= divisor;
        }
        Fraction(long n) { this(n, 1); }
        static Fraction parse(String text) {
            String[] parts = text.split("/");
            long n = Long.parseLong(parts[0]);
            long d = parts.length == 1 ? 1 : Long.parseLong(parts[1]);
            if (d == 0) throw new CommandError("ZERO DENOMINATOR");
            return new Fraction(n, d);
        }
        Fraction add(Fraction b) { return new Fraction(n * b.d + b.n * d, d * b.d); }
        Fraction subtract(Fraction b) { return new Fraction(n * b.d - b.n * d, d * b.d); }
        Fraction multiply(Fraction b) { return new Fraction(n * b.n, d * b.d); }
        Fraction divide(Fraction b) { return new Fraction(n * b.d, d * b.n); }
        Fraction negate() { return new Fraction(-n, d); }
        Fraction abs() { return new Fraction(Math.abs(n), d); }
        int sign() { return Long.compare(n, 0); }
        Fraction power(int exponent) {
            Fraction result = ONE;
            for (int i = 0; i < exponent; i++) result = result.multiply(this);
            return result;
        }
        @Override public int compareTo(Fraction other) { return Long.compare(n * other.d, other.n * d); }
        @Override public String toString() { return d == 1 ? Long.toString(n) : n + "/" + d; }
    }

    static final class Polynomial {
        static final Polynomial ZERO = new Polynomial(), ONE = new Polynomial(Fraction.ONE);
        private final Fraction[] coefficients;
        Polynomial(Fraction... values) {
            int length = values.length;
            while (length > 0 && values[length - 1].n == 0) length--;
            coefficients = Arrays.copyOf(values, length);
        }
        static Fraction[] zeros(int count) {
            Fraction[] values = new Fraction[count];
            Arrays.fill(values, Fraction.ZERO);
            return values;
        }
        static Polynomial linear(Fraction value, Fraction slope) { return new Polynomial(value, slope); }
        int degree() { return coefficients.length - 1; }
        boolean isZero() { return coefficients.length == 0; }
        boolean isOne() { return degree() == 0 && coefficients[0].equals(Fraction.ONE); }
        Fraction leading() { return coefficients[coefficients.length - 1]; }
        Fraction at(int i) { return i < coefficients.length ? coefficients[i] : Fraction.ZERO; }
        Polynomial add(Polynomial b) {
            Fraction[] result = zeros(Math.max(coefficients.length, b.coefficients.length));
            for (int i = 0; i < result.length; i++) result[i] = at(i).add(b.at(i));
            return new Polynomial(result);
        }
        Polynomial subtract(Polynomial b) {
            Fraction[] result = zeros(Math.max(coefficients.length, b.coefficients.length));
            for (int i = 0; i < result.length; i++) result[i] = at(i).subtract(b.at(i));
            return new Polynomial(result);
        }
        Polynomial negate() {
            Fraction[] result = zeros(coefficients.length);
            for (int i = 0; i < result.length; i++) result[i] = coefficients[i].negate();
            return new Polynomial(result);
        }
        Polynomial scale(Fraction factor) {
            Fraction[] result = zeros(coefficients.length);
            for (int i = 0; i < result.length; i++) result[i] = coefficients[i].multiply(factor);
            return new Polynomial(result);
        }
        Polynomial divideScalar(Fraction divisor) {
            Fraction[] result = zeros(coefficients.length);
            for (int i = 0; i < result.length; i++) result[i] = coefficients[i].divide(divisor);
            return new Polynomial(result);
        }
        Polynomial multiply(Polynomial b) {
            if (isZero() || b.isZero()) return ZERO;
            Fraction[] result = zeros(degree() + b.degree() + 1);
            for (int i = 0; i <= degree(); i++)
                for (int j = 0; j <= b.degree(); j++) result[i + j] = result[i + j].add(at(i).multiply(b.at(j)));
            return new Polynomial(result);
        }
        Polynomial power(int exponent) {
            if (exponent != 0 && isZero()) return ZERO;
            if (degree() == 0 && at(0).d == 1 && Math.abs(at(0).n) == 1)
                return new Polynomial(new Fraction(at(0).n < 0 && exponent % 2 == 1 ? -1 : 1));
            Polynomial result = ONE;
            for (int i = 0; i < exponent; i++) result = result.multiply(this);
            return result;
        }
        Division divide(Polynomial b) {
            Fraction[] q = zeros(Math.max(0, degree() - b.degree() + 1));
            Fraction[] r = coefficients.clone();
            int degree = degree();
            while (degree >= 0 && degree >= b.degree()) {
                Fraction factor = r[degree].divide(b.leading());
                int shift = degree - b.degree();
                q[shift] = factor;
                for (int j = 0; j <= b.degree(); j++) r[shift + j] = r[shift + j].subtract(factor.multiply(b.at(j)));
                while (degree >= 0 && r[degree].n == 0) degree--;
            }
            return new Division(new Polynomial(q), new Polynomial(r));
        }
        Polynomial quotient(Polynomial b) { return divide(b).quotient; }
        Polynomial remainder(Polynomial b) { return divide(b).remainder; }
        Polynomial monic() { return isZero() ? ZERO : divideScalar(leading()); }
        Polynomial derivative() {
            Fraction[] result = zeros(Math.max(0, degree()));
            for (int i = 1; i <= degree(); i++) result[i - 1] = new Fraction(i).multiply(at(i));
            return new Polynomial(result);
        }
        Polynomial differentiate(int n) {
            Polynomial result = this;
            for (int i = 0; i < n && !result.isZero(); i++) result = result.derivative();
            return result;
        }
        Polynomial integral() {
            Fraction[] result = zeros(coefficients.length + 1);
            for (int i = 0; i < coefficients.length; i++) result[i + 1] = coefficients[i].divide(new Fraction(i + 1));
            return new Polynomial(result);
        }
        Fraction evaluate(Fraction point) {
            Fraction result = Fraction.ZERO;
            for (int i = degree(); i >= 0; i--) result = result.multiply(point).add(at(i));
            return result;
        }
        Polynomial compose(Polynomial inner) {
            Polynomial result = ZERO;
            for (int i = degree(); i >= 0; i--) result = result.multiply(inner).add(new Polynomial(at(i)));
            return result;
        }
        Polynomial gcd(Polynomial b) {
            Polynomial a = this;
            while (!b.isZero()) { Polynomial r = a.remainder(b); a = b; b = r; }
            return a.monic();
        }
        Bezout extendedGcd(Polynomial b) {
            Polynomial r0 = this, r1 = b, s0 = ONE, s1 = ZERO, t0 = ZERO, t1 = ONE;
            while (!r1.isZero()) {
                Division division = r0.divide(r1);
                Polynomial s = s0.subtract(division.quotient.multiply(s1));
                Polynomial t = t0.subtract(division.quotient.multiply(t1));
                r0 = r1; r1 = division.remainder;
                s0 = s1; s1 = s;
                t0 = t1; t1 = t;
            }
            return r0.isZero() ? new Bezout(r0, s0, t0)
                : new Bezout(r0.monic(), s0.divideScalar(r0.leading()), t0.divideScalar(r0.leading()));
        }
        Fraction content() {
            long denominator = 1, numerator = 0;
            for (Fraction c : coefficients) {
                denominator = denominator * c.d / Main.gcd(denominator, c.d);
                numerator = Main.gcd(numerator, c.n);
            }
            return new Fraction(leading().n < 0 ? -numerator : numerator, denominator);
        }
        Polynomial primitive() { return divideScalar(content()); }
        Polynomial squareFreePart() { return degree() < 1 ? this : quotient(gcd(derivative())); }
        Polynomial withoutConstant() { return new Polynomial(Arrays.copyOfRange(coefficients, 1, coefficients.length)); }
        void checkProduct(Polynomial b) {
            if (!isZero() && !b.isZero() && degree() + b.degree() > 30) throw new CommandError("DEGREE LIMIT");
        }
        void checkPower(int exponent) {
            if (!isZero() && (long)degree() * exponent > 30) throw new CommandError("DEGREE LIMIT");
        }
        void checkComposition(Polynomial b) {
            if (degree() >= 1 && b.degree() >= 1 && degree() * b.degree() > 30) throw new CommandError("DEGREE LIMIT");
        }
        void requireNonzero() { if (isZero()) throw new CommandError("ZERO POLYNOMIAL"); }
        void requireDivisor() { if (isZero()) throw new CommandError("DIVISION BY ZERO"); }
        void requirePositiveDegree() { if (degree() == 0) throw new CommandError("DEGREE TOO LOW"); }
        String format(String variable) {
            StringBuilder text = new StringBuilder();
            for (int i = degree(); i >= 0; i--) {
                Fraction c = at(i);
                if (c.n == 0) continue;
                if (text.isEmpty()) { if (c.n < 0) text.append('-'); }
                else text.append(c.n < 0 ? " - " : " + ");
                if (i == 0 || !c.abs().equals(Fraction.ONE)) text.append(c.abs());
                if (i > 0) text.append(variable);
                if (i > 1) text.append('^').append(i);
            }
            return text.isEmpty() ? "0" : text.toString();
        }
    }
    record Division(Polynomial quotient, Polynomial remainder) {}
    record Bezout(Polynomial g, Polynomial s, Polynomial t) {}

    interface Expression { Polynomial evaluate(Map<String, Polynomial> storage); }
    record Literal(int value) implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) { return new Polynomial(new Fraction(value)); }
    }
    record Variable() implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) { return Polynomial.linear(Fraction.ZERO, Fraction.ONE); }
    }
    record Reference(String name, int order) implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) {
            Polynomial p = storage.get(name);
            if (p == null) throw new CommandError("UNKNOWN " + name);
            return p.differentiate(order);
        }
    }
    record Negative(Expression operand) implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) { return operand.evaluate(storage).negate(); }
    }
    record Binary(char operation, Expression left, Expression right) implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) {
            Polynomial a = left.evaluate(storage), b = right.evaluate(storage);
            return switch (operation) {
                case '+' -> a.add(b);
                case '-' -> a.subtract(b);
                case '*' -> { a.checkProduct(b); yield a.multiply(b); }
                default -> {
                    b.requireDivisor();
                    if (b.degree() >= 1) throw new CommandError("NONCONSTANT DIVISOR");
                    yield a.divideScalar(b.at(0));
                }
            };
        }
    }
    record Power(Expression operand, int exponent) implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) {
            Polynomial a = operand.evaluate(storage);
            a.checkPower(exponent);
            return a.power(exponent);
        }
    }
    record Call(Expression function, Expression argument) implements Expression {
        public Polynomial evaluate(Map<String, Polynomial> storage) {
            Polynomial a = function.evaluate(storage), b = argument.evaluate(storage);
            a.checkComposition(b);
            return a.compose(b);
        }
    }
    enum TokenKind { NUMBER, NAME, SYMBOL, END }
    record Token(TokenKind kind, String text, int position) {}
    static final class Parser {
        final List<Token> tokens = new ArrayList<>();
        int position;
        static boolean digit(char c) { return c >= '0' && c <= '9'; }
        static boolean upper(char c) { return c >= 'A' && c <= 'Z'; }
        Parser(String text) {
            int i = 0;
            while (i < text.length()) {
                if (text.charAt(i) == ' ') { i++; continue; }
                int start = i++;
                TokenKind kind = TokenKind.SYMBOL;
                if (digit(text.charAt(start))) {
                    kind = TokenKind.NUMBER;
                    while (i < text.length() && digit(text.charAt(i))) i++;
                } else if (upper(text.charAt(start))) {
                    kind = TokenKind.NAME;
                    while (i < text.length() && (upper(text.charAt(i)) || digit(text.charAt(i)))) i++;
                }
                tokens.add(new Token(kind, text.substring(start, i), start + 1));
            }
            tokens.add(new Token(TokenKind.END, "", text.length() + 1));
        }
        Token current() { return tokens.get(position); }
        CommandError syntax() { return new CommandError("SYNTAX AT " + (current().kind == TokenKind.END ? "END" : current().position)); }
        boolean accept(String symbol) {
            if (current().kind == TokenKind.SYMBOL && current().text.equals(symbol)) { position++; return true; }
            return false;
        }
        void expect(String symbol) { if (!accept(symbol)) throw syntax(); }
        Expression parse() {
            Expression result = expression();
            if (current().kind != TokenKind.END) throw syntax();
            return result;
        }
        Expression expression() {
            boolean negative = accept("-");
            Expression result = term();
            if (negative) result = new Negative(result);
            while (true) {
                char operation;
                if (accept("+")) operation = '+'; else if (accept("-")) operation = '-'; else break;
                result = new Binary(operation, result, term());
            }
            return result;
        }
        Expression term() {
            Expression result = factor();
            while (true) {
                char operation;
                if (accept("*")) operation = '*';
                else if (accept("/")) operation = '/';
                else if (current().kind == TokenKind.NAME || current().text.equals("x") || current().text.equals("(")) operation = '*';
                else break;
                result = new Binary(operation, result, factor());
            }
            return result;
        }
        Expression factor() {
            Expression result = primary();
            if (accept("^")) {
                if (current().kind != TokenKind.NUMBER) throw syntax();
                int n = Integer.parseInt(current().text);
                position++;
                result = new Power(result, n);
            }
            return result;
        }
        Expression primary() {
            if (current().kind == TokenKind.NUMBER) {
                int n = Integer.parseInt(current().text);
                position++;
                return new Literal(n);
            }
            if (accept("x")) return new Variable();
            if (current().kind == TokenKind.NAME) {
                String name = current().text;
                position++;
                int order = 0;
                while (accept("'")) order++;
                Expression reference = new Reference(name, order);
                if (!accept("(")) return reference;
                Expression argument = expression();
                expect(")");
                return new Call(reference, argument);
            }
            if (accept("(")) {
                Expression result = expression();
                expect(")");
                return result;
            }
            throw syntax();
        }
    }

    record Root(Fraction value, int multiplicity) {}
    record Factor(Polynomial value, int multiplicity) {}
    record RootResult(Fraction content, Polynomial remaining, List<Root> roots) {}
    static List<Long> divisors(long value) {
        List<Long> result = new ArrayList<>();
        for (long i = 1; i <= value; i++) if (value % i == 0) result.add(i);
        return result;
    }
    static RootResult rationalRoots(Polynomial a) {
        Fraction content = a.content();
        Polynomial p = a.divideScalar(content);
        int zeros = 0;
        while (p.at(0).n == 0) { p = p.withoutConstant(); zeros++; }
        List<Long> numerators = divisors(Math.abs(p.at(0).n)), denominators = divisors(p.leading().n);
        List<Fraction> candidates = new ArrayList<>();
        for (long s : numerators) for (long t : denominators) {
            if (gcd(s, t) == 1) { candidates.add(new Fraction(-s, t)); candidates.add(new Fraction(s, t)); }
        }
        candidates.sort(Comparator.naturalOrder());
        List<Root> roots = new ArrayList<>();
        for (Fraction r : candidates) {
            int multiplicity = 0;
            while (p.degree() >= 1 && p.evaluate(r).n == 0) {
                p = p.quotient(Polynomial.linear(new Fraction(-r.n), new Fraction(r.d)));
                multiplicity++;
            }
            if (multiplicity > 0) roots.add(new Root(r, multiplicity));
        }
        if (zeros > 0) roots.add(new Root(Fraction.ZERO, zeros));
        roots.sort(Comparator.comparing(Root::value));
        return new RootResult(content, p, roots);
    }
    static List<Factor> squareFreeFactors(Polynomial a) {
        List<Factor> result = new ArrayList<>();
        if (a.degree() < 1) return result;
        Polynomial w0 = a.monic(), c = w0.gcd(w0.derivative()), w = w0.quotient(c);
        for (int i = 1; w.degree() >= 1; i++) {
            Polynomial y = w.gcd(c), f = w.quotient(y);
            if (f.degree() >= 1) result.add(new Factor(f.primitive(), i));
            c = c.quotient(y); w = y;
        }
        return result;
    }
    static void appendFactor(StringBuilder text, Polynomial p, int multiplicity, boolean simpleX) {
        text.append(" * ");
        if (simpleX) text.append('x'); else text.append('(').append(p.format("x")).append(')');
        if (multiplicity > 1) text.append('^').append(multiplicity);
    }
    record Bound(int infinity, Fraction value) implements Comparable<Bound> {
        static Bound finite(Fraction value) { return new Bound(0, value); }
        static Bound parse(String text) {
            return switch (text) {
                case "-inf" -> new Bound(-1, Fraction.ZERO);
                case "inf" -> new Bound(1, Fraction.ZERO);
                default -> finite(Fraction.parse(text));
            };
        }
        @Override public int compareTo(Bound b) {
            return infinity != 0 || b.infinity != 0 ? Integer.compare(infinity, b.infinity) : value.compareTo(b.value);
        }
        @Override public String toString() { return infinity == 0 ? value.toString() : infinity < 0 ? "-inf" : "inf"; }
    }
    record Interval(Fraction low, Fraction high) {}
    static List<Polynomial> sturmSequence(Polynomial a) {
        Polynomial p = a.squareFreePart(), q = p.derivative();
        List<Polynomial> sequence = new ArrayList<>();
        sequence.add(p);
        while (!q.isZero()) {
            sequence.add(q);
            Polynomial next = p.remainder(q).negate();
            p = q; q = next;
        }
        return sequence;
    }
    static int variations(List<Polynomial> sequence, Bound point) {
        int previous = 0, count = 0;
        for (Polynomial p : sequence) {
            int sign = point.infinity == 0 ? p.evaluate(point.value).sign() : p.leading().sign();
            if (point.infinity < 0 && p.degree() % 2 == 1) sign = -sign;
            if (sign == 0) continue;
            if (previous != 0 && previous != sign) count++;
            previous = sign;
        }
        return count;
    }
    static int rootCount(List<Polynomial> sequence, Bound low, Bound high) {
        int left = variations(sequence, low), right = variations(sequence, high);
        return left - right;
    }
    static void examine(List<Polynomial> sequence, Fraction low, Fraction high, Fraction width, List<Interval> result) {
        int count = rootCount(sequence, Bound.finite(low), Bound.finite(high));
        if (count >= 2) {
            Fraction middle = low.add(high).divide(new Fraction(2));
            examine(sequence, low, middle, width, result);
            examine(sequence, middle, high, width, result);
        } else if (count == 1) {
            while (high.subtract(low).compareTo(width) > 0) {
                Fraction middle = low.add(high).divide(new Fraction(2));
                if (rootCount(sequence, Bound.finite(low), Bound.finite(middle)) >= 1) high = middle;
                else low = middle;
            }
            result.add(new Interval(low, high));
        }
    }
    static List<Interval> isolate(Polynomial a, int precision) {
        List<Polynomial> sequence = sturmSequence(a);
        Polynomial first = sequence.getFirst();
        Fraction maximum = Fraction.ZERO;
        for (int i = 0; i < first.degree(); i++) {
            Fraction ratio = first.at(i).divide(first.leading()).abs();
            if (ratio.compareTo(maximum) > 0) maximum = ratio;
        }
        Fraction beta = Fraction.ONE.add(maximum), width = new Fraction(1, 1L << precision);
        List<Interval> result = new ArrayList<>();
        examine(sequence, beta.negate(), beta, width, result);
        return result;
    }
    static Fraction resultant(Polynomial p, Polynomial q) {
        Fraction result = Fraction.ONE;
        while (q.degree() >= 1) {
            Polynomial t = p.remainder(q);
            if (t.isZero()) return Fraction.ZERO;
            result = result.multiply(q.leading().power(p.degree() - t.degree()));
            if (p.degree() * q.degree() % 2 == 1) result = result.negate();
            p = q; q = t;
        }
        return result.multiply(q.at(0).power(p.degree()));
    }
    static int descartes(Polynomial a, boolean negative) {
        int previous = 0, count = 0;
        for (int i = a.degree(); i >= 0; i--) {
            int sign = a.at(i).sign();
            if (negative && i % 2 == 1) sign = -sign;
            if (sign == 0) continue;
            if (previous != 0 && previous != sign) count++;
            previous = sign;
        }
        return count;
    }
    static Polynomial interpolate(List<Fraction> values) {
        int m = values.size() / 2;
        Fraction[] x = new Fraction[m], d = new Fraction[m];
        for (int i = 0; i < m; i++) { x[i] = values.get(2 * i); d[i] = values.get(2 * i + 1); }
        for (int j = 1; j < m; j++) for (int i = 0; i < j; i++)
            if (x[j].equals(x[i])) throw new CommandError("DUPLICATE X " + x[j]);
        for (int j = 1; j < m; j++) for (int i = m - 1; i >= j; i--)
            d[i] = d[i].subtract(d[i - 1]).divide(x[i].subtract(x[i - j]));
        Polynomial result = Polynomial.ZERO;
        for (int i = m - 1; i >= 0; i--) result = result.multiply(Polynomial.linear(x[i].negate(), Fraction.ONE)).add(new Polynomial(d[i]));
        return result;
    }
    static Polynomial special(String kind, int n) {
        if (!List.of("chebyshev", "chebyshev2", "legendre", "hermite", "laguerre").contains(kind))
            throw new CommandError("UNKNOWN KIND " + kind);
        if (n > 30) throw new CommandError("DEGREE LIMIT");
        Polynomial a = Polynomial.ONE;
        Polynomial b = switch (kind) {
            case "chebyshev2", "hermite" -> Polynomial.linear(Fraction.ZERO, new Fraction(2));
            case "laguerre" -> Polynomial.linear(Fraction.ONE, new Fraction(-1));
            default -> Polynomial.linear(Fraction.ZERO, Fraction.ONE);
        };
        if (n == 0) return a;
        for (int j = 1; j < n; j++) {
            Polynomial factor = switch (kind) {
                case "legendre" -> Polynomial.linear(Fraction.ZERO, new Fraction(2 * j + 1));
                case "laguerre" -> Polynomial.linear(new Fraction(2 * j + 1), new Fraction(-1));
                default -> Polynomial.linear(Fraction.ZERO, new Fraction(2));
            };
            int multiplier = switch (kind) { case "legendre", "laguerre" -> j; case "hermite" -> 2 * j; default -> 1; };
            Polynomial next = factor.multiply(b).subtract(a.scale(new Fraction(multiplier)));
            if (kind.equals("legendre") || kind.equals("laguerre")) next = next.scale(new Fraction(1, j + 1));
            a = b; b = next;
        }
        return b;
    }

    record Named(String name, Polynomial value) {}
    static final class Response {
        final List<Named> stores = new ArrayList<>();
        final List<String> lines = new ArrayList<>();
        String deletion;
        void save(String name, Polynomial value) {
            stores.add(new Named(name, value));
            lines.add(name + " = " + value.format("x"));
        }
    }
    static final class Calculator {
        final Map<String, Polynomial> storage = new TreeMap<>();
        Polynomial lookup(String name) {
            Polynomial p = storage.get(name);
            if (p == null) throw new CommandError("UNKNOWN " + name);
            return p;
        }
        static int[] sourcePositions(String command) {
            return switch (command) {
                case "ADD", "SUB", "MUL", "GCD", "LCM", "INVMOD", "COMPOSE" -> new int[]{2, 3};
                case "POW", "DERIV", "INTEG", "TANGENT" -> new int[]{2};
                case "MODPOW" -> new int[]{2, 4};
                case "DIV" -> new int[]{3, 4};
                case "XGCD" -> new int[]{4, 5};
                case "CRT" -> new int[]{2, 3, 4, 5};
                case "RESULTANT" -> new int[]{1, 2};
                case "LIST", "INTERP", "SPECIAL" -> new int[0];
                default -> new int[]{1};
            };
        }
        List<String> execute(String line) {
            Response response = new Response();
            if (line.startsWith("DEF ")) {
                String[] parts = line.split(" ", 3);
                Expression expression = new Parser(parts[2]).parse();
                response.save(parts[1], expression.evaluate(storage));
            } else {
                String[] w = line.split(" ");
                String command = w[0];
                if ((command.equals("DIV") && w[1].equals(w[2])) || (command.equals("XGCD") &&
                    (w[1].equals(w[2]) || w[1].equals(w[3]) || w[2].equals(w[3])))) throw new CommandError("SAME NAME");
                List<Polynomial> operands = new ArrayList<>();
                for (int i : sourcePositions(command)) operands.add(lookup(w[i]));
                int start = switch (command) { case "AREA", "TAYLOR", "EVAL", "INTERP" -> 2; case "TANGENT" -> 3; default -> w.length; };
                List<Fraction> values = new ArrayList<>();
                for (int i = start; i < w.length; i++) values.add(Fraction.parse(w[i]));
                Bound low = null, high = null;
                if (command.equals("STURM")) { low = Bound.parse(w[2]); high = Bound.parse(w[3]); }
                Polynomial a = operands.isEmpty() ? Polynomial.ZERO : operands.getFirst();
                Polynomial b = operands.size() < 2 ? Polynomial.ZERO : operands.get(1);
                switch (command) {
                    case "PRINT" -> response.lines.add(w[1] + " = " + a.format("x"));
                    case "DELETE" -> { response.deletion = w[1]; response.lines.add("deleted " + w[1]); }
                    case "LIST" -> {
                        if (storage.isEmpty()) response.lines.add("no polynomials");
                        else for (var entry : storage.entrySet()) response.lines.add(entry.getKey() + " = " + entry.getValue().format("x"));
                    }
                    case "DEGREE" -> response.lines.add("deg(" + w[1] + ") = " + (a.isZero() ? "-inf" : a.degree()));
                    case "ADD" -> response.save(w[1], a.add(b));
                    case "SUB" -> response.save(w[1], a.subtract(b));
                    case "MUL" -> { a.checkProduct(b); response.save(w[1], a.multiply(b)); }
                    case "POW" -> {
                        int exponent = Integer.parseInt(w[3]);
                        a.checkPower(exponent);
                        response.save(w[1], a.power(exponent));
                    }
                    case "DIV" -> {
                        b.requireDivisor();
                        Division d = a.divide(b);
                        response.save(w[1], d.quotient); response.save(w[2], d.remainder);
                    }
                    case "GCD" -> response.save(w[1], a.gcd(b));
                    case "XGCD" -> {
                        Bezout e = a.extendedGcd(b);
                        response.save(w[1], e.g); response.save(w[2], e.s); response.save(w[3], e.t);
                    }
                    case "LCM" -> {
                        Polynomial value = Polynomial.ZERO;
                        if (!a.isZero() && !b.isZero()) {
                            Polynomial g = a.gcd(b);
                            if (a.degree() + b.degree() - g.degree() > 30) throw new CommandError("DEGREE LIMIT");
                            value = a.quotient(g).multiply(b).monic();
                        }
                        response.save(w[1], value);
                    }
                    case "INVMOD" -> {
                        b.requireDivisor(); b.requirePositiveDegree();
                        Bezout e = a.extendedGcd(b);
                        if (!e.g.isOne()) throw new CommandError("NOT COPRIME");
                        response.save(w[1], e.s.remainder(b));
                    }
                    case "CRT" -> {
                        Polynomial a2 = operands.get(2), m2 = operands.get(3);
                        b.requireDivisor(); m2.requireDivisor();
                        if (b.degree() + m2.degree() > 30) throw new CommandError("DEGREE LIMIT");
                        Bezout e = b.extendedGcd(m2);
                        if (!e.g.isOne()) throw new CommandError("NOT COPRIME");
                        Polynomial r1 = a.remainder(b), r2 = a2.remainder(m2);
                        Polynomial u = r2.subtract(r1).multiply(e.s).remainder(m2);
                        response.save(w[1], r1.add(b.multiply(u)));
                    }
                    case "MODPOW" -> {
                        b.requireDivisor();
                        if (2 * b.degree() - 2 > 30) throw new CommandError("DEGREE LIMIT");
                        Polynomial x = Polynomial.ONE.remainder(b), y = a.remainder(b);
                        int exponent = Integer.parseInt(w[3]);
                        while (exponent != 0) {
                            if (exponent % 2 == 1) x = x.multiply(y).remainder(b);
                            exponent /= 2;
                            if (exponent != 0) y = y.multiply(y).remainder(b);
                        }
                        response.save(w[1], x);
                    }
                    case "DERIV" -> response.save(w[1], a.differentiate(Integer.parseInt(w[3])));
                    case "INTEG" -> {
                        if (!a.isZero() && a.degree() + 1 > 30) throw new CommandError("DEGREE LIMIT");
                        response.save(w[1], a.integral());
                    }
                    case "AREA" -> {
                        Polynomial integral = a.integral();
                        Fraction value = integral.evaluate(values.get(1)).subtract(integral.evaluate(values.get(0)));
                        response.lines.add("integral(" + w[1] + ", " + values.get(0) + ", " + values.get(1) + ") = " + value);
                    }
                    case "TANGENT" -> {
                        Fraction point = values.getFirst(), y = a.evaluate(point), slope = a.derivative().evaluate(point);
                        response.save(w[1], Polynomial.linear(y.subtract(slope.multiply(point)), slope));
                    }
                    case "TAYLOR" -> {
                        Fraction point = values.getFirst();
                        Polynomial shifted = a.compose(Polynomial.linear(point, Fraction.ONE));
                        String variable = point.n == 0 ? "x" : point.n > 0 ? "(x - " + point + ")" : "(x + " + point.negate() + ")";
                        response.lines.add("taylor(" + w[1] + ", " + point + ") = " + shifted.format(variable));
                    }
                    case "COMPOSE" -> { a.checkComposition(b); response.save(w[1], a.compose(b)); }
                    case "EVAL" -> {
                        for (Fraction point : values) response.lines.add(w[1] + "(" + point + ") = " + a.evaluate(point));
                    }
                    case "ROOTS", "FACTOR" -> {
                        a.requireNonzero();
                        RootResult roots = rationalRoots(a);
                        if (command.equals("ROOTS")) {
                            StringJoiner text = new StringJoiner(", ");
                            for (Root root : roots.roots) text.add(root.value + " (" + root.multiplicity + ")");
                            response.lines.add("roots(" + w[1] + ") = " + (roots.roots.isEmpty() ? "none" : text));
                        } else {
                            StringBuilder text = new StringBuilder("factor(" + w[1] + ") = " + roots.content);
                            for (Root root : roots.roots) appendFactor(text,
                                Polynomial.linear(new Fraction(-root.value.n), new Fraction(root.value.d)), root.multiplicity, root.value.n == 0);
                            if (roots.remaining.degree() >= 1) appendFactor(text, roots.remaining, 1, false);
                            response.lines.add(text.toString());
                        }
                    }
                    case "SQFREE" -> {
                        a.requireNonzero();
                        StringBuilder text = new StringBuilder("sqfree(" + w[1] + ") = " + a.content());
                        for (Factor factor : squareFreeFactors(a)) {
                            Polynomial p = factor.value;
                            appendFactor(text, p, factor.multiplicity, p.degree() == 1 && p.at(0).n == 0 && p.at(1).equals(Fraction.ONE));
                        }
                        response.lines.add(text.toString());
                    }
                    case "DESCARTES" -> {
                        a.requireNonzero();
                        response.lines.add("descartes(" + w[1] + ") = positive " + descartes(a, false) + ", negative " + descartes(a, true));
                    }
                    case "STURM" -> {
                        a.requireNonzero();
                        if (low.compareTo(high) >= 0) throw new CommandError("BAD INTERVAL");
                        List<Polynomial> sequence = sturmSequence(a);
                        response.lines.add("sturm(" + w[1] + ", " + low + ", " + high + ") = " + rootCount(sequence, low, high));
                    }
                    case "ISOLATE" -> {
                        a.requireNonzero();
                        int precision = Integer.parseInt(w[2]);
                        List<Interval> intervals = isolate(a, precision);
                        StringJoiner text = new StringJoiner(", ");
                        for (Interval interval : intervals) text.add("(" + interval.low + ", " + interval.high + "]");
                        response.lines.add("isolate(" + w[1] + ", " + precision + ") = " + (intervals.isEmpty() ? "none" : text));
                    }
                    case "RESULTANT" -> {
                        a.requireNonzero(); b.requireNonzero();
                        response.lines.add("res(" + w[1] + ", " + w[2] + ") = " + resultant(a, b));
                    }
                    case "DISCRIM", "POWERSUM" -> {
                        a.requireNonzero(); a.requirePositiveDegree();
                        int degree = a.degree();
                        if (command.equals("DISCRIM")) {
                            Fraction value = resultant(a, a.derivative()).divide(a.leading());
                            if (degree * (degree - 1) / 2 % 2 == 1) value = value.negate();
                            response.lines.add("disc(" + w[1] + ") = " + value);
                        } else {
                            int count = Integer.parseInt(w[2]);
                            Polynomial monic = a.monic();
                            Fraction[] sums = Polynomial.zeros(count + 1);
                            StringJoiner text = new StringJoiner(", ");
                            for (int j = 1; j <= count; j++) {
                                Fraction value = j <= degree ? new Fraction(j).multiply(monic.at(degree - j)) : Fraction.ZERO;
                                for (int i = 1; i <= Math.min(j - 1, degree); i++) value = value.add(monic.at(degree - i).multiply(sums[j - i]));
                                sums[j] = value.negate();
                                text.add(sums[j].toString());
                            }
                            response.lines.add("powersum(" + w[1] + ") = " + text);
                        }
                    }
                    case "INTERP" -> response.save(w[1], interpolate(values));
                    case "SPECIAL" -> response.save(w[1], special(w[2], Integer.parseInt(w[3])));
                    default -> throw new IllegalStateException("Unknown command");
                }
            }
            if (response.deletion != null) storage.remove(response.deletion);
            for (Named item : response.stores) storage.put(item.name, item.value);
            return response.lines;
        }
    }
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintWriter output = new PrintWriter(System.out);
        String first = input.readLine();
        if (first == null) return;
        int count = Integer.parseInt(first);
        Calculator calculator = new Calculator();
        for (int i = 0; i < count; i++) {
            String line = input.readLine();
            try { for (String text : calculator.execute(line)) output.print(text + "\n"); }
            catch (CommandError error) { output.print(error.getMessage() + "\n"); }
        }
        output.flush();
    }
}
