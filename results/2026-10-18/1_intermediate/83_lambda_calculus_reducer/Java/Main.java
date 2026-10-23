import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String reason) {
            super("error: " + reason);
        }
    }

    static void fail(String reason) {
        throw new Problem(reason);
    }

    record Term(char kind, String name, int number, Term left, Term right) { }

    static Term variable(String name) {
        return new Term('v', name, 0, null, null);
    }

    static Term constant(String name) {
        return new Term('c', name, 0, null, null);
    }

    static Term abstraction(String name, Term body) {
        return new Term('a', name, 0, body, null);
    }

    static Term application(Term function, Term argument) {
        return new Term('p', "", 0, function, argument);
    }

    record Token(String kind, String text, int column) { }

    static boolean lower(char c) {
        return c >= 'a' && c <= 'z';
    }

    static boolean upper(char c) {
        return c >= 'A' && c <= 'Z';
    }

    static boolean digit(char c) {
        return c >= '0' && c <= '9';
    }

    static boolean macroName(String name) {
        if (name.isEmpty() || !upper(name.charAt(0))) return false;
        for (char c : name.toCharArray()) if (!upper(c) && !digit(c) && c != '_') return false;
        return true;
    }

    static class Parser {
        List<Token> tokens = new ArrayList<>();
        int at;
        Parser(String line, int start) {
            for (int i = start; i < line.length();) {
                char c = line.charAt(i);
                if (c == ' ') {
                    i++;
                    continue;
                }
                int first = i;
                String kind;
                if ("\\.()=;".indexOf(c) >= 0) {
                    kind = Character.toString(c);
                    i++;
                } else if (lower(c)) {
                    kind = "variable";
                    while (i < line.length() && (lower(line.charAt(i)) || digit(line.charAt(i)))) i++;
                } else if (upper(c)) {
                    kind = "macro";
                    while (i < line.length() && (upper(line.charAt(i)) || digit(line.charAt(i)) || line.charAt(i) == '_')) i++;
                } else if (c == '#' && i + 1 < line.length() && digit(line.charAt(i + 1))) {
                    kind = "numeral";
                    i++;
                    while (i < line.length() && digit(line.charAt(i))) i++;
                } else {
                    fail("column " + (i + 1) + ": unexpected character '" + c + "'");
                    return;
                }
                tokens.add(new Token(kind, line.substring(first, i), first + 1));
            }
            tokens.add(new Token("end", "", line.length() + 1));
        }
        Token peek() {
            return tokens.get(at);
        }
        Token expect(String kind) {
            Token token = peek();
            if (!token.kind.equals(kind)) fail("column " + token.column + ": expected " + (kind.equals("macro") ? "macro name" : kind.equals("variable") ? "variable" : "'" + kind + "'"));
            at++;
            return token;
        }
        Term term() {
            List<Term> elements = new ArrayList<>();
            while (Set.of("variable", "macro", "numeral", "(").contains(peek().kind)) elements.add(atom());
            if (peek().kind.equals("\\")) {
                at++;
                List<String> names = new ArrayList<>();
                names.add(expect("variable").text);
                while (peek().kind.equals("variable")) names.add(tokens.get(at++).text);
                expect(".");
                Term body = term();
                for (int i = names.size() - 1; i >= 0; i--) body = abstraction(names.get(i), body);
                elements.add(body);
            }
            if (elements.isEmpty()) fail("column " + peek().column + ": expected term");
            Term result = elements.getFirst();
            for (int i = 1; i < elements.size(); i++) result = application(result, elements.get(i));
            return result;
        }
        Term atom() {
            Token token = tokens.get(at++);
            return switch (token.kind) {
                case "variable" -> variable(token.text);
                case "macro" -> new Term('m', token.text, 0, null, null);
                case "numeral" -> new Term('n', "", Integer.parseInt(token.text.substring(1)), null, null);
                default -> {
                    Term body = term();
                    expect(")");
                    yield body;
                }
            };
        }
        void end() {
            if (!peek().kind.equals("end")) fail("column " + peek().column + ": unexpected '" + peek().text + "'");
        }
    }

    static String print(Term term) {
        return print(term, true);
    }

    static String print(Term term, boolean end) {
        if (term.kind == 'n') return "#" + term.number;
        if (term.kind == 'd') return Integer.toString(term.number);
        if (term.kind != 'a' && term.kind != 'p') return term.name;
        if (term.kind == 'a') {
            List<String> names = new ArrayList<>();
            Term body = term;
            while (body.kind == 'a') {
                names.add(body.name);
                body = body.left;
            }
            String text = term.name.isEmpty() ? "\\".repeat(names.size()) + print(body, true) : "\\" + String.join(" ", names) + ". " + print(body, true);
            return end ? text : "(" + text + ")";
        }
        String left = term.left.kind == 'a' ? "(" + print(term.left, true) + ")" : print(term.left, false);
        String right = term.right.kind == 'p' ? "(" + print(term.right, true) + ")" : print(term.right, end);
        return left + " " + right;
    }

    static Set<String> free(Term term) {
        Set<String> result = new TreeSet<>();
        if (term.kind == 'v') result.add(term.name);
        else if (term.kind == 'a') {
            result.addAll(free(term.left));
            result.remove(term.name);
        } else if (term.kind == 'p') {
            result.addAll(free(term.left));
            result.addAll(free(term.right));
        }
        return result;
    }

    static void references(Term term, List<String> result) {
        if (term.kind == 'm') result.add(term.name);
        else {
            if (term.left != null) references(term.left, result);
            if (term.right != null) references(term.right, result);
        }
    }

    static Term substitute(Term term, String name, Term value) {
        if (term.kind == 'v') return term.name.equals(name) ? value : term;
        if (term.kind == 'p') return application(substitute(term.left, name, value), substitute(term.right, name, value));
        String bound = term.name;
        Set<String> bodyFree = free(term.left);
        if (bound.equals(name) || !bodyFree.contains(name)) return term;
        Set<String> valueFree = free(value);
        if (!valueFree.contains(bound)) return abstraction(bound, substitute(term.left, name, value));
        int end = bound.length();
        while (end > 0 && digit(bound.charAt(end - 1))) end--;
        String base = bound.substring(0, end), fresh;
        int index = 1;
        do {
            fresh = base + index++;
        }
        while (bodyFree.contains(fresh) || valueFree.contains(fresh));
        return abstraction(fresh, substitute(substitute(term.left, bound, variable(fresh)), name, value));
    }

    static String sequence(int index) {
        return Character.toString((char)('a' + index % 26)) + (index < 26 ? "" : Integer.toString(index / 26));
    }

    record Binding(String oldName, String newName) { }

    static Term canonical(Term term) {
        return rename(term, free(term), new int[]{0}, new ArrayList<>());
    }

    static Term rename(Term term, Set<String> free, int[] index, List<Binding> bindings) {
        if (term.kind == 'v') {
            for (int i = bindings.size() - 1; i >= 0; i--) if (bindings.get(i).oldName.equals(term.name)) return variable(bindings.get(i).newName);
            return term;
        }
        if (term.kind == 'p') return application(rename(term.left, free, index, bindings), rename(term.right, free, index, bindings));
        String name;
        do {
            name = sequence(index[0]++);
        }
        while (free.contains(name));
        bindings.add(new Binding(term.name, name));
        Term body = rename(term.left, free, index, bindings);
        bindings.removeLast();
        return abstraction(name, body);
    }

    static Term debruijn(Term term) {
        return debruijn(term, new ArrayList<>());
    }

    static Term debruijn(Term term, List<String> bindings) {
        if (term.kind == 'v') {
            for (int i = bindings.size() - 1; i >= 0; i--) if (bindings.get(i).equals(term.name)) return new Term('d', "", bindings.size() - 1 - i, null, null);
            return term;
        }
        if (term.kind == 'p') return application(debruijn(term.left, bindings), debruijn(term.right, bindings));
        bindings.add(term.name);
        Term body = debruijn(term.left, bindings);
        bindings.removeLast();
        return abstraction("", body);
    }

    static boolean same(Term a, Term b) {
        if (a.kind != b.kind) return false;
        return switch (a.kind) {
            case 'v', 'c', 'm' -> a.name.equals(b.name);
            case 'd', 'n' -> a.number == b.number;
            case 'a' -> same(a.left, b.left);
            default -> same(a.left, b.left) && same(a.right, b.right);
        };
    }

    record Step(Term term, String kind) { }

    static boolean etaRedex(Term term) {
        return term.kind == 'a' && term.left.kind == 'p' && term.left.right.kind == 'v' && term.left.right.name.equals(term.name) && !free(term.left.left).contains(term.name);
    }

    static Step step(Term term, String strategy, boolean eta) {
        boolean normal = strategy.equals("NORMAL"), applicative = strategy.equals("APPLICATIVE"), cbn = strategy.equals("CBN");
        if (term.kind == 'v') return null;
        if (term.kind == 'a') {
            if (!normal && !applicative) return null;
            if (normal && eta && etaRedex(term)) return new Step(term.left.left, "eta");
            Step body = step(term.left, strategy, eta);
            if (body != null) return new Step(abstraction(term.name, body.term), body.kind);
            return eta && etaRedex(term) ? new Step(term.left.left, "eta") : null;
        }
        if ((normal || cbn) && term.left.kind == 'a') return new Step(substitute(term.left.left, term.left.name, term.right), "beta");
        Step left = step(term.left, strategy, eta);
        if (left != null) return new Step(application(left.term, term.right), left.kind);
        if (cbn) return null;
        Step right = step(term.right, strategy, eta);
        if (right != null) return new Step(application(term.left, right.term), right.kind);
        return term.left.kind == 'a' && (applicative || normal || term.right.kind == 'v' || term.right.kind == 'a') ? new Step(substitute(term.left.left, term.left.name, term.right), "beta") : null;
    }

    record Reduced(Term term, int count, boolean success) { }

    final TreeMap<String, Term> macros = new TreeMap<>();
    boolean display, eta;
    int limit = 10000;
    Main() {
        Term x = variable("x"), y = variable("y"), z = variable("z");
        macros.put("I", abstraction("x", x));
        macros.put("K", abstraction("x", abstraction("y", x)));
        macros.put("S", abstraction("x", abstraction("y", abstraction("z", application(application(x, z), application(y, z))))));
    }

    Term expand(Term term) {
        return switch (term.kind) {
            case 'v' -> term;
            case 'm' -> {
                if (!macros.containsKey(term.name)) fail("unbound macro " + term.name);
                yield expand(macros.get(term.name));
            }
            case 'n' -> {
                Term body = variable("x");
                for (int i = 0; i < term.number; i++) body = application(variable("f"), body);
                yield abstraction("f", abstraction("x", body));
            }
            case 'a' -> abstraction(term.name, expand(term.left));
            default -> application(expand(term.left), expand(term.right));
        };
    }

    boolean depends(String from, String on) {
        return depends(from, on, new HashSet<>());
    }

    boolean depends(String from, String on, Set<String> seen) {
        Term term = macros.get(from);
        if (term == null || !seen.add(from)) return false;
        List<String> refs = new ArrayList<>();
        references(term, refs);
        for (String ref : refs) if (ref.equals(on) || depends(ref, on, seen)) return true;
        return false;
    }

    Reduced reduce(Term term, String strategy, boolean useEta, boolean show, boolean ski) {
        int count = 0;
        while (true) {
            Step next = ski ? skiStep(term) : step(term, strategy, useEta);
            if (next == null) return new Reduced(term, count, true);
            if (count == limit) return new Reduced(term, count, false);
            term = next.term;
            count++;
            if (show) System.out.println("step " + count + " (" + next.kind + "): " + print(term));
        }
    }

    String failure() {
        return "no normal form within " + limit + " steps";
    }

    static int size(Term term) {
        return term.kind == 'v' ? 1 : term.kind == 'a' ? 1 + size(term.left) : 1 + size(term.left) + size(term.right);
    }

    static int depth(Term term) {
        return term.kind == 'v' ? 1 : term.kind == 'a' ? 1 + depth(term.left) : 1 + Math.max(depth(term.left), depth(term.right));
    }

    static class Type {
        int variable;
        Type left, right, link;
        Type(int variable) {
            this.variable = variable;
        }
        Type(Type left, Type right) {
            variable = -1;
            this.left = left;
            this.right = right;
        }
    }

    static class Untypable extends RuntimeException { }

    static Type resolved(Type type) {
        Type end = type;
        while (end.link != null) end = end.link;
        while (type.link != null) {
            Type next = type.link;
            type.link = end;
            type = next;
        }
        return end;
    }

    static boolean occurs(Type variable, Type in) {
        in = resolved(in);
        return in == variable || in.variable < 0 && (occurs(variable, in.left) || occurs(variable, in.right));
    }

    static void unify(Type a, Type b) {
        a = resolved(a);
        b = resolved(b);
        if (a == b) return;
        if (a.variable >= 0) {
            if (occurs(a, b)) throw new Untypable();
            a.link = b;
        } else if (b.variable >= 0) unify(b, a);
        else {
            unify(a.left, b.left);
            unify(a.right, b.right);
        }
    }

    record TypedBinding(String name, Type type) { }

    static Type infer(Term term, List<TypedBinding> bindings, Map<String, Type> free, int[] next) {
        if (term.kind == 'v') {
            for (int i = bindings.size() - 1; i >= 0; i--) if (bindings.get(i).name.equals(term.name)) return bindings.get(i).type;
            return free.computeIfAbsent(term.name, name -> new Type(next[0]++));
        }
        if (term.kind == 'a') {
            Type parameter = new Type(next[0]++);
            bindings.add(new TypedBinding(term.name, parameter));
            Type body = infer(term.left, bindings, free, next);
            bindings.removeLast();
            return new Type(parameter, body);
        }
        Type function = infer(term.left, bindings, free, next), argument = infer(term.right, bindings, free, next), result = new Type(next[0]++);
        unify(function, new Type(argument, result));
        return result;
    }

    static String printType(Type type, Map<Integer, String> names) {
        type = resolved(type);
        if (type.variable >= 0) return names.computeIfAbsent(type.variable, id -> sequence(names.size()));
        Type left = resolved(type.left);
        String argument = printType(left, names);
        return (left.variable < 0 ? "(" + argument + ")" : argument) + " -> " + printType(type.right, names);
    }

    static String church(Term term) {
        if (term.kind == 'a' && term.left.kind == 'a') {
            String f = term.name, x = term.left.name;
            Term body = term.left.left;
            int count = 0;
            while (body.kind == 'p' && body.left.kind == 'v' && body.left.name.equals(f)) {
                count++;
                body = body.right;
            }
            if (body.kind == 'v' && body.name.equals(x)) return Integer.toString(count);
            if (term.left.left.kind == 'v' && term.left.left.name.equals(f)) return "true";
        }
        if (term.kind == 'a' && term.left.kind == 'p' && term.left.left.kind == 'p' && term.left.left.left.kind == 'v' && term.left.left.left.name.equals(term.name)) {
            Term p = term.left.left.right, q = term.left.right;
            if (!free(p).contains(term.name) && !free(q).contains(term.name)) return "(" + church(p) + ", " + church(q) + ")";
        }
        return print(canonical(term));
    }

    static Term abstractSki(String name, Term term) {
        if (!free(term).contains(name)) return application(constant("K"), term);
        if (term.kind == 'v' && term.name.equals(name)) return constant("I");
        if (term.kind == 'p' && term.right.kind == 'v' && term.right.name.equals(name) && !free(term.left).contains(name)) return term.left;
        return application(application(constant("S"), abstractSki(name, term.left)), abstractSki(name, term.right));
    }

    static Term ski(Term term) {
        return term.kind == 'v' ? term : term.kind == 'a' ? abstractSki(term.name, ski(term.left)) : application(ski(term.left), ski(term.right));
    }

    static Term apply(Term head, List<Term> arguments, int from) {
        for (int i = from; i < arguments.size(); i++) head = application(head, arguments.get(i));
        return head;
    }

    static Step skiStep(Term term) {
        List<Term> args = new ArrayList<>();
        Term head = term;
        while (head.kind == 'p') {
            args.add(0, head.right);
            head = head.left;
        }
        if (head.kind == 'c') {
            if (head.name.equals("I") && !args.isEmpty()) return new Step(apply(args.get(0), args, 1), "I");
            if (head.name.equals("K") && args.size() >= 2) return new Step(apply(args.get(0), args, 2), "K");
            if (head.name.equals("S") && args.size() >= 3) return new Step(apply(application(application(args.get(0), args.get(2)), application(args.get(1), args.get(2))), args, 3), "S");
        }
        for (int i = 0; i < args.size(); i++) {
            Step next = skiStep(args.get(i));
            if (next != null) {
                args.set(i, next.term);
                return new Step(apply(head, args, 0), next.kind);
            }
        }
        return null;
    }

    record Closure(Term term, List<Closure> environment) { }

    static Term realize(Term code, List<Closure> environment, int depth) {
        while (code.kind == 'd' && code.number >= depth) {
            Closure closure = environment.get(code.number - depth);
            code = closure.term;
            environment = closure.environment;
            depth = 0;
        }
        if (code.kind == 'v' || code.kind == 'd') return code;
        if (code.kind == 'a') return abstraction("", realize(code.left, environment, depth + 1));
        return application(realize(code.left, environment, depth), realize(code.right, environment, depth));
    }

    static Term fromDebruijn(Term term, Set<String> free, List<String> bindings, int[] next) {
        if (term.kind == 'v') return term;
        if (term.kind == 'd') return variable(bindings.get(bindings.size() - 1 - term.number));
        if (term.kind == 'p') return application(fromDebruijn(term.left, free, bindings, next), fromDebruijn(term.right, free, bindings, next));
        String name;
        do {
            name = sequence(next[0]++);
        }
        while (free.contains(name));
        bindings.add(name);
        Term body = fromDebruijn(term.left, free, bindings, next);
        bindings.removeLast();
        return abstraction(name, body);
    }

    void kam(Term term) {
        Term code = debruijn(term);
        List<Closure> environment = List.of(), stack = new ArrayList<>();
        int count = 0;
        while (true) {
            String kind = code.kind == 'p' ? "push" : code.kind == 'a' && !stack.isEmpty() ? "grab" : code.kind == 'd' ? "access" : "";
            if (kind.isEmpty()) break;
            if (count == limit) {
                System.out.println("no result within " + limit + " transitions");
                return;
            }
            if (kind.equals("push")) {
                stack.add(new Closure(code.right, environment));
                code = code.left;
            } else if (kind.equals("grab")) {
                List<Closure> next = new ArrayList<>();
                next.add(stack.removeLast());
                next.addAll(environment);
                environment = next;
                code = code.left;
            } else {
                Closure closure = environment.get(code.number);
                code = closure.term;
                environment = closure.environment;
            }
            count++;
            if (display) System.out.println("step " + count + " (" + kind + "): " + print(code) + " [env " + environment.size() + ", stack " + stack.size() + "]");
        }
        Term result = realize(code, environment, 0);
        for (int i = stack.size() - 1; i >= 0; i--) result = application(result, realize(stack.get(i).term, stack.get(i).environment, 0));
        result = fromDebruijn(result, free(result), new ArrayList<>(), new int[]{0});
        System.out.println("result: " + print(result) + " (transitions: " + count + ")");
    }

    void command(String line) {
        int split = line.indexOf(' ');
        String command = split < 0 ? line : line.substring(0, split), argument = split < 0 ? "" : line.substring(split + 1);
        if (!Set.of("let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam").contains(command)) fail("unknown command " + command);
        Set<String> reserved = Set.of("S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV");
        if (Set.of("unlet", "macros", "steps", "eta", "limit").contains(command)) {
            String stripped = argument.strip();
            String[] words = stripped.isEmpty() ? new String[0] : stripped.split(" +");
            switch (command) {
                case "steps", "eta" -> {
                    if (words.length != 1 || !(words[0].equals("on") || words[0].equals("off"))) fail("bad argument");
                    if (command.equals("steps")) display = words[0].equals("on");
                    else eta = words[0].equals("on");
                }
                case "limit" -> {
                    if (words.length != 1 || words[0].length() < 1 || words[0].length() > 5 || !words[0].chars().allMatch(c -> c >= '0' && c <= '9')) fail("bad argument");
                    int value = Integer.parseInt(words[0]);
                    if (value < 1 || value > 10000) fail("bad argument");
                    limit = value;
                }
                case "macros" -> {
                    if (words.length != 0) fail("bad argument");
                    boolean any = false;
                    for (Map.Entry<String, Term> entry : macros.entrySet()) if (!Set.of("S", "K", "I").contains(entry.getKey())) {
                        System.out.println(entry.getKey() + " = " + print(entry.getValue()));
                        any = true;
                    }
                    if (!any) System.out.println("(none)");
                }
                case "unlet" -> {
                    if (words.length != 1 || !macroName(words[0])) fail("bad argument");
                    String name = words[0];
                    if (reserved.contains(name)) fail("reserved name " + name);
                    if (!macros.containsKey(name)) fail("unbound macro " + name);
                    for (Map.Entry<String, Term> entry : macros.entrySet()) {
                        List<String> refs = new ArrayList<>();
                        references(entry.getValue(), refs);
                        if (refs.contains(name)) fail(name + " is used by " + entry.getKey());
                    }
                    macros.remove(name);
                    System.out.println("removed " + name);
                }
            }
            return;
        }
        Parser parser = new Parser(line, split < 0 ? line.length() : split + 1);
        String name = null, strategy = "NORMAL";
        Term first, second = null;
        if (command.equals("let")) {
            name = parser.expect("macro").text;
            parser.expect("=");
            first = parser.term();
        } else if (command.equals("subst")) {
            name = parser.expect("variable").text;
            parser.expect("=");
            first = parser.term();
            parser.expect(";");
            second = parser.term();
        } else {
            if (command.equals("reduce") && parser.peek().kind.equals("macro") && Set.of("NORMAL", "APPLICATIVE", "CBN", "CBV").contains(parser.peek().text)) strategy = parser.tokens.get(parser.at++).text;
            first = parser.term();
            if (command.equals("equal") || command.equals("alpha")) {
                parser.expect(";");
                second = parser.term();
            }
        }
        parser.end();
        if (command.equals("let")) {
            if (reserved.contains(name)) fail("reserved name " + name);
            List<String> refs = new ArrayList<>();
            references(first, refs);
            for (String ref : refs) {
                if (ref.equals(name) || depends(ref, name)) fail("recursive definition of " + name);
                if (!macros.containsKey(ref)) fail("unbound macro " + ref);
            }
            Set<String> variables = free(first);
            if (!variables.isEmpty()) fail("free variable " + variables.iterator().next() + " in definition of " + name);
            System.out.println((macros.containsKey(name) ? "redefined " : "defined ") + name);
            macros.put(name, first);
            return;
        }
        first = expand(first);
        if (second != null) second = expand(second);
        switch (command) {
            case "expand" -> System.out.println(print(first));
            case "subst" -> System.out.println(print(substitute(second, name, first)));
            case "debruijn" -> System.out.println(print(debruijn(first)));
            case "fv" -> {
                Set<String> variables = free(first);
                System.out.println(variables.isEmpty() ? "(none)" : String.join(" ", variables));
            }
            case "size" -> System.out.println(size(first));
            case "depth" -> System.out.println(depth(first));
            case "alpha" -> System.out.println(same(debruijn(first), debruijn(second)) ? "yes" : "no");
            case "equal" -> {
                Reduced left = reduce(first, "NORMAL", eta, false, false), right = reduce(second, "NORMAL", eta, false, false);
                System.out.println(!left.success || !right.success ? "unknown" : same(debruijn(left.term), debruijn(right.term)) ? "yes" : "no");
            }
            case "type" -> {
                try {
                    System.out.println(printType(infer(first, new ArrayList<>(), new HashMap<>(), new int[]{0}), new HashMap<>()));
                } catch (Untypable error) {
                    System.out.println("not typable");
                }
            }
            case "church" -> {
                Reduced result = reduce(first, "NORMAL", false, false, false);
                System.out.println(result.success ? church(canonical(result.term)) : failure());
            }
            case "ski" -> System.out.println(print(ski(first)));
            case "kam" -> kam(first);
            case "reduce", "skireduce" -> {
                boolean ski = command.equals("skireduce");
                Reduced result = reduce(ski ? ski(first) : first, strategy, eta, display, ski);
                System.out.println(result.success ? "result: " + print(ski ? result.term : canonical(result.term)) + " (steps: " + result.count + ")" : failure());
            }
            default -> throw new IllegalStateException();
        }
    }
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main workbench = new Main();
        String line;
        while ((line = reader.readLine()) != null && !line.equals("quit")) {
            if (line.isEmpty() || line.startsWith("--")) continue;
            try {
                workbench.command(line);
            } catch (Problem problem) {
                System.out.println(problem.getMessage());
            }
        }
    }
}
