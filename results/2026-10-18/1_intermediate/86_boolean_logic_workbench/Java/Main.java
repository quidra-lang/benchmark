import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.BitSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String reason) {
            super(reason);
        }
    }

    static void fail(String reason) {
        throw new Problem("error: " + reason);
    }

    static boolean lower(char c) {
        return c >= 'a' && c <= 'z';
    }

    static boolean upper(char c) {
        return c >= 'A' && c <= 'Z';
    }

    static boolean digit(char c) {
        return c >= '0' && c <= '9';
    }

    static boolean name(String s) {
        if (s.isEmpty() || s.length() > 8 || !lower(s.charAt(0))) return false;
        for (char c : s.toCharArray()) if (!lower(c) && !digit(c)) return false;
        return true;
    }

    record Shape(String op, int left, int right) { }

    static class Node {
        final String op;
        final Node left, right;
        final int id, variables;
        Node(String op, Node left, Node right, int id) {
            this.op = op;
            this.left = left;
            this.right = right;
            this.id = id;
            variables = op.length() == 1 && upper(op.charAt(0)) ? 1 << (op.charAt(0) - 'A') : (left == null ? 0 : left.variables) | (right == null ? 0 : right.variables);
        }
        boolean binary() {
            return right != null;
        }
    }
    final Map<Shape, Node> nodes = new HashMap<>();
    final TreeMap<String, Node> definitions = new TreeMap<>();
    final Map<Integer, String> printed = new HashMap<>();
    final Map<Long, Node> normalForms = new HashMap<>();

    Node node(String op, Node left, Node right) {
        Shape shape = new Shape(op, left == null ? -1 : left.id, right == null ? -1 : right.id);
        Node old = nodes.get(shape);
        if (old != null) return old;
        Node result = new Node(op, left, right, nodes.size());
        nodes.put(shape, result);
        return result;
    }

    Node leaf(String text) {
        return node(text, null, null);
    }

    Node not(Node child) {
        return node("~", child, null);
    }

    static int precedence(String op) {
        return switch (op) {
            case "<->" -> 1;
            case "->" -> 2;
            case "|" -> 3;
            case "^" -> 4;
            case "&" -> 5;
            default -> 6;
        };
    }

    String print(Node n) {
        String old = printed.get(n.id);
        if (old != null) return old;
        String result;
        if (n.left == null) result = n.op;
        else if (!n.binary()) result = "~" + (n.left.binary() ? "(" + print(n.left) + ")" : print(n.left));
        else {
            String a = print(n.left), b = print(n.right);
            int p = precedence(n.op);
            if (n.left.binary() && (precedence(n.left.op) < p || n.op.equals("->") && n.left.op.equals("->"))) a = "(" + a + ")";
            if (n.right.binary() && (precedence(n.right.op) < p || n.right.op.equals(n.op) && !n.op.equals("->"))) b = "(" + b + ")";
            result = a + " " + n.op + " " + b;
        }
        printed.put(n.id, result);
        return result;
    }

    static int size(Node n) {
        return 1 + (n.left == null ? 0 : size(n.left)) + (n.right == null ? 0 : size(n.right));
    }

    static int depth(Node n) {
        return 1 + Math.max(n.left == null ? 0 : depth(n.left), n.right == null ? 0 : depth(n.right));
    }

    static String variables(int mask) {
        StringBuilder s = new StringBuilder();
        for (int i = 0; i < 26; i++) if ((mask & 1 << i) != 0) s.append((char)('A' + i));
        return s.toString();
    }

    record Token(String text, int position) { }

    class Parser {
        final List<Token> tokens = new ArrayList<>();
        int at, end;
        Parser(String text, int start) {
            end = start + text.length();
            for (int i = 0; i < text.length();) {
                char c = text.charAt(i);
                if (c == ' ') {
                    i++;
                    continue;
                }
                int first = i;
                if (text.startsWith("<->", i)) i += 3;
                else if (text.startsWith("->", i)) i += 2;
                else if (lower(c)) {
                    i++;
                    while (i < text.length() && (lower(text.charAt(i)) || digit(text.charAt(i)))) i++;
                } else if (upper(c) || "01~&^|()".indexOf(c) >= 0) i++;
                else {
                    fail("invalid character '" + c + "' at " + (start + i));
                    return;
                }
                tokens.add(new Token(text.substring(first, i), start + first));
            }
        }
        String peek() {
            return at == tokens.size() ? "" : tokens.get(at).text;
        }
        void unexpected() {
            if (at == tokens.size()) fail("unexpected end of formula at " + end);
            Token t = tokens.get(at);
            fail("unexpected '" + t.text + "' at " + t.position);
        }
        Node unary() {
            String t = peek();
            if (t.equals("~")) {
                at++;
                return not(unary());
            }
            if (t.equals("(")) {
                at++;
                Node n = expression(1);
                if (!peek().equals(")")) unexpected();
                at++;
                return n;
            }
            if (!t.isEmpty() && (upper(t.charAt(0)) || t.equals("0") || t.equals("1"))) {
                at++;
                return leaf(t);
            }
            if (!t.isEmpty() && lower(t.charAt(0))) {
                Token token = tokens.get(at++);
                Node n = definitions.get(t);
                if (n == null) fail("undefined name '" + t + "' at " + token.position);
                return n;
            }
            unexpected();
            return null;
        }
        Node expression(int level) {
            if (level == 6) return unary();
            Node left = expression(level + 1);
            String op = switch (level) {
                case 1 -> "<->";
                case 2 -> "->";
                case 3 -> "|";
                case 4 -> "^";
                default -> "&";
            };
            while (peek().equals(op)) {
                at++;
                left = node(op, left, expression(level == 2 ? level : level + 1));
            }
            return left;
        }
        Node parse() {
            Node n = expression(1);
            if (at != tokens.size()) unexpected();
            return n;
        }
    }

    Node parse(String text, int start) {
        return new Parser(text, start).parse();
    }

    Node nnf(Node n, boolean positive) {
        long key = 2L * n.id + (positive ? 1 : 0);
        Node old = normalForms.get(key);
        if (old != null) return old;
        Node result;
        if (n.left == null) result = n.op.equals("0") || n.op.equals("1") ? leaf(positive ? n.op : n.op.equals("0") ? "1" : "0") : positive ? n : not(n);
        else if (n.op.equals("~")) result = nnf(n.left, !positive);
        else if (n.op.equals("&") || n.op.equals("|")) result = node(positive ? n.op : n.op.equals("&") ? "|" : "&", nnf(n.left, positive), nnf(n.right, positive));
        else if (n.op.equals("->")) result = node(positive ? "|" : "&", nnf(n.left, !positive), nnf(n.right, positive));
        else {
            boolean equal = n.op.equals("<->") == positive;
            result = node("|", node("&", nnf(n.left, true), nnf(n.right, equal)), node("&", nnf(n.left, false), nnf(n.right, !equal)));
        }
        normalForms.put(key, result);
        return result;
    }

    Node dual(Node n, Map<Integer, Node> memo) {
        Node old = memo.get(n.id);
        if (old != null) return old;
        Node result;
        if (n.left == null) result = n.op.equals("0") ? leaf("1") : n.op.equals("1") ? leaf("0") : n;
        else if (n.op.equals("~")) result = not(dual(n.left, memo));
        else {
            Node a = dual(n.left, memo), b = dual(n.right, memo);
            result = switch (n.op) {
                case "&" -> node("|", a, b);
                case "|" -> node("&", a, b);
                case "^" -> node("<->", a, b);
                case "<->" -> node("^", a, b);
                default -> node("&", not(a), b);
            };
        }
        memo.put(n.id, result);
        return result;
    }

    Node reduceNot(Node n) {
        return n.op.equals("0") ? leaf("1") : n.op.equals("1") ? leaf("0") : n.op.equals("~") ? n.left : not(n);
    }

    boolean complement(Node a, Node b) {
        return a.op.equals("~") && a.left == b || b.op.equals("~") && b.left == a;
    }

    Node simplifyBinary(String op, Node a, Node b) {
        boolean a0 = a.op.equals("0"), a1 = a.op.equals("1"), b0 = b.op.equals("0"), b1 = b.op.equals("1");
        switch (op) {
            case "&":
                if (a0 || b0) return leaf("0");
                if (a1) return b;
                if (b1 || a == b) return a;
                if (complement(a, b)) return leaf("0");
                break;
            case "|":
                if (a1 || b1) return leaf("1");
                if (a0) return b;
                if (b0 || a == b) return a;
                if (complement(a, b)) return leaf("1");
                break;
            case "^":
                if (a0) return b;
                if (b0) return a;
                if (a1) return reduceNot(b);
                if (b1) return reduceNot(a);
                if (a == b) return leaf("0");
                if (complement(a, b)) return leaf("1");
                break;
            case "->":
                if (a0 || b1) return leaf("1");
                if (a1) return b;
                if (b0) return reduceNot(a);
                if (a == b) return leaf("1");
                if (complement(a, b)) return b;
                break;
            case "<->":
                if (a1) return b;
                if (b1) return a;
                if (a0) return reduceNot(b);
                if (b0) return reduceNot(a);
                if (a == b) return leaf("1");
                if (complement(a, b)) return leaf("0");
                break;
        }
        return node(op, a, b);
    }

    Node simplify(Node n, Map<Character, Integer> substitutions, Map<Integer, Node> memo) {
        Node old = memo.get(n.id);
        if (old != null) return old;
        Node result;
        if (n.left == null) result = substitutions.containsKey(n.op.charAt(0)) ? leaf(substitutions.get(n.op.charAt(0)).toString()) : n;
        else if (n.op.equals("~")) result = reduceNot(simplify(n.left, substitutions, memo));
        else result = simplifyBinary(n.op, simplify(n.left, substitutions, memo), simplify(n.right, substitutions, memo));
        memo.put(n.id, result);
        return result;
    }

    static int evaluate(Node n, int trueVariables, Map<Integer, Integer> memo) {
        Integer old = memo.get(n.id);
        if (old != null) return old;
        int result;
        if (n.left == null) result = upper(n.op.charAt(0)) ? (trueVariables >>> (n.op.charAt(0) - 'A')) & 1 : n.op.charAt(0) - '0';
        else if (n.op.equals("~")) result = 1 - evaluate(n.left, trueVariables, memo);
        else {
            int a = evaluate(n.left, trueVariables, memo), b = evaluate(n.right, trueVariables, memo);
            result = switch (n.op) {
                case "&" -> a & b;
                case "|" -> a | b;
                case "^" -> a ^ b;
                case "->" -> (1 - a) | b;
                default -> 1 - (a ^ b);
            };
        }
        memo.put(n.id, result);
        return result;
    }

    static int[] truth(Node n, String vars) {
        int[] table = new int[1 << vars.length()];
        for (int r = 0; r < table.length; r++) {
            int mask = 0;
            for (int i = 0; i < vars.length(); i++) if ((r & 1 << (vars.length() - 1 - i)) != 0) mask |= 1 << (vars.charAt(i) - 'A');
            table[r] = evaluate(n, mask, new HashMap<>());
        }
        return table;
    }

    static String binary(int row, int count) {
        if (count == 0) return "";
        String s = Integer.toBinaryString(row);
        return "0".repeat(count - s.length()) + s;
    }

    static String assignment(int row, String vars) {
        List<String> parts = new ArrayList<>();
        String bits = binary(row, vars.length());
        for (int i = 0; i < vars.length(); i++) parts.add(vars.charAt(i) + "=" + bits.charAt(i));
        return "{" + String.join(" ", parts) + "}";
    }

    static int patternCompare(String a, String b) {
        for (int i = 0; i < a.length(); i++) {
            int c = Integer.compare("10-".indexOf(a.charAt(i)), "10-".indexOf(b.charAt(i)));
            if (c != 0) return c;
        }
        return 0;
    }

    static int literals(String p) {
        return (int)p.chars().filter(c -> c != '-').count();
    }

    static String term(String pattern, String vars, boolean clause) {
        List<String> parts = new ArrayList<>();
        for (int i = 0; i < vars.length(); i++) if (pattern.charAt(i) != '-') parts.add((pattern.charAt(i) == '0' ? "~" : "") + vars.charAt(i));
        return parts.isEmpty() ? clause ? "0" : "1" : String.join(clause ? " | " : " & ", parts);
    }

    static String form(List<String> patterns, String vars, boolean clauses) {
        if (patterns.isEmpty()) return clauses ? "1" : "0";
        List<String> parts = new ArrayList<>();
        for (String p : patterns) {
            String s = term(p, vars, clauses);
            parts.add(clauses && patterns.size() >= 2 && literals(p) >= 2 ? "(" + s + ")" : s);
        }
        return String.join(clauses ? " & " : " | ", parts);
    }

    static String opposite(String p) {
        StringBuilder b = new StringBuilder();
        for (char c : p.toCharArray()) b.append(c == '1' ? '0' : c == '0' ? '1' : '-');
        return b.toString();
    }

    static int[] coefficients(int[] table) {
        int[] out = table.clone();
        for (int bit = 1; bit < out.length; bit <<= 1) for (int s = 0; s < out.length; s++) if ((s & bit) != 0) out[s] ^= out[s ^ bit];
        return out;
    }

    record Implicant(String pattern, int mask, int bits, BitSet coverage) { }

    static void implicants(int at, int n, int mask, int bits, String prefix, List<Implicant> out, BitSet allowed) {
        if (at == n) {
            BitSet coverage = new BitSet(1 << n);
            for (int row = 0; row < 1 << n; row++) if (((row ^ bits) & mask) == 0) {
                if (!allowed.get(row)) return;
                coverage.set(row);
            }
            out.add(new Implicant(prefix, mask, bits, coverage));
            return;
        }
        int bit = 1 << (n - 1 - at);
        implicants(at + 1, n, mask | bit, bits | bit, prefix + "1", out, allowed);
        implicants(at + 1, n, mask | bit, bits, prefix + "0", out, allowed);
        implicants(at + 1, n, mask, bits, prefix + "-", out, allowed);
    }

    static List<String> coverPatterns(List<Implicant> cover, boolean pos) {
        List<String> result = new ArrayList<>();
        for (Implicant p : cover) result.add(pos ? opposite(p.pattern) : p.pattern);
        result.sort(Main::patternCompare);
        return result;
    }

    static int coverLiterals(List<Implicant> cover) {
        return cover.stream().mapToInt(p -> Integer.bitCount(p.mask)).sum();
    }

    static boolean better(List<Implicant> candidate, List<Implicant> best, boolean pos) {
        if (best == null || candidate.size() != best.size()) return best == null || candidate.size() < best.size();
        int a = coverLiterals(candidate), b = coverLiterals(best);
        if (a != b) return a < b;
        List<String> x = coverPatterns(candidate, pos), y = coverPatterns(best, pos);
        for (int i = 0; i < x.size(); i++) {
            int c = patternCompare(x.get(i), y.get(i));
            if (c != 0) return c < 0;
        }
        return false;
    }

    static List<String> minimize(String vars, int[] f, int[] dc, boolean pos) {
        int n = vars.length();
        BitSet on = new BitSet(f.length), allowed = new BitSet(f.length);
        for (int r = 0; r < f.length; r++) {
            if ((pos ? 1 - f[r] : f[r]) == 1 && (dc == null || dc[r] == 0)) on.set(r);
            if (on.get(r) || dc != null && dc[r] == 1) allowed.set(r);
        }
        List<Implicant> all = new ArrayList<>();
        implicants(0, n, 0, 0, "", all, allowed);
        Set<Integer> keys = new HashSet<>();
        for (Implicant p : all) keys.add((p.mask << 8) | p.bits);
        List<Implicant> primes = new ArrayList<>();
        int[] stages = new int[n + 1], primeStages = new int[n + 1];
        for (Implicant p : all) {
            int stage = n - Integer.bitCount(p.mask);
            stages[stage]++;
            boolean prime = true;
            for (int bit = 1; bit < 1 << n; bit <<= 1) if ((p.mask & bit) != 0 && keys.contains(((p.mask ^ bit) << 8) | (p.bits & ~bit))) {
                prime = false;
                break;
            }
            if (prime) {
                primeStages[stage]++;
                if (p.coverage.intersects(on)) primes.add(p);
            }
        }
        primes.sort((a, b) -> patternCompare(a.pattern, b.pattern));
        Set<Implicant> essentialSet = new HashSet<>();
        for (int r = on.nextSetBit(0); r >= 0; r = on.nextSetBit(r + 1)) {
            Implicant only = null;
            int count = 0;
            for (Implicant p : primes) if (p.coverage.get(r)) {
                only = p;
                count++;
            }
            if (count == 1) essentialSet.add(only);
        }
        List<Implicant> essential = primes.stream().filter(essentialSet::contains).toList(), optional = primes.stream().filter(p -> !essentialSet.contains(p)).toList();
        List<Implicant> best = null;
        for (int mask = 0; mask < 1 << optional.size(); mask++) {
            List<Implicant> candidate = new ArrayList<>(essential);
            BitSet covered = new BitSet(f.length);
            for (int i = 0; i < optional.size(); i++) if ((mask & 1 << i) != 0) candidate.add(optional.get(i));
            if (best != null && candidate.size() > best.size()) continue;
            for (Implicant p : candidate) covered.or(p.coverage);
            BitSet missing = (BitSet)on.clone();
            missing.andNot(covered);
            if (missing.isEmpty() && better(candidate, best, pos)) best = candidate;
        }
        List<String> out = new ArrayList<>();
        if (!pos) {
            for (int stage = 0; stage <= n; stage++) {
                out.add("stage " + stage + ": implicants " + stages[stage] + " primes " + primeStages[stage]);
                if (stage == n || stages[stage + 1] == 0) break;
            }
            out.add("primes: " + (primes.isEmpty() ? "none" : String.join(", ", coverPatterns(primes, false).stream().map(p -> term(p, vars, false)).toList())));
            out.add("essential: " + (essential.isEmpty() ? "none" : String.join(", ", coverPatterns(essential, false).stream().map(p -> term(p, vars, false)).toList())));
        }
        out.add("minimal: " + form(coverPatterns(best, pos), vars, pos));
        out.add((pos ? "clauses " : "terms ") + best.size() + " literals " + coverLiterals(best));
        return out;
    }

    record Clause(int positive, int negative) {
        boolean subset(Clause other) {
            return (positive & other.positive) == positive && (negative & other.negative) == negative;
        }
        Clause union(Clause other) {
            return new Clause(positive | other.positive, negative | other.negative);
        }
        boolean tautology() {
            return (positive & negative) != 0;
        }
        String pattern(String vars) {
            StringBuilder s = new StringBuilder();
            for (char c : vars.toCharArray()) {
                int bit = 1 << (c - 'A');
                s.append((positive & bit) != 0 ? '1' : (negative & bit) != 0 ? '0' : '-');
            }
            return s.toString();
        }
    }

    static Set<Clause> tidy(Set<Clause> input) {
        List<Clause> sorted = input.stream().filter(c -> !c.tautology()).sorted((a, b) -> Integer.compare(Integer.bitCount(a.positive | a.negative), Integer.bitCount(b.positive | b.negative))).toList();
        Set<Clause> out = new HashSet<>();
        for (Clause c : sorted) if (out.stream().noneMatch(e -> e.subset(c))) out.add(c);
        return out;
    }

    Set<Clause> clauses(Node n, Map<Integer, Set<Clause>> memo) {
        Set<Clause> old = memo.get(n.id);
        if (old != null) return old;
        Set<Clause> result = new HashSet<>();
        if (n.op.equals("0")) result.add(new Clause(0, 0));
        else if (n.op.equals("1")) {
            // True contributes no clauses.
        } else if (n.left == null) result.add(new Clause(1 << (n.op.charAt(0) - 'A'), 0));
        else if (n.op.equals("~")) result.add(new Clause(0, 1 << (n.left.op.charAt(0) - 'A')));
        else {
            Set<Clause> a = clauses(n.left, memo), b = clauses(n.right, memo);
            if (n.op.equals("&")) {
                result.addAll(a);
                result.addAll(b);
            } else for (Clause x : a) for (Clause y : b) {
                Clause c = x.union(y);
                if (!c.tautology()) result.add(c);
            }
            result = tidy(result);
        }
        memo.put(n.id, result);
        return result;
    }

    static List<String> clausePatterns(Set<Clause> clauses, String vars) {
        List<String> out = new ArrayList<>();
        for (Clause c : clauses) out.add(c.pattern(vars));
        out.sort(Main::patternCompare);
        return out;
    }

    record Decision(int variable, int low, int high) { }

    static int bdd(int[] values, int from, int count, int variable, List<Decision> nodes, Map<Decision, Integer> index) {
        if (count == 1) return values[from];
        int low = bdd(values, from, count / 2, variable + 1, nodes, index), high = bdd(values, from + count / 2, count / 2, variable + 1, nodes, index);
        if (low == high) return low;
        Decision d = new Decision(variable, low, high);
        Integer old = index.get(d);
        if (old != null) return old;
        int id = nodes.size() + 2;
        nodes.add(d);
        index.put(d, id);
        return id;
    }

    static String[] words(String text) {
        String s = text.trim();
        return s.isEmpty() ? new String[0] : s.split(" +");
    }

    void define(String name, Node formula, List<String> out) {
        out.add((definitions.containsKey(name) ? "redefined " : "defined ") + name + " = " + print(formula));
        definitions.put(name, formula);
    }

    List<String> command(String line) {
        int space = line.indexOf(' ');
        String command = space < 0 ? line : line.substring(0, space), arg = space < 0 ? "" : line.substring(space + 1);
        Set<String> single = Set.of("PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "MINIMIZE", "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "PROPS", "BDD", "CLAUSES", "DP");
        Set<String> split = Set.of("RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES");
        if (!single.contains(command) && !split.contains(command) && !Set.of("DEF", "DEFSUM", "DEL", "LIST").contains(command)) fail("unknown command " + command);
        if (command.equals("LIST") && space >= 0) fail("unexpected argument");
        if (!command.equals("LIST") && space < 0) fail("missing argument");
        int semicolon = arg.indexOf(';');
        if (split.contains(command) && semicolon < 0) fail("missing ';'");
        List<String> out = new ArrayList<>();
        if (command.equals("LIST")) {
            out.add("names: " + definitions.size());
            for (var e : definitions.entrySet()) out.add(e.getKey() + " = " + print(e.getValue()));
            return out;
        }
        if (command.equals("DEL")) {
            if (!name(arg)) fail("invalid name '" + arg + "'");
            if (!definitions.containsKey(arg)) fail("undefined name '" + arg + "'");
            definitions.remove(arg);
            return List.of("deleted " + arg);
        }
        if (command.equals("DEF")) {
            int at = arg.indexOf(' ');
            if (at < 0) fail("missing argument");
            String name = arg.substring(0, at);
            if (!name(name)) fail("invalid name '" + name + "'");
            Node formula = parse(arg.substring(at + 1), name.length() + 6);
            define(name, formula, out);
            return out;
        }
        if (command.equals("DEFSUM")) {
            if (semicolon < 0) fail("missing ';'");
            String[] front = words(arg.substring(0, semicolon)), back = words(arg.substring(semicolon + 1));
            if (front.length == 0) fail("missing argument");
            if (!name(front[0])) fail("invalid name '" + front[0] + "'");
            if (front.length == 1) fail("bad variable list");
            for (int i = 1; i < front.length; i++) if (front[i].length() != 1 || !upper(front[i].charAt(0)) || i > 1 && front[i - 1].compareTo(front[i]) >= 0) fail("bad variable list");
            int n = front.length - 1;
            if (n >= 9) fail("too many variables: " + n);
            int previous = -1;
            Node result = null;
            for (String word : back) {
                if (word.isEmpty() || word.length() > 1 && word.charAt(0) == '0' || !word.chars().allMatch(c -> c >= '0' && c <= '9')) fail("bad minterm '" + word + "'");
                int row = Integer.parseInt(word);
                if (row >= 1 << n || row <= previous) fail("bad minterm '" + word + "'");
                previous = row;
                Node term = null;
                for (int i = 0; i < n; i++) {
                    Node literal = leaf(front[i + 1]);
                    if ((row & 1 << (n - i - 1)) == 0) literal = not(literal);
                    term = term == null ? literal : node("&", term, literal);
                }
                result = result == null ? term : node("|", result, term);
            }
            define(front[0], result == null ? leaf("0") : result, out);
            return out;
        }
        int start = command.length() + 2;
        String first = split.contains(command) ? arg.substring(0, semicolon) : arg, second = split.contains(command) ? arg.substring(semicolon + 1) : "";
        Node f = parse(first, start), g = null;
        if (Set.of("MINDC", "EQUIV", "IMPLIES").contains(command)) g = parse(second, start + semicolon + 1);
        if (command.equals("RESTRICT")) {
            String[] assignments = words(second);
            if (assignments.length == 0) fail("missing assignment");
            Map<Character, Integer> values = new HashMap<>();
            for (String a : assignments) {
                if (a.length() != 3 || !upper(a.charAt(0)) || a.charAt(1) != '=' || "01".indexOf(a.charAt(2)) < 0) fail("bad assignment '" + a + "'");
                if (values.putIfAbsent(a.charAt(0), a.charAt(2) - '0') != null) fail("duplicate variable " + a.charAt(0));
            }
            return List.of("restricted: " + print(simplify(f, values, new HashMap<>())));
        }
        if (command.equals("COFACTOR")) {
            String[] x = words(second);
            if (x.length != 1 || x[0].length() != 1 || !upper(x[0].charAt(0))) fail("bad variable");
            char c = x[0].charAt(0);
            Node f1 = simplify(f, Map.of(c, 1), new HashMap<>()), f0 = simplify(f, Map.of(c, 0), new HashMap<>());
            return List.of("cofactor " + c + "=1: " + print(f1), "cofactor " + c + "=0: " + print(f0), "difference: " + print(simplifyBinary("^", f1, f0)));
        }
        String vars = variables(f.variables | (g == null ? 0 : g.variables));
        int n = vars.length();
        if (command.equals("PRINT")) return List.of("formula: " + print(f), "variables: " + (vars.isEmpty() ? "none" : String.join(" ", vars.split(""))), "size " + size(f) + " depth " + depth(f));
        if (command.equals("NNF")) return List.of("nnf: " + print(nnf(f, true)));
        if (command.equals("DUAL")) return List.of("dual: " + print(dual(f, new HashMap<>())));
        if (command.equals("SIMPLIFY")) return List.of("simplified: " + print(simplify(f, Map.of(), new HashMap<>())));
        if (command.equals("CLAUSES") || command.equals("DP")) {
            Set<Clause> clauses = clauses(nnf(f, true), new HashMap<>());
            if (command.equals("CLAUSES")) return List.of("clauses: " + form(clausePatterns(clauses, vars), vars, true));
            out.add("start: clauses " + clauses.size());
            for (char c : vars.toCharArray()) {
                if (clauses.isEmpty() || clauses.contains(new Clause(0, 0))) break;
                int bit = 1 << (c - 'A');
                List<Clause> positive = clauses.stream().filter(x -> (x.positive & bit) != 0).toList(), negative = clauses.stream().filter(x -> (x.negative & bit) != 0).toList();
                Set<Clause> resolvents = new HashSet<>(), next = new HashSet<>();
                for (Clause a : positive) for (Clause b : negative) {
                    Clause r = new Clause((a.positive | b.positive) & ~bit, (a.negative | b.negative) & ~bit);
                    if (!r.tautology()) resolvents.add(r);
                }
                for (Clause a : clauses) if (((a.positive | a.negative) & bit) == 0) next.add(a);
                next.addAll(resolvents);
                clauses = tidy(next);
                out.add("eliminate " + c + ": resolvents " + resolvents.size() + " clauses " + clauses.size());
            }
            out.add("result: " + (clauses.contains(new Clause(0, 0)) ? "unsatisfiable" : "satisfiable"));
            return out;
        }
        if (n >= 9) fail("too many variables: " + n);
        int[] table = truth(f, vars), other = g == null ? null : truth(g, vars);
        int rows = table.length;
        if (command.equals("MINIMIZE") || command.equals("MINDC") || command.equals("MINPOS")) return minimize(vars, table, other, command.equals("MINPOS"));
        switch (command) {
            case "TABLE" -> {
                out.add((n == 0 ? "" : String.join(" ", vars.split("")) + " ") + "| F");
                for (int r = 0; r < rows; r++) out.add((n == 0 ? "" : String.join(" ", binary(r, n).split("")) + " ") + "| " + table[r]);
            }
            case "MINTERMS", "MAXTERMS", "DNF", "CNF" -> {
                boolean positive = command.equals("MINTERMS") || command.equals("DNF");
                List<String> patterns = new ArrayList<>(), numbers = new ArrayList<>();
                for (int r = 0; r < rows; r++) if (table[r] == (positive ? 1 : 0)) {
                    String p = binary(r, n);
                    patterns.add(positive ? p : opposite(p));
                    numbers.add(Integer.toString(r));
                }
                String label = command.toLowerCase(java.util.Locale.ROOT);
                out.add(label + ": " + (command.equals("DNF") || command.equals("CNF") ? form(patterns, vars, !positive) : numbers.isEmpty() ? "none" : String.join(" ", numbers)));
            }
            case "ANF" -> {
                int[] coeff = coefficients(table);
                List<String> patterns = new ArrayList<>();
                for (int r = 0; r < rows; r++) if (coeff[r] == 1) patterns.add(binary(r, n).replace('0', '-'));
                patterns.sort((a, b) -> literals(a) != literals(b) ? Integer.compare(literals(a), literals(b)) : patternCompare(a, b));
                out.add("anf: " + (patterns.isEmpty() ? "0" : String.join(" ^ ", patterns.stream().map(p -> term(p, vars, false)).toList())));
            }
            case "SAT", "TAUT" -> {
                boolean sat = command.equals("SAT");
                int firstRow = -1;
                for (int r = 0; r < rows; r++) if (table[r] == (sat ? 1 : 0)) {
                    firstRow = r;
                    break;
                }
                out.add(firstRow < 0 ? sat ? "unsatisfiable" : "tautology" : (sat ? "satisfiable: " : "not a tautology: ") + assignment(firstRow, vars));
            }
            case "COUNT" -> {
                int count = 0;
                for (int v : table) count += v;
                out.add("models: " + count + " of " + rows);
            }
            case "EQUIV", "IMPLIES" -> {
                boolean equivalent = command.equals("EQUIV");
                int firstRow = -1;
                for (int r = 0; r < rows; r++) if (equivalent ? table[r] != other[r] : table[r] == 1 && other[r] == 0) {
                    firstRow = r;
                    break;
                }
                out.add(firstRow < 0 ? equivalent ? "equivalent" : "implies" : equivalent ? "not equivalent: " + assignment(firstRow, vars) + " f=" + table[firstRow] + " g=" + other[firstRow] : "does not imply: " + assignment(firstRow, vars));
            }
            case "PROPS" -> {
                List<String> dependencies = new ArrayList<>();
                boolean selfDual = true, monotone = true, linear = true, symmetric = true;
                for (int i = 0; i < n; i++) {
                    int bit = 1 << (n - 1 - i);
                    for (int r = 0; r < rows; r++) if (table[r] != table[r ^ bit]) {
                        dependencies.add(Character.toString(vars.charAt(i)));
                        break;
                    }
                }
                int[] coeff = coefficients(table), weights = new int[n + 1];
                java.util.Arrays.fill(weights, -1);
                for (int r = 0; r < rows; r++) {
                    selfDual &= table[r] != table[rows - 1 - r];
                    if (coeff[r] == 1 && Integer.bitCount(r) > 1) linear = false;
                    int weight = Integer.bitCount(r);
                    if (weights[weight] >= 0 && weights[weight] != table[r]) symmetric = false;
                    weights[weight] = table[r];
                    for (int bit = 1; bit < rows; bit <<= 1) if ((r & bit) == 0 && table[r] > table[r | bit]) monotone = false;
                }
                out.add("depends: " + (dependencies.isEmpty() ? "none" : String.join(" ", dependencies)));
                String[] labels = {"zero-preserving", "one-preserving", "self-dual", "monotone", "linear", "symmetric"};
                boolean[] values = {table[0] == 0, table[rows - 1] == 1, selfDual, monotone, linear, symmetric};
                for (int i = 0; i < labels.length; i++) out.add(labels[i] + ": " + (values[i] ? "yes" : "no"));
            }
            case "KMAP" -> {
                if (n < 2 || n > 4) fail("kmap needs 2 to 4 variables");
                int p = n / 2, q = n - p;
                String label = vars.substring(0, p) + "\\" + vars.substring(p);
                StringBuilder header = new StringBuilder(label);
                for (int i = 0; i < 1 << q; i++) header.append(' ').append(binary(i ^ i / 2, q));
                out.add(header.toString());
                for (int i = 0; i < 1 << p; i++) {
                    int r = i ^ i / 2;
                    StringBuilder row = new StringBuilder(binary(r, p) + " ".repeat(q + 1));
                    for (int j = 0; j < 1 << q; j++) row.append(" ".repeat(q)).append(table[(r << q) | (j ^ j / 2)]);
                    out.add(row.toString());
                }
            }
            case "BDD" -> {
                List<Decision> decisions = new ArrayList<>();
                int root = bdd(table, 0, rows, 0, decisions, new HashMap<>());
                int[] paths = new int[decisions.size() + 2];
                paths[1] = 1;
                out.add("nodes: " + decisions.size());
                for (int i = 0; i < decisions.size(); i++) {
                    Decision d = decisions.get(i);
                    paths[i + 2] = paths[d.low] + paths[d.high];
                    out.add((i + 2) + " = ite(" + vars.charAt(d.variable) + ", " + d.high + ", " + d.low + ")");
                }
                out.add("root: " + root);
                out.add("paths: " + paths[root]);
            }
            default -> throw new IllegalStateException();
        }
        return out;
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main workbench = new Main();
        int count = Integer.parseInt(reader.readLine());
        for (int i = 0; i < count; i++) {
            String line = reader.readLine();
            try {
                for (String output : workbench.command(line)) System.out.println(output);
            } catch (Problem error) {
                System.out.println(error.getMessage());
            }
        }
    }
}
