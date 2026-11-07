import java.util.*;
final class Expressions {
    sealed interface Expr permits Literal, Reference, Current, Operation {}
    record Literal(Object value) implements Expr {}
    record Reference(String name) implements Expr {}
    record Current() implements Expr {}
    record Operation(String name, List<Expr> arguments) implements Expr {}
    static List<String> lex(String text) {
        List<String> tokens = new ArrayList<>();
        for (int i = 0; i < text.length();) {
            char c = text.charAt(i);
            if (c == ' ') {
                i++;
                continue;
            }
            int start = i++;
            if (c == '"') {
                while (text.charAt(i) != '"')
                    i++;
                i++;
            } else if (c >= '0' && c <= '9') {
                while (i < text.length() && text.charAt(i) >= '0' && text.charAt(i) <= '9')
                    i++;
            } else if (c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z') {
                while (i < text.length()) {
                    char n = text.charAt(i);
                    if (!(n >= 'A' && n <= 'Z' || n >= 'a' && n <= 'z' || n >= '0' && n <= '9' ||
                          n == '_' || n == '.'))
                        break;
                    i++;
                }
            } else if (i < text.length() && text.charAt(i) == '=' && "=!<>".indexOf(c) >= 0)
                i++;
            tokens.add(text.substring(start, i));
        }
        return tokens;
    }
    static final class Parser {
        List<String> tokens;
        int position;
        Parser(String text) { tokens = lex(text); }
        String peek() { return position < tokens.size() ? tokens.get(position) : ""; }
        String take() { return tokens.get(position++); }
        Expr disjunction() {
            Expr tree = conjunction();
            while (peek().equals("or")) {
                String op = take();
                tree = new Operation(op, List.of(tree, conjunction()));
            }
            return tree;
        }
        Expr conjunction() {
            Expr tree = negation();
            while (peek().equals("and")) {
                String op = take();
                tree = new Operation(op, List.of(tree, negation()));
            }
            return tree;
        }
        Expr negation() {
            if (peek().equals("not")) {
                take();
                return new Operation("not", List.of(negation()));
            }
            return comparison();
        }
        Expr comparison() {
            Expr tree = sum();
            if (Set.of("==", "!=", "<", "<=", ">", ">=", "in").contains(peek())) {
                String op = take();
                tree = new Operation(op, List.of(tree, sum()));
            }
            return tree;
        }
        Expr sum() {
            Expr tree = product();
            while (peek().equals("+") || peek().equals("-")) {
                String op = take();
                tree = new Operation(op, List.of(tree, product()));
            }
            return tree;
        }
        Expr product() {
            Expr tree = unary();
            while (peek().equals("*")) {
                String op = take();
                tree = new Operation(op, List.of(tree, unary()));
            }
            return tree;
        }
        Expr unary() {
            if (peek().equals("-")) {
                take();
                return new Operation("-", List.of(unary()));
            }
            return primary();
        }
        Expr primary() {
            String token = take();
            if (token.charAt(0) >= '0' && token.charAt(0) <= '9')
                return new Literal(Integer.parseInt(token));
            if (token.startsWith("\""))
                return new Literal(token.substring(1, token.length() - 1));
            if (token.equals("true") || token.equals("false"))
                return new Literal(token.equals("true"));
            if (token.equals("it"))
                return new Current();
            if (token.contains("."))
                return new Reference(token);
            if (token.equals("(")) {
                Expr tree = disjunction();
                take();
                return tree;
            }
            if (token.equals("[")) {
                List<String> values = new ArrayList<>();
                while (!peek().equals("]")) {
                    String value = take();
                    values.add(value.substring(1, value.length() - 1));
                    if (!peek().equals("]"))
                        take();
                }
                take();
                return new Literal(List.copyOf(values));
            }
            take();
            List<Expr> arguments = new ArrayList<>();
            while (!peek().equals(")")) {
                arguments.add(disjunction());
                if (!peek().equals(")"))
                    take();
            }
            take();
            return new Operation(token, arguments);
        }
    }
    static Expr parse(String text) { return new Parser(text).disjunction(); }
}
