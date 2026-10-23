import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    static final Set<String> RESERVED = Set.of("not", "mod", "count", "sum", "min", "max", "retract", "dump", "why", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt");
    static final Set<String> COMPARISONS = Set.of("=", "!=", "<", "<=", ">", ">=");
    static final Set<String> OPERATIONS = Set.of("+", "-", "*", "/", "mod");

    static class Problem extends RuntimeException {
        Problem(String reason) {
            super(reason);
        }
    }

    static void fail(String reason) {
        throw new Problem(reason);
    }

    static boolean lower(char c) {
        return c >= 'a' && c <= 'z';
    }

    static boolean digit(char c) {
        return c >= '0' && c <= '9';
    }

    static boolean wordChar(char c) {
        return lower(c) || c >= 'A' && c <= 'Z' || digit(c) || c == '_';
    }

    record Value(boolean integer, long number, String symbol) implements Comparable<Value> {
        static Value integer(long n) {
            return new Value(true, n, "");
        }
        static Value symbol(String s) {
            return new Value(false, 0, s);
        }
        public int compareTo(Value other) {
            if (integer != other.integer) return integer ? -1 : 1;
            return integer ? Long.compare(number, other.number) : symbol.compareTo(other.symbol);
        }
        public String toString() {
            if (integer) return Long.toString(number);
            boolean plain = !symbol.isEmpty() && lower(symbol.charAt(0)) && !RESERVED.contains(symbol);
            for (char c : symbol.toCharArray()) plain &= wordChar(c);
            return plain ? symbol : "\"" + symbol + "\"";
        }
    }

    record Tuple(List<Value> values) implements Comparable<Tuple> {
        Tuple {
            values = List.copyOf(values);
        }
        public int compareTo(Tuple other) {
            for (int i = 0; i < values.size(); i++) {
                int c = values.get(i).compareTo(other.values.get(i));
                if (c != 0) return c;
            }
            return 0;
        }
    }

    record Term(String variable, Value value, boolean anonymous) {
        String text(Map<String, Value> env) {
            if (anonymous) return "_";
            if (value != null) return value.toString();
            return env != null && env.containsKey(variable) ? env.get(variable).toString() : variable;
        }
        Value get(Map<String, Value> env) {
            return value != null ? value : env.get(variable);
        }
    }

    record Expr(String op, Term term, Expr left, Expr right) {
        String text(Map<String, Value> env) {
            if (term != null) return term.text(env);
            if (op.equals("()")) return "(" + left.text(env) + ")";
            return left.text(env) + " " + op + " " + right.text(env);
        }
        void terms(List<Term> out) {
            if (term != null) out.add(term);
            else {
                left.terms(out);
                if (right != null) right.terms(out);
            }
        }
        Value evaluate(Map<String, Value> env) {
            if (term != null) return term.get(env);
            Value a = left.evaluate(env);
            if (op.equals("()")) return a;
            Value b = right.evaluate(env);
            if (a == null || b == null || !a.integer || !b.integer || (op.equals("/") || op.equals("mod")) && b.number == 0) return null;
            return Value.integer(switch (op) {
                case "+" -> a.number + b.number; case "-" -> a.number - b.number; case "*" -> a.number * b.number; case "/" -> Math.floorDiv(a.number, b.number); default -> a.number - b.number * Math.floorDiv(a.number, b.number);
            });
        }
    }

    record Atom(String name, List<Term> terms) {
        String text(Map<String, Value> env) {
            return name + (terms.isEmpty() ? "" : "(" + String.join(", ", terms.stream().map(t -> t.text(env)).toList()) + ")");
        }
        Tuple tuple(Map<String, Value> env) {
            return new Tuple(terms.stream().map(t -> t.get(env)).toList());
        }
    }

    record Literal(Atom atom, boolean negative, Expr left, String op, Expr right) {
        List<Term> terms() {
            if (atom != null) return atom.terms;
            List<Term> out = new ArrayList<>();
            left.terms(out);
            right.terms(out);
            return out;
        }
        String text(Map<String, Value> env) {
            return atom != null ? (negative ? "not " : "") + atom.text(env) : left.text(env) + " " + op + " " + right.text(env);
        }
        boolean comparison(Map<String, Value> env) {
            Value a = left.evaluate(env), b = right.evaluate(env);
            if (a == null || b == null) return false;
            if (op.equals("=")) return a.equals(b);
            if (op.equals("!=")) return !a.equals(b);
            if (!a.integer || !b.integer) return false;
            int c = Long.compare(a.number, b.number);
            return switch (op) {
                case "<" -> c < 0;
                case "<=" -> c <= 0;
                case ">" -> c > 0;
                default -> c >= 0;
            };
        }
    }

    record Rule(int number, Atom head, List<Literal> body) {
        String text() {
            return (head == null ? ":- " : head.text(null) + " :- ") + String.join(", ", body.stream().map(l -> l.text(null)).toList()) + ".";
        }
        List<Term> terms() {
            List<Term> out = new ArrayList<>();
            if (head != null) out.addAll(head.terms);
            for (Literal l : body) out.addAll(l.terms());
            return out;
        }
    }

    record Token(String kind, String text) { }

    record Statement(String kind, Atom atom, List<Literal> body, String name, long number, String aggregate, String variable) { }

    static class Parser {
        List<Token> tokens = new ArrayList<>();
        int at;
        Parser(String line) {
            for (int i = 0; i < line.length();) {
                char c = line.charAt(i);
                if (c == ' ') {
                    i++;
                    continue;
                }
                if (c == '%') break;
                int first = i;
                String kind;
                if (c == '"') {
                    int end = line.indexOf('"', i + 1);
                    if (end < 0) fail("unterminated string");
                    i = end + 1;
                    kind = "string";
                } else if (i + 1 < line.length() && Set.of(":-", "?-", "!=", "<=", ">=").contains(line.substring(i, i + 2))) {
                    i += 2;
                    kind = line.substring(first, i);
                } else if ("(),.:=<>+-*/".indexOf(c) >= 0) {
                    i++;
                    kind = Character.toString(c);
                } else if (wordChar(c)) {
                    while (i < line.length() && wordChar(line.charAt(i))) i++;
                    String s = line.substring(first, i);
                    if (lower(c)) kind = RESERVED.contains(s) ? s : "name";
                    else if (c >= 'A' && c <= 'Z') kind = "variable";
                    else if (s.equals("_")) kind = "anonymous";
                    else if (s.chars().allMatch(x -> x >= '0' && x <= '9')) {
                        if (Long.parseLong(s) > 1000000000L) fail("integer out of range '" + s + "'");
                        kind = "integer";
                    } else {
                        fail("bad token '" + s + "'");
                        return;
                    }
                } else {
                    fail("bad character '" + c + "'");
                    return;
                }
                tokens.add(new Token(kind, line.substring(first, i)));
            }
            tokens.add(new Token("end", ""));
        }
        Token peek() {
            return tokens.get(at);
        }
        boolean is(String kind) {
            return peek().kind.equals(kind);
        }
        void syntax() {
            fail(is("end") ? "syntax error at end of line" : "syntax error at '" + peek().text + "'");
        }
        Token expect(String kind) {
            if (!is(kind)) syntax();
            return tokens.get(at++);
        }
        Term term() {
            Token t = peek();
            if (is("name")) {
                at++;
                return new Term(null, Value.symbol(t.text), false);
            }
            if (is("string")) {
                at++;
                return new Term(null, Value.symbol(t.text.substring(1, t.text.length() - 1)), false);
            }
            if (is("integer") || is("-")) {
                boolean minus = is("-");
                if (minus) at++;
                long n = Long.parseLong(expect("integer").text);
                return new Term(null, Value.integer(minus ? -n : n), false);
            }
            if (is("variable")) {
                at++;
                return new Term(t.text, null, false);
            }
            if (is("anonymous")) {
                at++;
                return new Term(null, null, true);
            }
            syntax();
            return null;
        }
        Atom atom() {
            String name = expect("name").text;
            List<Term> args = new ArrayList<>();
            if (is("(")) {
                at++;
                args.add(term());
                while (is(",")) {
                    at++;
                    args.add(term());
                }
                expect(")");
            }
            return new Atom(name, args);
        }
        Expr factor() {
            if (is("(")) {
                at++;
                Expr inner = expression();
                expect(")");
                return new Expr("()", null, inner, null);
            }
            return new Expr("", term(), null, null);
        }
        Expr product() {
            Expr out = factor();
            while (is("*") || is("/") || is("mod")) {
                String op = tokens.get(at++).text;
                out = new Expr(op, null, out, factor());
            }
            return out;
        }
        Expr expression() {
            Expr out = product();
            while (is("+") || is("-")) {
                String op = tokens.get(at++).text;
                out = new Expr(op, null, out, product());
            }
            return out;
        }
        Literal literal() {
            if (is("not")) {
                at++;
                return new Literal(atom(), true, null, null, null);
            }
            if (is("name") && !COMPARISONS.contains(tokens.get(at + 1).kind) && !OPERATIONS.contains(tokens.get(at + 1).kind)) return new Literal(atom(), false, null, null, null);
            Expr left = expression();
            if (!COMPARISONS.contains(peek().kind)) syntax();
            String op = tokens.get(at++).text;
            return new Literal(null, false, left, op, expression());
        }
        List<Literal> body() {
            List<Literal> out = new ArrayList<>();
            out.add(literal());
            while (is(",")) {
                at++;
                out.add(literal());
            }
            return out;
        }
        Statement statement() {
            String kind = peek().kind, name = null, aggregate = "", variable = null;
            Atom atom = null;
            List<Literal> body = List.of();
            long number = 0;
            if (is("name") || is(":-")) {
                if (is("name")) atom = atom();
                if (is(":-")) {
                    at++;
                    body = body();
                    kind = "rule";
                } else {
                    if (atom == null) syntax();
                    kind = "fact";
                }
            } else if (is("?-")) {
                at++;
                kind = "query";
                if (is("count")) {
                    aggregate = "count";
                    at++;
                } else if (is("sum") || is("min") || is("max")) {
                    aggregate = tokens.get(at++).text;
                    variable = expect("variable").text;
                    expect(":");
                }
                body = body();
            } else {
                if (!Set.of("retract", "why", "dump", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt").contains(kind)) syntax();
                at++;
                if (kind.equals("retract") || kind.equals("why")) atom = atom();
                else if (kind.equals("dump")) name = expect("name").text;
                else if (kind.equals("forget")) number = Long.parseLong(expect("integer").text);
                else if (kind.equals("listing") && is("name")) name = tokens.get(at++).text;
            }
            expect(".");
            if (!is("end")) syntax();
            return new Statement(kind, atom, body, name, number, aggregate, variable);
        }
    }

    static class Predicate {
        int arity;
        TreeSet<Tuple> facts = new TreeSet<>();
        Predicate(int arity) {
            this.arity = arity;
        }
        Predicate copy() {
            Predicate p = new Predicate(arity);
            p.facts.addAll(facts);
            return p;
        }
    }

    static class State {
        TreeMap<String, Predicate> predicates = new TreeMap<>();
        List<Rule> rules = new ArrayList<>();
        State copy() {
            State s = new State();
            for (var entry : predicates.entrySet()) s.predicates.put(entry.getKey(), entry.getValue().copy());
            s.rules.addAll(rules);
            return s;
        }
    }

    record History(State state, int line) { }

    record Derivation(int round, int rule) { }

    static class Model {
        TreeMap<String, TreeMap<Tuple, Derivation>> tuples = new TreeMap<>();
        int[] rounds, added;
    }
    State state = new State();
    List<History> history = new ArrayList<>();
    int nextRule = 1;

    static List<String> variables(List<Term> terms) {
        LinkedHashSet<String> names = new LinkedHashSet<>();
        for (Term t : terms) if (t.variable != null) names.add(t.variable);
        return new ArrayList<>(names);
    }

    static List<Term> bodyTerms(List<Literal> body) {
        List<Term> terms = new ArrayList<>();
        for (Literal l : body) terms.addAll(l.terms());
        return terms;
    }

    static List<Atom> atoms(Atom head, List<Literal> body) {
        List<Atom> out = new ArrayList<>();
        if (head != null) out.add(head);
        for (Literal l : body) if (l.atom != null) out.add(l.atom);
        return out;
    }
    TreeMap<String, Integer> predicateCheck(Atom head, List<Literal> body, boolean clause) {
        TreeMap<String, Integer> arities = new TreeMap<>();
        for (var e : state.predicates.entrySet()) arities.put(e.getKey(), e.getValue().arity);
        for (Atom a : atoms(head, body)) {
            Integer expected = arities.get(a.name);
            if (expected == null && !clause) fail("unknown predicate " + a.name);
            if (expected != null && expected != a.terms.size()) fail("arity mismatch for " + a.name + ": expected " + expected + ", got " + a.terms.size());
            arities.put(a.name, a.terms.size());
        }
        return arities;
    }

    static void safety(Atom head, List<Literal> body, String aggregateVariable) {
        if (head != null) for (Term t : head.terms) if (t.anonymous) fail("anonymous variable in head");
        for (Literal l : body) if (l.atom == null) for (Term t : l.terms()) if (t.anonymous) fail("anonymous variable in comparison");
        Set<String> bound = new HashSet<>();
        for (Literal l : body) if (l.atom != null && !l.negative) bound.addAll(variables(l.atom.terms));
        List<String> needed = new ArrayList<>();
        if (head != null) needed.addAll(variables(head.terms));
        if (aggregateVariable != null) needed.add(aggregateVariable);
        for (Literal l : body) if (l.atom == null || l.negative) needed.addAll(variables(l.terms()));
        for (String name : needed) if (!bound.contains(name)) fail("unsafe variable " + name);
    }

    static Map<String, Integer> strata(Set<String> predicates, List<Rule> rules) {
        Map<String, Integer> result = new TreeMap<>();
        for (String p : predicates) result.put(p, 0);
        for (int pass = 0; pass < predicates.size(); pass++) {
            boolean changed = false;
            for (Rule r : rules) if (r.head != null) for (Literal l : r.body) if (l.atom != null) {
                int value = result.get(l.atom.name) + (l.negative ? 1 : 0);
                if (result.get(r.head.name) < value) {
                    result.put(r.head.name, value);
                    changed = true;
                }
            }
            if (!changed) return result;
            if (pass + 1 == predicates.size()) return null;
        }
        return result;
    }

    void snapshot(int line) {
        history.add(new History(state.copy(), line));
    }

    static Map<String, Value> match(Atom atom, Tuple tuple, Map<String, Value> original) {
        Map<String, Value> env = new HashMap<>(original);
        for (int i = 0; i < atom.terms.size(); i++) {
            Term t = atom.terms.get(i);
            Value value = tuple.values.get(i);
            if (t.anonymous) continue;
            if (t.value != null) {
                if (!t.value.equals(value)) return null;
            } else {
                Value old = env.putIfAbsent(t.variable, value);
                if (old != null && !old.equals(value)) return null;
            }
        }
        return env;
    }

    static Tuple key(List<String> vars, Map<String, Value> env) {
        return new Tuple(vars.stream().map(env::get).toList());
    }

    static boolean filters(List<Literal> body, Model model, Map<String, Value> env, boolean complete) {
        for (Literal l : body) if (l.atom == null || l.negative) {
            if (!complete && !env.keySet().containsAll(variables(l.terms()))) continue;
            if (l.atom == null) {
                if (!l.comparison(env)) return false;
            } else for (Tuple tuple : model.tuples.get(l.atom.name).keySet()) if (match(l.atom, tuple, env) != null) return false;
        }
        return true;
    }

    static void visitSolutions(List<Literal> body, List<Literal> positive, int at,
                               Model model, int before, Map<String, Value> env,
                               List<String> variables, TreeMap<Tuple, Map<String, Value>> output) {
        if (!filters(body, model, env, at == positive.size())) return;
        if (at == positive.size()) {
            output.putIfAbsent(key(variables, env), env);
            return;
        }
        Atom atom = positive.get(at).atom;
        List<String> names = variables(atom.terms);
        TreeSet<Tuple> seen = new TreeSet<>();
        for (var entry : model.tuples.get(atom.name).entrySet()) {
            if (before >= 0 && entry.getValue().round >= before) continue;
            Map<String, Value> candidate = match(atom, entry.getKey(), env);
            if (candidate != null && seen.add(key(names, candidate))) {
                visitSolutions(body, positive, at + 1, model, before, candidate, variables, output);
            }
        }
    }

    static List<Map<String, Value>> solutions(List<Literal> body, Model model, int before) {
        List<Literal> positive = new ArrayList<>(body.stream().filter(l -> l.atom != null && !l.negative).toList());
        positive.sort((a, b) -> Integer.compare(model.tuples.get(a.atom.name).size(), model.tuples.get(b.atom.name).size()));
        List<String> variables = variables(bodyTerms(body));
        TreeMap<Tuple, Map<String, Value>> output = new TreeMap<>();
        visitSolutions(body, positive, 0, model, before, new HashMap<>(), variables, output);
        return new ArrayList<>(output.values());
    }

    Model model() {
        Map<String, Integer> levels = strata(state.predicates.keySet(), state.rules);
        int maximum = levels.values().stream().mapToInt(Integer::intValue).max().orElse(-1);
        Model model = new Model();
        model.rounds = new int[maximum + 1];
        model.added = new int[maximum + 1];
        for (var e : state.predicates.entrySet()) {
            TreeMap<Tuple, Derivation> tuples = new TreeMap<>();
            for (Tuple t : e.getValue().facts) tuples.put(t, new Derivation(0, 0));
            model.tuples.put(e.getKey(), tuples);
        }
        int serial = 0;
        for (int level = 0; level <= maximum; level++) while (true) {
            TreeMap<String, TreeMap<Tuple, Integer>> staged = new TreeMap<>();
            for (Rule r : state.rules) if (r.head != null && levels.get(r.head.name) == level) {
                for (Map<String, Value> env : solutions(r.body, model, -1)) {
                    Tuple t = r.head.tuple(env);
                    if (!model.tuples.get(r.head.name).containsKey(t)) staged.computeIfAbsent(r.head.name, x -> new TreeMap<>()).merge(t, r.number, Math::min);
                }
            }
            if (staged.isEmpty()) break;
            serial++;
            model.rounds[level]++;
            for (var p : staged.entrySet()) for (var t : p.getValue().entrySet()) {
                model.tuples.get(p.getKey()).put(t.getKey(), new Derivation(serial, t.getValue()));
                model.added[level]++;
            }
        }
        return model;
    }

    static String tupleText(String predicate, Tuple tuple) {
        return predicate + (tuple.values.isEmpty() ? "" : "(" + String.join(", ", tuple.values.stream().map(Value::toString).toList()) + ")");
    }

    static List<String> answerLines(List<String> vars, List<Map<String, Value>> answers, String prefix) {
        List<String> out = new ArrayList<>();
        for (Map<String, Value> env : answers) out.add(prefix + String.join(", ", vars.stream().map(v -> v + " = " + env.get(v)).toList()));
        return out;
    }

    void proof(String predicate, Tuple tuple, Model model, int depth, List<String> out) {
        String prefix = "  ".repeat(depth) + tupleText(predicate, tuple);
        Derivation derivation = model.tuples.get(predicate).get(tuple);
        if (derivation.round == 0) {
            out.add(prefix + " [fact]");
            return;
        }
        for (Rule r : state.rules) if (r.head != null && r.head.name.equals(predicate)) {
            List<String> vars = variables(r.terms());
            TreeMap<Tuple, Map<String, Value>> choices = new TreeMap<>();
            for (Map<String, Value> env : solutions(r.body, model, derivation.round)) if (r.head.tuple(env).equals(tuple)) choices.put(key(vars, env), env);
            if (choices.isEmpty()) continue;
            Map<String, Value> env = choices.firstEntry().getValue();
            out.add(prefix + " [rule " + r.number + "]");
            for (Literal l : r.body) {
                if (l.atom != null && !l.negative) {
                    for (var t : model.tuples.get(l.atom.name).entrySet()) if (t.getValue().round < derivation.round && match(l.atom, t.getKey(), env) != null) {
                        proof(l.atom.name, t.getKey(), model, depth + 1, out);
                        break;
                    }
                } else out.add("  ".repeat(depth + 1) + l.text(env));
            }
            return;
        }
    }

    List<String> process(Statement s, int line) {
        List<String> out = new ArrayList<>();
        if (s.kind.equals("fact") || s.kind.equals("rule")) {
            TreeMap<String, Integer> arities = predicateCheck(s.atom, s.body, true);
            safety(s.atom, s.body, null);
            Rule rule = new Rule(nextRule, s.atom, s.body);
            if (s.kind.equals("rule")) {
                for (Rule old : state.rules) if (old.text().equals(rule.text())) fail("duplicate of rule " + old.number);
                List<Rule> trial = new ArrayList<>(state.rules);
                trial.add(rule);
                if (s.atom != null && strata(arities.keySet(), trial) == null) fail("negative cycle through " + s.atom.name);
            } else if (state.predicates.containsKey(s.atom.name) && state.predicates.get(s.atom.name).facts.contains(s.atom.tuple(Map.of()))) return out;
            snapshot(line);
            for (var e : arities.entrySet()) state.predicates.computeIfAbsent(e.getKey(), n -> new Predicate(e.getValue()));
            if (s.kind.equals("fact")) state.predicates.get(s.atom.name).facts.add(s.atom.tuple(Map.of()));
            else {
                state.rules.add(rule);
                nextRule++;
                Map<String, Integer> counts = new LinkedHashMap<>();
                for (Term t : rule.terms()) if (t.variable != null) counts.merge(t.variable, 1, Integer::sum);
                for (var e : counts.entrySet()) if (e.getValue() == 1) out.add("WARNING line " + line + ": singleton variable " + e.getKey());
            }
            return out;
        }
        if (s.kind.equals("undo")) {
            if (history.isEmpty()) fail("nothing to undo");
            History h = history.removeLast();
            state = h.state;
            return List.of("undid line " + h.line);
        }
        if (s.kind.equals("forget")) {
            Rule rule = state.rules.stream().filter(r -> r.number == s.number).findFirst().orElse(null);
            if (rule == null) fail("no rule " + s.number);
            snapshot(line);
            state.rules.remove(rule);
            return out;
        }
        if (s.kind.equals("retract") || s.kind.equals("why")) predicateCheck(s.atom, List.of(), false);
        if (s.kind.equals("retract")) {
            List<Tuple> removed = state.predicates.get(s.atom.name).facts.stream().filter(t -> match(s.atom, t, Map.of()) != null).toList();
            if (removed.isEmpty()) fail("no matching facts");
            snapshot(line);
            state.predicates.get(s.atom.name).facts.removeAll(removed);
            return List.of(removed.size() + (removed.size() == 1 ? " fact retracted" : " facts retracted"));
        }
        if (s.kind.equals("listing") || s.kind.equals("dump")) {
            if (s.name != null && !state.predicates.containsKey(s.name)) fail("unknown predicate " + s.name);
            if (s.kind.equals("listing")) {
                for (Rule r : state.rules) if (s.name == null || r.head != null && r.head.name.equals(s.name)) out.add(r.number + ": " + r.text());
                return out.isEmpty() ? List.of("no rules") : out;
            }
        }
        if (s.kind.equals("query")) {
            predicateCheck(null, s.body, false);
            safety(null, s.body, s.variable);
        }
        if (s.kind.equals("why")) for (Term t : s.atom.terms) if (t.value == null) fail("why needs a ground atom");
        Map<String, Integer> levels = strata(state.predicates.keySet(), state.rules);
        if (s.kind.equals("strata")) {
            if (levels.isEmpty()) return List.of("no predicates");
            List<String> names = new ArrayList<>(state.predicates.keySet());
            int n = names.size();
            boolean[][] reach = new boolean[n][n];
            for (Rule r : state.rules) if (r.head != null) for (Literal l : r.body) if (l.atom != null) reach[names.indexOf(r.head.name)][names.indexOf(l.atom.name)] = true;
            for (int k = 0; k < n; k++) for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) reach[i][j] |= reach[i][k] && reach[k][j];
            int maximum = levels.values().stream().mapToInt(Integer::intValue).max().orElse(0);
            for (int k = 0; k <= maximum; k++) {
                List<String> row = new ArrayList<>();
                for (int i = 0; i < n; i++) if (levels.get(names.get(i)) == k) row.add(names.get(i) + (reach[i][i] ? "*" : ""));
                out.add("stratum " + k + ": " + String.join(", ", row));
            }
            return out;
        }
        Model model = model();
        switch (s.kind) {
            case "query" -> {
                List<Map<String, Value>> answers = solutions(s.body, model, -1);
                List<String> vars = variables(bodyTerms(s.body));
                if (s.aggregate.equals("count")) out.add(Integer.toString(answers.size()));
                else if (s.aggregate.equals("sum")) {
                    long total = 0;
                    for (var env : answers) {
                        Value v = env.get(s.variable);
                        if (!v.integer) fail("non-integer value in sum");
                        total += v.number;
                    }
                    out.add(Long.toString(total));
                } else if (s.aggregate.equals("min") || s.aggregate.equals("max")) {
                    Value best = null;
                    for (var env : answers) {
                        Value v = env.get(s.variable);
                        if (best == null || (s.aggregate.equals("min") ? v.compareTo(best) < 0 : v.compareTo(best) > 0)) best = v;
                    }
                    out.add(best == null ? "no answers" : best.toString());
                } else if (vars.isEmpty()) out.add(answers.isEmpty() ? "false." : "true.");
                else {
                    out.addAll(answerLines(vars, answers, ""));
                    out.add(answers.size() + (answers.size() == 1 ? " answer" : " answers"));
                }
            }
            case "dump" -> {
                for (Tuple t : model.tuples.get(s.name).keySet()) out.add(tupleText(s.name, t) + ".");
                int count = model.tuples.get(s.name).size();
                out.add(count + (count == 1 ? " tuple" : " tuples"));
            }
            case "why" -> {
                Tuple t = s.atom.tuple(Map.of());
                if (!model.tuples.get(s.atom.name).containsKey(t)) out.add("false.");
                else proof(s.atom.name, t, model, 0, out);
            }
            case "check" -> {
                for (Rule r : state.rules) if (r.head == null) {
                    List<Map<String, Value>> answers = solutions(r.body, model, -1);
                    List<String> vars = variables(bodyTerms(r.body));
                    out.add("constraint " + r.number + ": " + (answers.isEmpty() ? "ok" : answers.size() + (answers.size() == 1 ? " violation" : " violations")));
                    if (!vars.isEmpty()) out.addAll(answerLines(vars, answers, "  "));
                }
                if (out.isEmpty()) out.add("no constraints");
            }
            case "predicates" -> {
                for (var e : state.predicates.entrySet()) {
                    long rules = state.rules.stream().filter(r -> r.head != null && r.head.name.equals(e.getKey())).count();
                    out.add(e.getKey() + "/" + e.getValue().arity + ": facts " + e.getValue().facts.size() + ", rules " + rules + ", tuples " + model.tuples.get(e.getKey()).size());
                }
                if (out.isEmpty()) out.add("no predicates");
            }
            case "stats" -> {
                int facts = state.predicates.values().stream().mapToInt(p -> p.facts.size()).sum(), tuples = model.tuples.values().stream().mapToInt(Map::size).sum();
                long rules = state.rules.stream().filter(r -> r.head != null).count();
                out.add("facts " + facts + ", rules " + rules + ", constraints " + (state.rules.size() - rules) + ", tuples " + tuples);
                for (int k = 0; k < model.rounds.length; k++) out.add("stratum " + k + ": rounds " + model.rounds[k] + ", new " + model.added[k]);
                for (Rule r : state.rules) if (r.head != null) {
                    long count = model.tuples.get(r.head.name).values().stream().filter(d -> d.rule == r.number).count();
                    out.add("rule " + r.number + ": new " + count);
                }
            }
            default -> throw new IllegalStateException();
        }
        return out;
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main engine = new Main();
        String line;
        int number = 0;
        while ((line = reader.readLine()) != null) {
            number++;
            try {
                Parser parser = new Parser(line);
                if (parser.is("end")) continue;
                Statement statement = parser.statement();
                if (statement.kind.equals("halt")) break;
                for (String output : engine.process(statement, number)) System.out.println(output);
            } catch (Problem error) {
                System.out.println("ERROR line " + number + ": " + error.getMessage());
            }
        }
    }
}
