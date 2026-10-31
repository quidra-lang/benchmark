import java.io.*;
import java.util.*;
import java.util.regex.*;
import java.util.stream.*;

public class Main {
    record Rational(long p, long q) implements Comparable<Rational> {
        Rational {
            if (q == 0) throw new IllegalArgumentException("division by zero");
            if (q<0) {
                p = -p;
                q = -q;
            }
            long a = Math.abs(p), b = q;
            while (b != 0) {
                long t = a%b;
                a = b;
                b = t;
            }
            p /= a;
            q /= a;
        }
        Rational(long p) {
            this(p, 1);
        }
        Rational add(Rational b) {
            return new Rational(p*b.q+b.p*q, q*b.q);
        }
        Rational multiply(Rational b) {
            return new Rational(p*b.p, q*b.q);
        }
        Rational negate() {
            return new Rational(-p, q);
        }
        public int compareTo(Rational b) {
            return Long.compare(p*b.q, b.p*q);
        }
    }
    record Expr(int kind, Rational q, String name, List<Expr> args) {
    }
    record Parts(Rational coefficient, List<Expr> factors) {
    }
    record Syntax(String op, Expr value, List<Syntax> args) {
    }
    static Expr num(long p) {
        return number(new Rational(p));
    }
    static Expr num(long p, long q) {
        return number(new Rational(p, q));
    }
    static Expr number(Rational q) {
        return new Expr(5, q, "", List.of());
    }
    static Expr node(int kind, List<Expr>a) {
        return node(kind, a, "");
    }
    static Expr node(int kind, List<Expr>a, String name) {
        return new Expr(kind, new Rational(0), name, List.copyOf(a));
    }
    static final Expr ZERO = num(0), ONE = num(1), MINUS = num(-1), HALF = num(1, 2);
    static final Set<String> FUNCTIONS = Set.of("sin", "cos", "tan", "exp", "ln", "sqrt");
    static int compare(Expr a, Expr b) {
        if (a.kind != b.kind) return Integer.compare(a.kind, b.kind);
        if (a.kind == 5) return a.q.compareTo(b.q);
        int c = a.name.compareTo(b.name);
        if (c != 0) return c;
        for (int i = 0; i<Math.min(a.args.size(), b.args.size()); i++) {
            c = compare(a.args.get(i), b.args.get(i));
            if (c != 0) return c;
        }
        return Integer.compare(a.args.size(), b.args.size());
    }
    static boolean integer(Expr f) {
        return f.kind == 5 && f.q.q == 1;
    }
    static boolean negative(Expr f) {
        return f.kind == 3 && f.args.get(1).kind == 5 && f.args.get(1).q.p<0;
    }
    static Expr base(Expr f) {
        return f.kind == 3?f.args.get(0):f;
    }
    static Expr exponent(Expr f) {
        return f.kind == 3?f.args.get(1):ONE;
    }
    static Parts coefficient(Expr f) {
        if (f.kind == 5) return new Parts(f.q, List.of());
        if (f.kind == 2) return f.args.get(0).kind == 5?new Parts(f.args.get(0).q, f.args.subList(1, f.args.size())):new Parts(new Rational(1), f.args);
        return new Parts(new Rational(1), List.of(f));
    }
    static Expr product(Rational c, List<Expr>a) {
        if (a.isEmpty()) return number(c);
        List<Expr>r = new ArrayList<>();
        if (!c.equals(new Rational(1))) r.add(number(c));
        r.addAll(a);
        return r.size() == 1?r.get(0):node(2, r);
    }
    static int exponentCompare(Expr a, Expr b) {
        if (a.kind == 5 && b.kind != 5) return -1;
        if (a.kind != 5 && b.kind == 5) return 1;
        return compare(a, b);
    }
    static int termCompare(Expr a, Expr b) {
        Map<Expr, Expr>x = new HashMap<>(), y = new HashMap<>();
        for (Expr f:coefficient(a).factors) x.put(base(f), exponent(f));
        for (Expr f:coefficient(b).factors) y.put(base(f), exponent(f));
        Set<Expr>bases = new TreeSet<>(Main::compare);
        bases.addAll(x.keySet());
        bases.addAll(y.keySet());
        for (Expr f:bases) {
            int c = exponentCompare(y.getOrDefault(f, ZERO), x.getOrDefault(f, ZERO));
            if (c != 0) return c;
        }
        return 0;
    }
    static Expr add(Expr...a) {
        return add(List.of(a));
    }
    static Expr add(List<Expr>operands) {
        List<Expr>terms = new ArrayList<>();
        for (Expr f:operands) {
            if (f.kind == 1) terms.addAll(f.args);
            else if (f.kind == 2 && f.args.size() == 2 && f.args.get(0).kind == 5 && f.args.get(1).kind == 1) {
                for (Expr t:f.args.get(1).args) terms.add(mul(f.args.get(0), t));
            } else terms.add(f);
        }
        Map<List<Expr>, Rational>groups = new LinkedHashMap<>();
        for (Expr f:terms) {
            Parts p = coefficient(f);
            groups.merge(p.factors, p.coefficient, Rational::add);
        }
        List<Expr>built = new ArrayList<>();
        groups.forEach((m, c) -> {
            if (c.p != 0) built.add(product(c, m));
        });
        built.sort(Main::termCompare);
        return built.isEmpty()?ZERO:built.size() == 1?built.get(0):node(1, built);
    }
    static Expr mul(Expr...a) {
        return mul(List.of(a));
    }
    static Expr mul(List<Expr>operands) {
        Rational c = new Rational(1);
        Map<Expr, List<Expr>>groups = new LinkedHashMap<>();
        List<Expr>factors = new ArrayList<>();
        for (Expr f:operands) factors.addAll(f.kind == 2?f.args:List.of(f));
        for (Expr f:factors) if (f.kind == 5) c = c.multiply(f.q);
        else groups.computeIfAbsent(base(f), b -> new ArrayList<>()).add(f);
        if (c.p == 0) return ZERO;
        List<Expr>results = new ArrayList<>();
        groups.forEach((b, g) -> results.add(g.size() == 1?g.get(0):power(b, add(g.stream().map(Main::exponent).toList()))));
        Set<Expr>bases = new HashSet<>();
        boolean regroup = false;
        for (Expr f:results) {
            if (f.kind == 2 || f.kind == 5 || !bases.add(base(f))) regroup = true;
        }
        if (regroup) {
            results.add(0, number(c));
            return mul(results);
        }
        results.sort((a, b) -> compare(base(a), base(b)));
        return product(c, results);
    }
    static Long root(long v, long d) {
        if (v == 1) return 1L;
        if (d>20) return null;
        long r = Math.round(Math.pow(v, 1.0/d));
        for (long s = Math.max(0, r-1); s <= r+1; s++) {
            long a = 1;
            for (long i = 0; i<d && a <= v; i++) a *= s;
            if (a == v) return s;
        }
        return null;
    }
    static Expr rationalPower(Rational b, long n) {
        if (n<0) {
            b = new Rational(b.q, b.p);
            n = -n;
        }
        Rational r = new Rational(1);
        while (n>0) {
            if (n%2 != 0) r = r.multiply(b);
            n /= 2;
            if (n>0) b = b.multiply(b);
        }
        return number(r);
    }
    static Expr power(Expr b, Expr x) {
        if (x.equals(ZERO)) return ONE;
        if (x.equals(ONE)) return b;
        if (b.kind == 5) {
            if (b.equals(ONE)) return ONE;
            if (x.kind != 5) return node(3, List.of(b, x));
            if (b.q.p == 0) {
                if (x.q.p>0) return ZERO;
                throw new IllegalArgumentException("division by zero");
            }
            if (integer(x)) return rationalPower(b.q, x.q.p);
            if (b.q.p>0) {
                Long s = root(b.q.p, x.q.q), t = root(b.q.q, x.q.q);
                if (s != null && t != null) return rationalPower(new Rational(s, t), x.q.p);
            }
        }
        else if (integer(x)) {
            if (b.kind == 3) return power(b.args.get(0), mul(b.args.get(1), x));
            if (b.kind == 2) return mul(b.args.stream().map(f -> power(f, x)).toList());
        }
        return node(3, List.of(b, x));
    }
    static Expr fn(String s, Expr a) {
        if (s.equals("sqrt")) return power(a, HALF);
        if (a.equals(ZERO) && Set.of("sin", "tan").contains(s)) return ZERO;
        if (a.equals(ZERO) && Set.of("cos", "exp").contains(s)) return ONE;
        if (a.equals(ONE) && s.equals("ln")) return ZERO;
        if (Set.of("sin", "cos", "tan").contains(s) && coefficient(a).coefficient.p<0) {
            Expr r = fn(s, mul(MINUS, a));
            return s.equals("cos")?r:mul(MINUS, r);
        }
        if (a.kind == 4 && ((s.equals("exp") && a.name.equals("ln")) || (s.equals("ln") && a.name.equals("exp")))) return a.args.get(0);
        return node(4, List.of(a), s);
    }
    static SortedSet<String>variables(Expr f) {
        SortedSet<String>r = new TreeSet<>();
        if (f.kind == 0) r.add(f.name);
        for (Expr a:f.args) r.addAll(variables(a));
        return r;
    }
    static Expr derivative(Expr f, String v) {
        if (f.kind == 5) return ZERO;
        if (f.kind == 0) return f.name.equals(v)?ONE:ZERO;
        if (f.kind == 1) return add(f.args.stream().map(t -> derivative(t, v)).toList());
        if (f.kind == 2) {
            List<Expr>r = new ArrayList<>();
            for (int i = 0; i<f.args.size(); i++) {
                List<Expr>a = new ArrayList<>(f.args);
                a.set(i, derivative(a.get(i), v));
                r.add(mul(a));
            }
            return add(r);
        }
        if (f.kind == 3) {
            Expr b = f.args.get(0), x = f.args.get(1);
            if (!variables(x).contains(v)) return mul(x, power(b, add(x, MINUS)), derivative(b, v));
            if (!variables(b).contains(v)) return mul(f, fn("ln", b), derivative(x, v));
            return mul(f, add(mul(derivative(x, v), fn("ln", b)), mul(x, derivative(b, v), power(b, MINUS))));
        }
        Expr a = f.args.get(0), h = switch (f.name) {
            case "sin" -> fn("cos", a);
            case "cos" -> mul(MINUS, fn("sin", a));
            case "tan" -> power(fn("cos", a), num(-2));
            case "exp" -> f;
            default -> power(a, MINUS);
        };
        return mul(h, derivative(a, v));
    }
    static Expr rebuild(Expr f, List<Expr>a) {
        return switch (f.kind) {
            case 1 -> add(a);
            case 2 -> mul(a);
            case 3 -> power(a.get(0), a.get(1));
            default -> fn(f.name, a.get(0));
        };
    }
    static Expr substitute(Expr f, Map<String, Expr>m) {
        if (f.kind == 0) return m.getOrDefault(f.name, f);
        if (f.kind == 5) return f;
        return rebuild(f, f.args.stream().map(t -> substitute(t, m)).toList());
    }
    static List<Expr>terms(Expr f) {
        return f.kind == 1?f.args:List.of(f);
    }
    static Expr distribute(Expr a, Expr b) {
        List<Expr>r = new ArrayList<>();
        for (Expr x:terms(a)) for (Expr y:terms(b)) r.add(mul(x, y));
        return add(r);
    }
    static Expr expand(Expr f) {
        if (f.kind == 0 || f.kind == 5) return f;
        List<Expr>a = f.args.stream().map(Main::expand).toList();
        if (f.kind == 2) {
            Expr r = a.get(0);
            for (int i = 1; i<a.size(); i++) r = distribute(r, a.get(i));
            return r;
        }
        if (f.kind == 3 && a.get(0).kind == 1 && integer(a.get(1)) && a.get(1).q.p>0) {
            Expr r = a.get(0);
            for (long i = 1; i<a.get(1).q.p; i++) r = distribute(r, a.get(0));
            return r;
        }
        return rebuild(f, a);
    }
    static double numeric(Expr f) {
        if (f.kind == 5) return (double) f.q.p/f.q.q;
        if (f.kind == 1 || f.kind == 2) {
            double r = f.kind == 1?0:1;
            for (Expr t:f.args) {
                double x = numeric(t);
                if (f.kind == 1) r += x;
                else r *= x;
            }
            return r;
        }
        if (f.kind == 3) {
            double u = numeric(f.args.get(0)), z = numeric(f.args.get(1));
            boolean integral = f.args.get(1).kind == 5?integer(f.args.get(1)):z == Math.rint(z);
            if (u<0 && !integral) throw new IllegalArgumentException("domain error");
            return f.args.get(1).equals(HALF)?Math.sqrt(u):Math.pow(u, z);
        }
        double a = numeric(f.args.get(0));
        if (f.name.equals("ln") && a <= 0) throw new IllegalArgumentException("domain error");
        return switch (f.name) {
            case "sin" -> Math.sin(a);
            case "cos" -> Math.cos(a);
            case "tan" -> Math.tan(a);
            case "exp" -> Math.exp(a);
            default -> Math.log(a);
        };
    }
    static boolean atomic(Expr f) {
        return f.kind == 0 || f.kind == 4 || (integer(f) && f.q.p >= 0) || (f.kind == 3 && f.args.get(1).equals(HALF));
    }
    static String atom(Expr f) {
        return atomic(f)?show(f):"("+show(f)+")";
    }
    static String showPower(Expr b, Expr x) {
        return x.equals(HALF)?"sqrt("+show(b)+")":atom(b)+"^"+atom(x);
    }
    static String factor(Expr f) {
        return f.kind == 1?"("+show(f)+")":f.kind == 3?showPower(f.args.get(0), f.args.get(1)):show(f);
    }
    static String quotient(Rational c, List<Expr>a) {
        List<String>top = new ArrayList<>(), bottom = new ArrayList<>();
        if (Math.abs(c.p) != 1) top.add(Long.toString(Math.abs(c.p)));
        if (c.q != 1) bottom.add(Long.toString(c.q));
        for (Expr f:a) if (negative(f)) {
            Expr r = number(f.args.get(1).q.negate());
            bottom.add(r.equals(ONE)?factor(f.args.get(0)):showPower(f.args.get(0), r));
        } else top.add(factor(f));
        String s = top.isEmpty()?"1":String.join("*", top);
        if (bottom.size() == 1) s += "/"+bottom.get(0);
        else if (!bottom.isEmpty()) s += "/("+String.join("*", bottom)+")";
        return(c.p<0?"-":"")+s;
    }
    static String show(Expr f) {
        if (f.kind == 5) return f.q.p+(f.q.q == 1?"":"/"+f.q.q);
        if (f.kind == 0) return f.name;
        if (f.kind == 4) return f.name+"("+show(f.args.get(0))+")";
        if (f.kind == 3) return negative(f)?quotient(new Rational(1), List.of(f)):showPower(f.args.get(0), f.args.get(1));
        if (f.kind == 2) {
            Parts p = coefficient(f);
            return quotient(p.coefficient, p.factors);
        }
        String s = show(f.args.get(0));
        for (int i = 1; i<f.args.size(); i++) {
            String t = show(f.args.get(i));
            s += t.startsWith("-")?" - "+t.substring(1):" + "+t;
        }
        return s;
    }
    static final class Parser {
        final List<String>tokens = new ArrayList<>();
        final Map<String, Expr>names;
        int position;
        Parser(String text, Map<String, Expr>names) {
            this.names = names;
            Matcher m = Pattern.compile("[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|.").matcher(text);
            while (m.find()) {
                String t = m.group();
                if (t.startsWith(" ")) continue;
                if (!t.matches("[a-zA-Z0-9+*/^()-]+")) throw new IllegalArgumentException("invalid character '"+t+"'");
                tokens.add(t);
            }
        }
        String peek() {
            return position<tokens.size()?tokens.get(position):"";
        }
        void unexpected() {
            throw new IllegalArgumentException(position == tokens.size()?"unexpected end of expression":"unexpected '"+peek()+"'");
        }
        boolean accept(String s) {
            if (!peek().equals(s)) return false;
            position++;
            return true;
        }
        void expect(String s) {
            if (!accept(s)) unexpected();
        }
        Syntax atomTree() {
            String t = peek();
            if (t.isEmpty()) unexpected();
            if (accept("(")) {
                Syntax a = expression();
                expect(")");
                return a;
            }
            if (!Character.isLetterOrDigit(t.charAt(0))) unexpected();
            position++;
            if (Character.isDigit(t.charAt(0))) return new Syntax("", num(Long.parseLong(t)), List.of());
            if (Character.isUpperCase(t.charAt(0))) {
                if (!names.containsKey(t)) throw new IllegalArgumentException("undefined name '"+t+"'");
                return new Syntax("", names.get(t), List.of());
            }
            if (!FUNCTIONS.contains(t)) return new Syntax("", node(0, List.of(), t), List.of());
            expect("(");
            Syntax a = expression();
            expect(")");
            return new Syntax(t, null, List.of(a));
        }
        Syntax unary() {
            if (accept("-")) return new Syntax("neg", null, List.of(unary()));
            Syntax a = atomTree();
            return accept("^")?new Syntax("^", null, List.of(a, unary())):a;
        }
        Syntax term() {
            Syntax a = unary();
            while (peek().equals("*") || peek().equals("/")) {
                String op = tokens.get(position++);
                a = new Syntax(op, null, List.of(a, unary()));
            }
            return a;
        }
        Syntax expression() {
            Syntax a = term();
            while (peek().equals("+") || peek().equals("-")) {
                String op = tokens.get(position++);
                a = new Syntax(op, null, List.of(a, term()));
            }
            return a;
        }
        Expr evaluate(Syntax t) {
            if (t.value != null) return t.value;
            List<Expr>a = t.args.stream().map(this::evaluate).toList();
            return switch (t.op) {
                case "+" -> add(a);
                case "-" -> add(a.get(0), mul(MINUS, a.get(1)));
                case "*" -> mul(a);
                case "/" -> mul(a.get(0), power(a.get(1), MINUS));
                case "^" -> power(a.get(0), a.get(1));
                case "neg" -> mul(MINUS, a.get(0));
                default -> fn(t.op, a.get(0));
            };
        }
        Expr parse() {
            Syntax t = expression();
            if (position<tokens.size()) unexpected();
            return evaluate(t);
        }
    }
    static boolean variable(String s) {
        return s.matches("[a-z][a-z0-9]*") && !FUNCTIONS.contains(s);
    }
    static boolean rationalLiteral(String s) {
        return s.matches("-?[0-9]+(?:/[0-9]+)?");
    }
    static Expr literal(String s) {
        if (!rationalLiteral(s)) throw new IllegalArgumentException("invalid number '"+s+"'");
        String[]a = s.split("/");
        return num(Long.parseLong(a[0]), a.length == 1?1:Long.parseLong(a[1]));
    }
    static final Map<String, String>SIGNATURES = Map.ofEntries(Map.entry("SIMPLIFY", "e"), Map.entry("EXPAND", "e"), Map.entry("DIFF", "ev"), Map.entry("DIFFN", "evn"), Map.entry("GRAD", "e"), Map.entry("HESSIAN", "e"), Map.entry("IMPLICIT", "evv"), Map.entry("SUBST", "eve"), Map.entry("EVAL", "ea"), Map.entry("TANGENT", "evc"), Map.entry("LIMIT", "evc"), Map.entry("TAYLOR", "evcn"));
    static List<String>command(String line, Map<String, Expr>names) {
        int p = line.indexOf(' ');
        String c = p<0?line:line.substring(0, p), arg = p<0?"":line.substring(p+1);
        if (c.equals("LET")) {
            int i = arg.indexOf('=');
            if (i<0) throw new IllegalArgumentException("wrong number of arguments");
            String s = arg.substring(0, i).trim();
            if (!s.matches("[A-Z][A-Z0-9]*")) throw new IllegalArgumentException("invalid name '"+s+"'");
            Expr f = new Parser(arg.substring(i+1).trim(), names).parse();
            names.put(s, f);
            return List.of(s+" = "+show(f));
        }
        String sig = SIGNATURES.get(c);
        if (sig == null) throw new IllegalArgumentException("unknown command "+c);
        String[]fields = p<0?new String[0]:Arrays.stream(arg.split(";", -1)).map(String::trim).toArray(String[]::new);
        if (c.equals("EVAL")?(fields.length != 1 && fields.length != 2):fields.length != sig.length()) throw new IllegalArgumentException("wrong number of arguments");
        Expr[]forms = new Expr[fields.length];
        Arrays.fill(forms, ZERO);
        int n = 0;
        for (int i = 0; i<fields.length; i++) {
            String s = fields[i];
            switch (sig.charAt(i)) {
                case 'e' -> forms[i] = new Parser(s, names).parse();
                case 'v' -> {
                    if (!variable(s)) throw new IllegalArgumentException("invalid variable '"+s+"'");
                }
                case 'n' -> {
                    if (!s.matches("[1-8]")) throw new IllegalArgumentException("invalid order '"+s+"'");
                    n = Integer.parseInt(s);
                }
                case 'c' -> forms[i] = literal(s);
            }
        }
        Expr f = forms[0];
        String v = fields.length>1?fields[1]:"";
        List<String>out = new ArrayList<>();
        if (c.equals("SIMPLIFY")) return List.of("simplified: "+show(f));
        if (c.equals("EXPAND")) return List.of("expanded: "+show(expand(f)));
        if (c.equals("DIFF")) return List.of("d/d"+v+" = "+show(derivative(f, v)));
        if (c.equals("DIFFN")) {
            for (int k = 1; k <= n; k++) {
                f = derivative(f, v);
                out.add("d^"+k+"/d"+v+"^"+k+" = "+show(f));
            }
            return out;
        }
        if (c.equals("GRAD") || c.equals("HESSIAN")) {
            List<String>vs = new ArrayList<>(variables(f));
            if (vs.isEmpty()) return List.of("no variables");
            for (int i = 0; i<vs.size(); i++) {
                Expr d = derivative(f, vs.get(i));
                if (c.equals("GRAD")) out.add("d/d"+vs.get(i)+" = "+show(d));
                else for (int j = i; j<vs.size(); j++) out.add("d2/d"+vs.get(i)+"d"+vs.get(j)+" = "+show(derivative(d, vs.get(j))));
            }
            return out;
        }
        if (c.equals("IMPLICIT")) {
            String w = fields[2];
            if (v.equals(w)) throw new IllegalArgumentException("same variable");
            return List.of("d"+w+"/d"+v+" = "+show(mul(MINUS, derivative(f, v), power(derivative(f, w), MINUS))));
        }
        if (c.equals("SUBST")) return List.of("substituted: "+show(substitute(f, Map.of(v, forms[2]))));
        if (c.equals("EVAL")) {
            Map<String, Expr>values = new HashMap<>();
            for (String word:v.split(" ")) {
                if (word.isEmpty()) continue;
                int i = word.indexOf('=');
                String s = i<0?word:word.substring(0, i), t = i<0?"":word.substring(i+1);
                if (i<0 || !variable(s) || !rationalLiteral(t)) throw new IllegalArgumentException("invalid assignment '"+word+"'");
                Expr q = literal(t);
                if (values.containsKey(s)) throw new IllegalArgumentException("duplicate variable "+s);
                values.put(s, q);
            }
            for (String s:variables(f)) if (!values.containsKey(s)) throw new IllegalArgumentException("no value for "+s);
            Expr r = substitute(f, values);
            return List.of(r.kind == 5?"exact: "+show(r):String.format(Locale.ROOT, "approx: %.6f", numeric(r)));
        }
        Expr x = forms[2];
        Map<String, Expr>point = Map.of(v, x);
        if (c.equals("TANGENT")) {
            Expr m = substitute(derivative(f, v), point), y = substitute(f, point), z = node(0, List.of(), v);
            String t = "tangent: y = "+show(add(mul(m, z), y, mul(number(x.q.negate()), m)));
            if (m.equals(ZERO)) return List.of(t, "normal: "+v+" = "+show(x));
            Expr k = power(m, MINUS);
            return List.of(t, "normal: y = "+show(add(mul(MINUS, k, z), y, mul(x, k))));
        }
        if (c.equals("LIMIT")) {
            List<Expr>top = new ArrayList<>(), bottom = new ArrayList<>();
            for (Expr t:f.kind == 2?f.args:List.of(f)) if (negative(t)) bottom.add(power(t.args.get(0), number(t.args.get(1).q.negate())));
            else top.add(t);
            Expr g = mul(top), h = mul(bottom);
            for (int i = 0; i <= 5; i++) {
                Expr u = substitute(g, point), b = substitute(h, point);
                if (!b.equals(ZERO)) return List.of("limit: "+show(mul(u, power(b, MINUS))));
                if (!u.equals(ZERO)) return List.of("limit: unbounded");
                if (i<5) {
                    g = derivative(g, v);
                    h = derivative(h, v);
                }
            }
            return List.of("limit: unknown");
        }
        List<Expr>ds = new ArrayList<>(List.of(f)), ps = new ArrayList<>();
        for (int i = 0; i<n; i++) ds.add(derivative(ds.getLast(), v));
        long fac = 1;
        for (int i = 0; i <= n; i++) {
            if (i>0) fac *= i;
            Expr co = mul(substitute(ds.get(i), point), num(1, fac));
            ps.add(mul(co, power(add(node(0, List.of(), v), number(x.q.negate())), num(i))));
        }
        return List.of("taylor: "+show(expand(add(ps))));
    }
    public static void main(String[]args) throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(in.readLine());
        Map<String, Expr>names = new HashMap<>();
        while (n-->0) {
            try {
                for (String s:command(in.readLine(), names)) System.out.println(s);
            } catch (IllegalArgumentException e) {
                System.out.println("error: "+e.getMessage());
            }
        }
    }
}
