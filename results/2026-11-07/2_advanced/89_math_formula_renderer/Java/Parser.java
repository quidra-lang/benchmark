import java.util.*;
final class Parser {
    sealed interface Node permits Atom, Row, Binary, Radical, Script, Delimited, Matrix, Accent {}
    record Atom(String kind, String value, int column) implements Node {}
    record Row(List<Node> children) implements Node {}
    record Binary(String kind, Node first, Node second) implements Node {}
    record Radical(Node index, Node body) implements Node {}
    record Script(Node base, Node sub, Node sup) implements Node {}
    record Delimited(String left, String right, Node body, int column) implements Node {}
    record Matrix(String environment, List<List<Node>> rows) implements Node {}
    record Accent(String name, Node body) implements Node {}
    static final Set<String> ATOMS = Set.of("identifier", "number", "symbol", "command", "text"),
                             TERMINATORS = Set.of("}", "&", "newline", "right", "end", "eof"),
                             ARGUMENTS = Set.of("identifier", "number", "symbol", "command", "text",
                                                "eqref", "{", "frac", "binom", "overset",
                                                "underset", "sqrt", "accent");
    List<Lexer.Token> tokens;
    int position;
    Lexer.Token tag, label;
    Parser(List<Lexer.Token> tokens) { this.tokens = tokens; }
    static Node collapse(List<Node> nodes) {
        return nodes.size() == 1 ? nodes.getFirst() : new Row(List.copyOf(nodes));
    }
    static void checkBraces(List<Lexer.Token> tokens) {
        Deque<Integer> stack = new ArrayDeque<>();
        for (Lexer.Token token : tokens)
            if (token.kind().equals("{"))
                stack.push(token.column());
            else if (token.kind().equals("}")) {
                if (stack.isEmpty())
                    throw new Lexer.FormulaError(token.column(), "unmatched }");
                stack.pop();
            }
        if (!stack.isEmpty())
            throw new Lexer.FormulaError(stack.peek(), "unclosed {");
    }
    Lexer.Token peek() { return tokens.get(position); }
    Lexer.Token take() {
        Lexer.Token token = peek();
        if (!token.kind().equals("eof"))
            position++;
        return token;
    }
    void unexpected() {
        String message = switch (peek().kind()) {
            case "right" -> "unexpected \\right";
            case "end" -> "unexpected \\end";
            case "&" -> "misplaced &";
            case "newline" -> "misplaced \\\\";
            default -> throw new IllegalStateException();
        };
        throw new Lexer.FormulaError(peek().column(), message);
    }
    List<Node> parse() {
        List<Node> nodes = elements(true, false);
        if (!peek().kind().equals("eof"))
            unexpected();
        return nodes;
    }
    List<Node> elements(boolean top, boolean index) {
        List<Node> nodes = new ArrayList<>();
        while (true) {
            Lexer.Token token = peek();
            if (TERMINATORS.contains(token.kind()) ||
                index && token.kind().equals("symbol") && token.value().equals("]"))
                return nodes;
            if (token.kind().equals("tag") || token.kind().equals("label")) {
                if (!top)
                    throw new Lexer.FormulaError(token.column(), "misplaced \\" + token.kind());
                if ((token.kind().equals("tag") ? tag : label) != null)
                    throw new Lexer.FormulaError(token.column(), "duplicate \\" + token.kind());
                if (token.kind().equals("tag"))
                    tag = take();
                else
                    label = take();
            } else
                nodes.add(element());
        }
    }
    Node element() {
        Node base = Set.of("^", "_").contains(peek().kind()) ? new Row(List.of()) : nucleus(),
             sub = null, sup = null;
        while (Set.of("^", "_").contains(peek().kind())) {
            Lexer.Token token = take();
            if (token.kind().equals("^")) {
                if (sup != null)
                    throw new Lexer.FormulaError(token.column(), "double superscript");
                sup = argument("^");
            } else {
                if (sub != null)
                    throw new Lexer.FormulaError(token.column(), "double subscript");
                sub = argument("_");
            }
        }
        return sub == null && sup == null ? base : new Script(base, sub, sup);
    }
    Node argument(String name) {
        if (!ARGUMENTS.contains(peek().kind()))
            throw new Lexer.FormulaError(peek().column(), "missing argument for " + name);
        return nucleus();
    }
    String delimiter() {
        Lexer.Token token = take();
        if (token.kind().equals("symbol") &&
                Set.of("(", ")", "[", "]", "|", ".").contains(token.value()) ||
            token.kind().equals("command") && Set.of("\\{", "\\}").contains(token.value()))
            return token.value();
        throw new Lexer.FormulaError(token.column(), "invalid delimiter");
    }
    Node nucleus() {
        Lexer.Token token = take();
        String kind = token.kind();
        if (ATOMS.contains(kind))
            return new Atom(kind, token.value(), token.column());
        if (kind.equals("eqref"))
            return new Atom("reference", token.value(), token.column());
        if (kind.equals("{")) {
            List<Node> nodes = elements(false, false);
            if (!peek().kind().equals("}"))
                unexpected();
            take();
            return collapse(nodes);
        }
        if (Set.of("frac", "binom", "overset", "underset").contains(kind)) {
            Node first = argument("\\" + kind), second = argument("\\" + kind);
            return new Binary(kind, first, second);
        }
        if (kind.equals("sqrt")) {
            Node index = null;
            if (peek().kind().equals("symbol") && peek().value().equals("[")) {
                Lexer.Token opening = take();
                List<Node> nodes = elements(false, true);
                if (!peek().kind().equals("symbol") || !peek().value().equals("]"))
                    throw new Lexer.FormulaError(opening.column(), "missing ]");
                take();
                index = collapse(nodes);
            }
            return new Radical(index, argument("\\sqrt"));
        }
        if (kind.equals("accent"))
            return new Accent(token.value(), argument("\\" + token.value()));
        if (kind.equals("left")) {
            String left = delimiter();
            List<Node> nodes = elements(false, false);
            if (!peek().kind().equals("right"))
                throw new Lexer.FormulaError(token.column(), "missing \\right");
            Lexer.Token closing = take();
            String right = delimiter();
            return new Delimited(left, right, collapse(nodes), closing.column());
        }
        return matrix(token.value(), token.column());
    }
    Matrix matrix(String environment, int column) {
        List<List<Node>> rows = new ArrayList<>();
        rows.add(new ArrayList<>());
        while (true) {
            rows.getLast().add(collapse(elements(false, false)));
            Lexer.Token token = take();
            if (token.kind().equals("&"))
                continue;
            if (token.kind().equals("newline")) {
                rows.add(new ArrayList<>());
                continue;
            }
            if (!token.kind().equals("end"))
                throw new Lexer.FormulaError(column, "missing \\end");
            if (!token.value().equals(environment))
                throw new Lexer.FormulaError(token.column(), "mismatched \\end");
            break;
        }
        List<Node> last = rows.getLast();
        if (rows.size() >= 2 && last.size() == 1 && last.getFirst() instanceof Row row &&
            row.children().isEmpty())
            rows.removeLast();
        int columns = 0;
        for (List<Node> row : rows)
            columns = Math.max(columns, row.size());
        for (List<Node> row : rows)
            while (row.size() < columns)
                row.add(new Row(List.of()));
        return new Matrix(environment, rows);
    }
}
