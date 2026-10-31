import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    static class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }

    record Fraction(long n, long d) implements Comparable<Fraction> {
        static final Fraction ONE = new Fraction(1, 1);
        Fraction {
            if (d < 0) { n = -n; d = -d; }
            long a = Math.abs(n), b = d;
            while (b != 0) { long remainder = a % b; a = b; b = remainder; }
            n /= a; d /= a;
        }
        Fraction(long n) { this(n, 1); }
        Fraction add(Fraction b) { return new Fraction(n*b.d + b.n*d, d*b.d); }
        Fraction sub(Fraction b) { return new Fraction(n*b.d - b.n*d, d*b.d); }
        Fraction mul(Fraction b) { return new Fraction(n*b.n, d*b.d); }
        Fraction div(Fraction b) { return new Fraction(n*b.d, d*b.n); }
        Fraction neg() { return new Fraction(-n, d); }
        Fraction abs() { return new Fraction(Math.abs(n), d); }
        Fraction power(int exponent) {
            Fraction factor = exponent < 0 ? new Fraction(d, n) : this;
            Fraction result = ONE;
            for (int i = 0; i < Math.abs(exponent); i++) result = result.mul(factor);
            return result;
        }
        public int compareTo(Fraction b) { return Long.compare(n*b.d, b.n*d); }
        public String toString() { return d == 1 ? Long.toString(n) : n + "/" + d; }
        String decimal() {
            long magnitude = Math.abs(n);
            return String.format(Locale.ROOT, "%s%d.%06d", n < 0 ? "-" : "", magnitude/d, magnitude%d*1_000_000/d);
        }
        String notation(String unit) { return this + " " + unit + " (" + decimal() + ")"; }
    }

    record Dimension(long kg, long m, long s, long a, long k, long mol, long cd) {
        static final Dimension NONE = new Dimension(0, 0, 0, 0, 0, 0, 0);
        Dimension combine(Dimension b, long sign) {
            return new Dimension(kg+sign*b.kg, m+sign*b.m, s+sign*b.s, a+sign*b.a,
                    k+sign*b.k, mol+sign*b.mol, cd+sign*b.cd);
        }
        Dimension scale(long factor) { return new Dimension(kg*factor, m*factor, s*factor, a*factor, k*factor, mol*factor, cd*factor); }
        Dimension half() { return new Dimension(kg/2, m/2, s/2, a/2, k/2, mol/2, cd/2); }
        boolean even() { return kg%2 == 0 && m%2 == 0 && s%2 == 0 && a%2 == 0 && k%2 == 0 && mol%2 == 0 && cd%2 == 0; }
        void match(Dimension b) {
            if (!equals(b)) throw new CommandError("DIMENSION MISMATCH " + this + " vs " + b);
        }
        public String toString() {
            String[] names = {"kg", "m", "s", "A", "K", "mol", "cd"};
            long[] values = {kg, m, s, a, k, mol, cd};
            List<String> terms = new ArrayList<>();
            for (int i = 0; i < values.length; i++) {
                if (values[i] != 0) terms.add(values[i] == 1 ? names[i] : names[i] + "^" + values[i]);
            }
            return terms.isEmpty() ? "1" : String.join(" ", terms);
        }
    }
    record Quantity(Fraction value, Dimension dim) {}
    record Kind(String name, Dimension dim) {}
    static final List<Kind> KINDS = List.of(
        new Kind("dimensionless", Dimension.NONE), new Kind("length", new Dimension(0,1,0,0,0,0,0)),
        new Kind("mass", new Dimension(1,0,0,0,0,0,0)), new Kind("time", new Dimension(0,0,1,0,0,0,0)),
        new Kind("current", new Dimension(0,0,0,1,0,0,0)), new Kind("temperature", new Dimension(0,0,0,0,1,0,0)),
        new Kind("amount", new Dimension(0,0,0,0,0,1,0)), new Kind("luminous_intensity", new Dimension(0,0,0,0,0,0,1)),
        new Kind("area", new Dimension(0,2,0,0,0,0,0)), new Kind("volume", new Dimension(0,3,0,0,0,0,0)),
        new Kind("speed", new Dimension(0,1,-1,0,0,0,0)), new Kind("acceleration", new Dimension(0,1,-2,0,0,0,0)),
        new Kind("density", new Dimension(1,-3,0,0,0,0,0)), new Kind("momentum", new Dimension(1,1,-1,0,0,0,0)),
        new Kind("force", new Dimension(1,1,-2,0,0,0,0)), new Kind("energy", new Dimension(1,2,-2,0,0,0,0)),
        new Kind("power", new Dimension(1,2,-3,0,0,0,0)), new Kind("pressure", new Dimension(1,-1,-2,0,0,0,0)),
        new Kind("frequency", new Dimension(0,0,-1,0,0,0,0)), new Kind("charge", new Dimension(0,0,1,1,0,0,0)),
        new Kind("voltage", new Dimension(1,2,-3,-1,0,0,0)), new Kind("resistance", new Dimension(1,2,-3,-2,0,0,0)),
        new Kind("conductance", new Dimension(-1,-2,3,2,0,0,0)), new Kind("capacitance", new Dimension(-1,-2,4,2,0,0,0)),
        new Kind("magnetic_flux", new Dimension(1,2,-2,-1,0,0,0)), new Kind("flux_density", new Dimension(1,0,-2,-1,0,0,0)),
        new Kind("inductance", new Dimension(1,2,-2,-2,0,0,0)), new Kind("illuminance", new Dimension(0,-2,0,0,0,0,1)),
        new Kind("catalytic_activity", new Dimension(0,0,-1,0,0,1,0))
    );
    static Dimension kindDimension(String name) {
        for (Kind kind : KINDS) if (kind.name.equals(name)) return kind.dim;
        return null;
    }
    static String kindName(Dimension dim) {
        for (Kind kind : KINDS) if (kind.dim.equals(dim)) return kind.name;
        return "-";
    }
    static boolean letter(char c) { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'; }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static boolean digits(String text) {
        if (text.isEmpty()) return false;
        for (int i = 0; i < text.length(); i++) if (!digit(text.charAt(i))) return false;
        return true;
    }
    static Fraction number(String text) {
        String body = text.startsWith("-") ? text.substring(1) : text;
        Fraction value;
        int dot = body.indexOf('.'), slash = body.indexOf('/');
        if (digits(body)) value = new Fraction(Long.parseLong(body));
        else if (dot >= 0) {
            String whole = body.substring(0, dot), tail = body.substring(dot+1);
            if (!digits(whole) || !digits(tail)) throw new CommandError("BAD NUMBER " + text);
            long scale = 1;
            for (int i = 0; i < tail.length(); i++) scale *= 10;
            value = new Fraction(Long.parseLong(whole)*scale + Long.parseLong(tail), scale);
        } else if (slash >= 0) {
            String n = body.substring(0, slash), d = body.substring(slash+1);
            if (!digits(n) || !digits(d) || Long.parseLong(d) == 0) throw new CommandError("BAD NUMBER " + text);
            value = new Fraction(Long.parseLong(n), Long.parseLong(d));
        } else throw new CommandError("BAD NUMBER " + text);
        return text.startsWith("-") ? value.neg() : value;
    }
    static int exponent(String text) {
        long value = Long.parseLong(text);
        if (value == 0 || value < -3 || value > 3) throw new CommandError("BAD EXPONENT " + text);
        return (int)value;
    }
    static void checkName(String name, boolean variable) {
        if (name.isEmpty() || name.length() > 12 || !name.chars().allMatch(c -> letter((char)c))
                || variable && List.of("abs", "sqrt", "min", "max").contains(name)) throw new CommandError("BAD NAME " + name);
    }
    static long integerRoot(long n) {
        if (n < 2) return n;
        long x = n, next = (n+1)/2;
        while (next < x) { x = next; next = (x+n/x)/2; }
        return x;
    }

    static final int IDENTIFIER = 256, NUMBER = 257, UNIT = 258, INVALID = 259, END = 260;
    record Token(int kind, String text, int position) {}
    sealed interface UnitNode {}
    record UnitName(String name) implements UnitNode {}
    record UnitNumber(String text) implements UnitNode {}
    record UnitPower(UnitNode child, String exponent) implements UnitNode {}
    record UnitTerm(char op, UnitNode node) {}
    record UnitProduct(List<UnitTerm> terms) implements UnitNode {}
    sealed interface Expr {}
    record Literal(String number, String unit) implements Expr {}
    record Variable(String name) implements Expr {}
    record Power(Expr child, String exponent) implements Expr {}
    record Negative(Expr child) implements Expr {}
    record Binary(char op, Expr left, Expr right) implements Expr {}
    record Call(String name, List<Expr> args) implements Expr {}

    static class Parser {
        final String source;
        final List<Token> tokens = new ArrayList<>();
        int position;
        Parser(String source, boolean quantity) {
            this.source = source;
            for (int i = 0; i < source.length();) {
                int start = i, kind;
                char c = source.charAt(i);
                if (letter(c)) {
                    kind = IDENTIFIER;
                    while (i < source.length() && letter(source.charAt(i))) i++;
                } else if (digit(c)) {
                    kind = NUMBER;
                    while (i < source.length() && digit(source.charAt(i))) i++;
                    if (quantity && i+1 < source.length() && source.charAt(i) == '.' && digit(source.charAt(i+1))) {
                        i++;
                        while (i < source.length() && digit(source.charAt(i))) i++;
                    }
                } else if (quantity && c == '[' && source.indexOf(']', i+1) > i+1) {
                    kind = UNIT; i = source.indexOf(']', i+1)+1;
                } else {
                    kind = (quantity ? "+-*/^()," : "*/^()-").indexOf(c) >= 0 ? c : INVALID;
                    i++;
                }
                tokens.add(new Token(kind, source.substring(start, i), start));
            }
            tokens.add(new Token(END, "", source.length()));
        }
        Token current() { return tokens.get(position); }
        boolean take(int kind) {
            if (current().kind != kind) return false;
            position++; return true;
        }
        CommandError syntax() {
            return new CommandError("SYNTAX " + source + " AT " + (current().kind == END ? "END" : current().position+1));
        }
        void expect(int kind) { if (!take(kind)) throw syntax(); }
        String readExponent() {
            int start = current().position;
            take('-');
            Token token = current();
            if (token.kind != NUMBER || token.text.contains(".")) throw syntax();
            position++;
            return source.substring(start, token.position+token.text.length());
        }
        UnitNode unitTerm() {
            Token token = current();
            UnitNode result;
            if (take(IDENTIFIER)) result = new UnitName(token.text);
            else if (token.kind == NUMBER && token.text.charAt(0) != '0') { position++; result = new UnitNumber(token.text); }
            else if (take('(')) { result = unitExpression(); expect(')'); }
            else throw syntax();
            return take('^') ? new UnitPower(result, readExponent()) : result;
        }
        UnitNode unitExpression() {
            List<UnitTerm> terms = new ArrayList<>();
            terms.add(new UnitTerm('*', unitTerm()));
            while (current().kind == '*' || current().kind == '/') {
                char op = (char)current().kind; position++;
                terms.add(new UnitTerm(op, unitTerm()));
            }
            return new UnitProduct(List.copyOf(terms));
        }
        UnitNode completeUnit() {
            UnitNode result = unitExpression();
            if (current().kind != END) throw syntax();
            return result;
        }
        Expr primary() {
            Token token = current();
            Expr result;
            if (take(NUMBER)) {
                String unit = null;
                if (current().kind == UNIT) {
                    String text = current().text; position++;
                    unit = text.substring(1, text.length()-1);
                }
                result = new Literal(token.text, unit);
            } else if (take(UNIT)) result = new Literal("1", token.text.substring(1, token.text.length()-1));
            else if (take(IDENTIFIER)) {
                if (take('(')) {
                    List<Expr> args = new ArrayList<>();
                    args.add(expression());
                    while (take(',')) args.add(expression());
                    expect(')'); result = new Call(token.text, List.copyOf(args));
                } else result = new Variable(token.text);
            } else if (take('(')) { result = expression(); expect(')'); }
            else throw syntax();
            return take('^') ? new Power(result, readExponent()) : result;
        }
        Expr unary() { return take('-') ? new Negative(unary()) : primary(); }
        Expr product() {
            Expr result = unary();
            while (current().kind == '*' || current().kind == '/') {
                char op = (char)current().kind; position++;
                result = new Binary(op, result, unary());
            }
            return result;
        }
        Expr expression() {
            Expr result = product();
            while (current().kind == '+' || current().kind == '-') {
                char op = (char)current().kind; position++;
                result = new Binary(op, result, product());
            }
            return result;
        }
        Expr complete() {
            Expr result = expression();
            if (current().kind != END) throw syntax();
            return result;
        }
    }

    record Reduced(Fraction coefficient, LinkedHashMap<String, Long> names) {}
    static Reduced reduce(UnitNode node) {
        return switch (node) {
            case UnitName atom -> {
                LinkedHashMap<String, Long> names = new LinkedHashMap<>();
                names.put(atom.name, 1L);
                yield new Reduced(Fraction.ONE, names);
            }
            case UnitNumber atom -> new Reduced(new Fraction(Long.parseLong(atom.text)), new LinkedHashMap<>());
            case UnitPower power -> {
                Reduced inner = reduce(power.child);
                int k = Integer.parseInt(power.exponent);
                inner.names.replaceAll((name, count) -> count*k);
                yield new Reduced(inner.coefficient.power(k), inner.names);
            }
            case UnitProduct product -> {
                Fraction coefficient = Fraction.ONE;
                LinkedHashMap<String, Long> names = new LinkedHashMap<>();
                for (UnitTerm term : product.terms) {
                    Reduced right = reduce(term.node);
                    long sign = term.op == '*' ? 1 : -1;
                    coefficient = sign == 1 ? coefficient.mul(right.coefficient) : coefficient.div(right.coefficient);
                    for (var entry : right.names.entrySet()) names.merge(entry.getKey(), sign*entry.getValue(), Long::sum);
                }
                yield new Reduced(coefficient, names);
            }
        };
    }
    static String reducedText(UnitNode tree) {
        Reduced reduced = reduce(tree);
        List<String> parts = new ArrayList<>();
        if (!reduced.coefficient.equals(Fraction.ONE)) parts.add(reduced.coefficient.toString());
        for (var entry : reduced.names.entrySet()) {
            long k = entry.getValue();
            if (k != 0) parts.add(k == 1 ? entry.getKey() : entry.getKey() + "^" + k);
        }
        return parts.isEmpty() ? "1" : String.join(" ", parts);
    }

    record Definition(Fraction value, String expression) {}
    record Unit(String symbol, Quantity quantity, boolean prefix, Definition definition) {}
    record Prefix(String symbol, Fraction factor) {}
    record ParsedUnit(UnitNode tree, Quantity quantity) {}

    static class Database {
        final List<Unit> units = new ArrayList<>();
        final TreeMap<String, Quantity> variables = new TreeMap<>();
        static final List<Prefix> PREFIXES = List.of(
            new Prefix("G", new Fraction(1_000_000_000)), new Prefix("M", new Fraction(1_000_000)),
            new Prefix("k", new Fraction(1000)), new Prefix("h", new Fraction(100)), new Prefix("da", new Fraction(10)),
            new Prefix("d", new Fraction(1,10)), new Prefix("c", new Fraction(1,100)), new Prefix("m", new Fraction(1,1000)),
            new Prefix("u", new Fraction(1,1_000_000)), new Prefix("n", new Fraction(1,1_000_000_000))
        );
        Database() {
            add("m",1,1,"length",true); add("g",1,1000,"mass",true); add("s",1,1,"time",true);
            add("A",1,1,"current",true); add("K",1,1,"temperature",true); add("mol",1,1,"amount",true);
            add("cd",1,1,"luminous_intensity",true); add("N",1,1,"force",true); add("J",1,1,"energy",true);
            add("W",1,1,"power",true); add("Pa",1,1,"pressure",true); add("Hz",1,1,"frequency",true);
            add("C",1,1,"charge",true); add("V",1,1,"voltage",true); add("ohm",1,1,"resistance",true);
            add("S",1,1,"conductance",true); add("F",1,1,"capacitance",true); add("Wb",1,1,"magnetic_flux",true);
            add("T",1,1,"flux_density",true); add("H",1,1,"inductance",true); add("lx",1,1,"illuminance",true);
            add("kat",1,1,"catalytic_activity",true); add("L",1,1000,"volume",true); add("t",1000,1,"mass",false);
            add("min",60,1,"time",false); add("h",3600,1,"time",false); add("day",86400,1,"time",false);
            add("in",127,5000,"length",false); add("ft",381,1250,"length",false); add("yd",1143,1250,"length",false);
            add("mi",201168,125,"length",false); add("nmi",1852,1,"length",false); add("ha",10000,1,"area",false);
            add("kn",463,900,"speed",false); add("bar",100000,1,"pressure",true); add("atm",101325,1,"pressure",false);
            add("Torr",20265,152,"pressure",false); add("cal",523,125,"energy",true); add("Wh",3600,1,"energy",true);
            add("Ah",3600,1,"charge",true); add("dC",1,1,"temperature",false); add("dF",5,9,"temperature",false);
        }
        void add(String symbol, long n, long d, String kind, boolean prefix) {
            units.add(new Unit(symbol, new Quantity(new Fraction(n, d), kindDimension(kind)), prefix, null));
        }
        Quantity resolve(String name) {
            for (Unit unit : units) if (unit.symbol.equals(name)) return unit.quantity;
            for (Prefix prefix : PREFIXES) {
                if (!name.startsWith(prefix.symbol)) continue;
                String symbol = name.substring(prefix.symbol.length());
                for (Unit unit : units.subList(0, 42)) {
                    if (unit.prefix && unit.symbol.equals(symbol)) return new Quantity(prefix.factor.mul(unit.quantity.value), unit.quantity.dim);
                }
            }
            return null;
        }
        void validateUnit(UnitNode node) {
            switch (node) {
                case UnitName atom -> { if (resolve(atom.name) == null) throw new CommandError("UNKNOWN UNIT " + atom.name); }
                case UnitNumber atom -> {}
                case UnitPower power -> { validateUnit(power.child); exponent(power.exponent); }
                case UnitProduct product -> { for (UnitTerm term : product.terms) validateUnit(term.node); }
            }
        }
        Quantity unitValue(UnitNode node) {
            return switch (node) {
                case UnitName atom -> resolve(atom.name);
                case UnitNumber atom -> new Quantity(new Fraction(Long.parseLong(atom.text)), Dimension.NONE);
                case UnitPower power -> {
                    Quantity inner = unitValue(power.child);
                    int k = Integer.parseInt(power.exponent);
                    yield new Quantity(inner.value.power(k), inner.dim.scale(k));
                }
                case UnitProduct product -> {
                    Quantity result = new Quantity(Fraction.ONE, Dimension.NONE);
                    for (UnitTerm term : product.terms) {
                        Quantity right = unitValue(term.node);
                        result = term.op == '*'
                            ? new Quantity(result.value.mul(right.value), result.dim.combine(right.dim, 1))
                            : new Quantity(result.value.div(right.value), result.dim.combine(right.dim, -1));
                    }
                    yield result;
                }
            };
        }
        ParsedUnit parseUnit(String text) {
            UnitNode tree = new Parser(text, false).completeUnit();
            validateUnit(tree);
            return new ParsedUnit(tree, unitValue(tree));
        }
        Quantity unit(String text) { return parseUnit(text).quantity; }
        Quantity quantity(String text) { return evaluate(new Parser(text, true).complete()); }
        Quantity evaluate(Expr expression) {
            return switch (expression) {
                case Literal literal -> {
                    if (literal.unit == null) yield new Quantity(number(literal.number), Dimension.NONE);
                    Quantity unit = unit(literal.unit);
                    yield new Quantity(number(literal.number).mul(unit.value), unit.dim);
                }
                case Variable variable -> {
                    Quantity value = variables.get(variable.name);
                    if (value == null) throw new CommandError("UNKNOWN VARIABLE " + variable.name);
                    yield value;
                }
                case Negative negative -> {
                    Quantity value = evaluate(negative.child);
                    yield new Quantity(value.value.neg(), value.dim);
                }
                case Power power -> {
                    Quantity value = evaluate(power.child);
                    int k = exponent(power.exponent);
                    if (value.value.n == 0 && k < 0) throw new CommandError("DIVISION BY ZERO");
                    yield new Quantity(value.value.power(k), value.dim.scale(k));
                }
                case Binary binary -> {
                    Quantity a = evaluate(binary.left), b = evaluate(binary.right);
                    if (binary.op == '+' || binary.op == '-') {
                        a.dim.match(b.dim);
                        yield new Quantity(binary.op == '+' ? a.value.add(b.value) : a.value.sub(b.value), a.dim);
                    }
                    if (binary.op == '/' && b.value.n == 0) throw new CommandError("DIVISION BY ZERO");
                    yield binary.op == '*' ? new Quantity(a.value.mul(b.value), a.dim.combine(b.dim, 1))
                        : new Quantity(a.value.div(b.value), a.dim.combine(b.dim, -1));
                }
                case Call call -> {
                    int arity = switch (call.name) {
                        case "abs", "sqrt" -> 1;
                        case "min", "max" -> 2;
                        default -> throw new CommandError("UNKNOWN FUNCTION " + call.name);
                    };
                    if (call.args.size() != arity) throw new CommandError("BAD ARGUMENTS " + call.name);
                    Quantity a = evaluate(call.args.getFirst());
                    if (call.name.equals("abs")) yield new Quantity(a.value.abs(), a.dim);
                    if (call.name.equals("sqrt")) {
                        if (a.value.n < 0) throw new CommandError("NEGATIVE ROOT");
                        if (!a.dim.even()) throw new CommandError("ODD DIMENSION " + a.dim);
                        long n = integerRoot(a.value.n), d = integerRoot(a.value.d);
                        if (n*n != a.value.n || d*d != a.value.d) throw new CommandError("NOT EXACT");
                        yield new Quantity(new Fraction(n, d), a.dim.half());
                    }
                    Quantity b = evaluate(call.args.get(1));
                    a.dim.match(b.dim);
                    int comparison = a.value.compareTo(b.value);
                    yield call.name.equals("min") ? (comparison <= 0 ? a : b) : (comparison >= 0 ? a : b);
                }
            };
        }
        String simplified(Dimension dim) {
            for (Unit unit : units) if (unit.quantity.value.equals(Fraction.ONE) && unit.quantity.dim.equals(dim)) return unit.symbol;
            return dim.toString();
        }
        List<Unit> selected(Dimension dim) {
            List<Unit> result = new ArrayList<>();
            for (Unit unit : units) if (unit.quantity.dim.equals(dim)) result.add(unit);
            result.sort((a, b) -> {
                int comparison = a.quantity.value.compareTo(b.quantity.value);
                return comparison == 0 ? a.symbol.compareTo(b.symbol) : comparison;
            });
            return result;
        }
        String notation(Quantity quantity) { return quantity.value.notation(simplified(quantity.dim)); }
        List<String> command(String line) {
            String[] w = line.split(" ");
            return switch (w[0]) {
                case "DEFINE" -> {
                    checkName(w[1], false);
                    Fraction value = number(w[3]);
                    Quantity unit = unit(w[4]);
                    if (kindDimension(w[1]) != null || resolve(w[1]) != null) throw new CommandError("NAME TAKEN " + w[1]);
                    if (value.n <= 0) throw new CommandError("NOT POSITIVE " + w[3]);
                    Fraction factor = value.mul(unit.value);
                    units.add(new Unit(w[1], new Quantity(factor, unit.dim), false, new Definition(value, w[4])));
                    yield List.of("DEFINE " + w[1] + " factor=" + factor + " dim=" + unit.dim + " kind=" + kindName(unit.dim));
                }
                case "UNDEF" -> {
                    int index = -1;
                    for (int i = 0; i < units.size(); i++) if (units.get(i).symbol.equals(w[1])) { index = i; break; }
                    if (index < 0) throw new CommandError("NOT DEFINED " + w[1]);
                    if (index < 42) throw new CommandError("BUILTIN UNIT " + w[1]);
                    units.remove(index);
                    yield List.of("UNDEF " + w[1]);
                }
                case "DEFS" -> {
                    List<String> output = new ArrayList<>();
                    output.add("DEFS count=" + (units.size()-42));
                    for (Unit unit : units.subList(42, units.size())) {
                        output.add("DEF " + unit.symbol + " = " + unit.definition.value + " " + unit.definition.expression
                                + " factor=" + unit.quantity.value + " dim=" + unit.quantity.dim);
                    }
                    yield output;
                }
                case "CONVERT", "INVERT" -> {
                    Fraction value = number(w[1]);
                    Quantity from = unit(w[2]), to = unit(w[4]);
                    boolean inverse = w[0].equals("INVERT");
                    if (inverse) {
                        if (from.dim.equals(Dimension.NONE) || !from.dim.combine(to.dim, 1).equals(Dimension.NONE))
                            throw new CommandError("NOT RECIPROCAL " + from.dim + " vs " + to.dim);
                        if (value.n == 0) throw new CommandError("DIVISION BY ZERO");
                    } else from.dim.match(to.dim);
                    Fraction result = value.mul(from.value);
                    if (inverse) result = Fraction.ONE.div(result);
                    result = result.div(to.value);
                    yield List.of(w[0] + " " + value + " " + w[2] + " = " + result.notation(w[4]));
                }
                case "DIM", "REDUCE", "SIMPLIFY" -> {
                    ParsedUnit parsed = parseUnit(w[1]);
                    Quantity unit = parsed.quantity;
                    String result = switch (w[0]) {
                        case "DIM" -> unit.dim + " factor=" + unit.value + " kind=" + kindName(unit.dim);
                        case "REDUCE" -> reducedText(parsed.tree);
                        default -> notation(unit);
                    };
                    yield List.of(w[0] + " " + w[1] + " = " + result);
                }
                case "ADD", "SUB", "MUL", "DIV", "COMPARE" -> {
                    Fraction a = number(w[1]);
                    Quantity first = unit(w[2]);
                    Fraction b = number(w[3]);
                    Quantity second = unit(w[4]);
                    boolean target = w.length == 7;
                    Quantity destination = target ? unit(w[6]) : first;
                    if (w[0].equals("ADD") || w[0].equals("SUB") || w[0].equals("COMPARE")) {
                        first.dim.match(second.dim);
                        if (target) first.dim.match(destination.dim);
                        Fraction left = a.mul(first.value), right = b.mul(second.value);
                        if (w[0].equals("COMPARE")) {
                            String relation = new String[]{"<", "=", ">"}[left.compareTo(right)+1];
                            String ratio = right.n == 0 ? "undefined" : left.div(right).toString();
                            yield List.of("COMPARE " + a + " " + w[2] + " " + relation + " " + b + " " + w[4] + " ratio=" + ratio);
                        }
                        boolean add = w[0].equals("ADD");
                        Fraction result = (add ? left.add(right) : left.sub(right)).div(destination.value);
                        yield List.of(w[0] + " " + a + " " + w[2] + (add ? " + " : " - ") + b + " " + w[4]
                                + " = " + result.notation(target ? w[6] : w[2]));
                    }
                    boolean multiply = w[0].equals("MUL");
                    Dimension dim = first.dim.combine(second.dim, multiply ? 1 : -1);
                    if (!multiply && b.n == 0) throw new CommandError("DIVISION BY ZERO");
                    if (target) dim.match(destination.dim);
                    Fraction raw = multiply ? a.mul(b) : a.div(b);
                    Fraction left = a.mul(first.value), right = b.mul(second.value);
                    Fraction coherent = multiply ? left.mul(right) : left.div(right);
                    String op = multiply ? "*" : "/";
                    String prefix = w[0] + " " + a + " " + w[2] + " " + op + " " + b + " " + w[4] + " = ";
                    if (target) yield List.of(prefix + coherent.div(destination.value).notation(w[6]));
                    String rightUnit = !multiply && (w[4].contains("*") || w[4].contains("/")) ? "(" + w[4] + ")" : w[4];
                    yield List.of(prefix + raw + " " + w[2] + op + rightUnit + " = " + coherent.notation(simplified(dim)));
                }
                case "TEMP" -> {
                    Fraction value = number(w[1]);
                    for (String scale : List.of(w[2], w[4])) {
                        if (!List.of("C", "F", "K", "R").contains(scale)) throw new CommandError("UNKNOWN SCALE " + scale);
                    }
                    Fraction kelvin = switch (w[2]) {
                        case "C" -> value.add(new Fraction(5463, 20));
                        case "F" -> value.add(new Fraction(45967, 100)).mul(new Fraction(5)).div(new Fraction(9));
                        case "R" -> value.mul(new Fraction(5)).div(new Fraction(9));
                        default -> value;
                    };
                    if (kelvin.n < 0) throw new CommandError("BELOW ABSOLUTE ZERO");
                    Fraction result = switch (w[4]) {
                        case "C" -> kelvin.sub(new Fraction(5463, 20));
                        case "F" -> kelvin.mul(new Fraction(9)).div(new Fraction(5)).sub(new Fraction(45967, 100));
                        case "R" -> kelvin.mul(new Fraction(9)).div(new Fraction(5));
                        default -> kelvin;
                    };
                    yield List.of("TEMP " + value + " " + w[2] + " = " + result.notation(w[4]));
                }
                case "LIST" -> {
                    Dimension dim = kindDimension(w[1]);
                    if (dim == null) dim = unit(w[1]).dim;
                    List<Unit> selected = selected(dim);
                    List<String> output = new ArrayList<>();
                    output.add("LIST " + w[1] + " dim=" + dim + " kind=" + kindName(dim) + " count=" + selected.size());
                    for (Unit unit : selected) {
                        output.add("UNIT " + unit.symbol + " factor=" + unit.quantity.value + " origin="
                                + (unit.definition == null ? "builtin" : "user") + " prefix=" + (unit.prefix ? "yes" : "no"));
                    }
                    yield output;
                }
                case "TABLE" -> {
                    Fraction value = number(w[1]);
                    Quantity from = unit(w[2]);
                    List<Unit> selected = selected(from.dim);
                    List<String> output = new ArrayList<>();
                    output.add("TABLE " + value + " " + w[2] + " dim=" + from.dim + " count=" + selected.size());
                    for (Unit unit : selected) output.add("ROW " + value.mul(from.value).div(unit.quantity.value).notation(unit.symbol));
                    yield output;
                }
                case "AUTO" -> {
                    Fraction value = number(w[1]);
                    Quantity unit = unit(w[2]);
                    Unit reference = null;
                    for (Unit candidate : units.subList(0, 42)) {
                        if (candidate.prefix && candidate.quantity.dim.equals(unit.dim)) { reference = candidate; break; }
                    }
                    if (reference == null) throw new CommandError("NO PREFIXABLE UNIT " + unit.dim);
                    Fraction scaled = value.mul(unit.value).div(reference.quantity.value), magnitude = scaled.abs();
                    int k = 0;
                    if (magnitude.n != 0) {
                        if (magnitude.compareTo(Fraction.ONE) >= 0) {
                            while (k < 9 && magnitude.compareTo(new Fraction(10).power(k+3)) >= 0) k += 3;
                        } else {
                            while (k > -9 && magnitude.compareTo(new Fraction(10).power(k)) < 0) k -= 3;
                        }
                    }
                    String prefix = new String[]{"n", "u", "m", "", "k", "M", "G"}[(k+9)/3];
                    yield List.of("AUTO " + value + " " + w[2] + " = " + scaled.div(new Fraction(10).power(k)).notation(prefix+reference.symbol));
                }
                case "SPLIT" -> {
                    Fraction value = number(w[1]);
                    Quantity unit = unit(w[2]);
                    String[] parts = w[4].split(",");
                    List<Quantity> destinations = new ArrayList<>();
                    for (String part : parts) destinations.add(unit(part));
                    if (value.n < 0) throw new CommandError("NEGATIVE VALUE");
                    for (Quantity destination : destinations) unit.dim.match(destination.dim);
                    for (int i = 1; i < destinations.size(); i++) {
                        if (destinations.get(i-1).value.compareTo(destinations.get(i).value) <= 0) throw new CommandError("UNIT ORDER");
                    }
                    Fraction remaining = value.mul(unit.value);
                    List<String> pieces = new ArrayList<>();
                    for (int i = 0; i < parts.length-1; i++) {
                        Fraction quotient = remaining.div(destinations.get(i).value);
                        long count = quotient.n/quotient.d;
                        remaining = remaining.sub(new Fraction(count).mul(destinations.get(i).value));
                        pieces.add(count + " " + parts[i]);
                    }
                    pieces.add(remaining.div(destinations.getLast().value).notation(parts[parts.length-1]));
                    yield List.of("SPLIT " + value + " " + w[2] + " = " + String.join(" ", pieces));
                }
                case "LET" -> {
                    checkName(w[1], true);
                    Quantity quantity = quantity(w[3]);
                    variables.put(w[1], quantity);
                    yield List.of("LET " + w[1] + " = " + notation(quantity));
                }
                case "EVAL" -> {
                    Quantity quantity = quantity(w[1]);
                    String result;
                    if (w.length == 4) {
                        Quantity unit = unit(w[3]);
                        quantity.dim.match(unit.dim);
                        result = quantity.value.div(unit.value).notation(w[3]);
                    } else result = notation(quantity);
                    yield List.of("EVAL " + w[1] + " = " + result);
                }
                case "VARS" -> {
                    List<String> output = new ArrayList<>();
                    output.add("VARS count=" + variables.size());
                    for (Map.Entry<String, Quantity> entry : variables.entrySet()) output.add("VAR " + entry.getKey() + " = " + notation(entry.getValue()));
                    yield output;
                }
                default -> throw new CommandError("UNKNOWN COMMAND " + w[0]);
            };
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8)));
        int count = Integer.parseInt(input.readLine());
        Database database = new Database();
        for (int i = 0; i < count; i++) {
            String line = input.readLine();
            try { for (String result : database.command(line)) output.print(result + "\n"); }
            catch (CommandError error) { output.print("ERROR " + error.getMessage() + "\n"); }
        }
        output.flush();
    }
}
