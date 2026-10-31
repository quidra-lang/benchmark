import java.util.*;
import java.util.function.Supplier;
final class Parser {
    interface Node {
        Lexer.Token first();
    }
    sealed interface Item extends Node permits Function, Variable {}
    sealed interface Statement extends Node permits Variable, Block, SimpleStatement, Return, Flow,
                                       If, While, For, Switch {}
    sealed interface Expr
        extends Node permits Primary, Paren, Unary, Binary, Conditional, Call, Index, Member {
        default int level() { return 8; }
    }
    record Function(Lexer.Token type, Lexer.Token name, ListNode parameters, Block body)
        implements Item {
        public Lexer.Token first() { return type; }
    }
    record Parameter(Lexer.Token type, Lexer.Token name, List<Bracket> brackets) implements Node {
        public Lexer.Token first() { return type; }
    }
    record Bracket(Lexer.Token left, Expr expression, Lexer.Token right) {}
    record Variable(Lexer.Token type, Lexer.Token name, List<Bracket> dimensions,
                    Lexer.Token equals, Node initializer, Lexer.Token semi)
        implements Item, Statement {
        public Lexer.Token first() { return type; }
    }
    enum ListKind { PARAMETERS, ARGUMENTS, INITIALIZERS }
    record ListNode(Lexer.Token left, Lexer.Token right, List<Node> elements,
                    List<Lexer.Token> commas, Lexer.Token trailing, ListKind kind) implements Node {
        public Lexer.Token first() { return left; }
    }
    record Block(Lexer.Token left, List<Statement> statements, Lexer.Token right)
        implements Statement {
        public Lexer.Token first() { return left; }
    }
    record Simple(Expr left, Lexer.Token operator, Expr right) implements Node {
        public Lexer.Token first() { return left.first(); }
    }
    record SimpleStatement(Simple value, Lexer.Token semi) implements Statement {
        public Lexer.Token first() { return value.first(); }
    }
    record Return(Lexer.Token keyword, Expr expression, Lexer.Token semi) implements Statement {
        public Lexer.Token first() { return keyword; }
    }
    record Flow(Lexer.Token keyword, Lexer.Token semi) implements Statement {
        public Lexer.Token first() { return keyword; }
    }
    record If(Lexer.Token keyword, Lexer.Token left, Expr test, Lexer.Token right, Statement body,
              Lexer.Token elseToken, Statement alternative) implements Statement {
        public Lexer.Token first() { return keyword; }
    }
    record While(Lexer.Token keyword, Lexer.Token left, Expr test, Lexer.Token right,
                 Statement body) implements Statement {
        public Lexer.Token first() { return keyword; }
    }
    record For(Lexer.Token keyword, Lexer.Token left, Node initial, Lexer.Token firstSemi,
               Expr condition, Lexer.Token secondSemi, Simple update, Lexer.Token right,
               Statement body) implements Statement {
        public Lexer.Token first() { return keyword; }
    }
    record Clause(Lexer.Token label, Expr value, Lexer.Token colon, List<Statement> statements)
        implements Node {
        public Lexer.Token first() { return label; }
    }
    record Switch(Lexer.Token keyword, Lexer.Token left, Expr test, Lexer.Token right,
                  Lexer.Token opening, List<Clause> clauses, Lexer.Token closing)
        implements Statement {
        public Lexer.Token first() { return keyword; }
    }
    record Primary(Lexer.Token token) implements Expr {
        public Lexer.Token first() { return token; }
    }
    record Paren(Lexer.Token left, Expr inner, Lexer.Token right) implements Expr {
        public Lexer.Token first() { return left; }
    }
    record Unary(Lexer.Token operator, Expr operand) implements Expr {
        public Lexer.Token first() { return operator; }
        public int level() { return 7; }
    }
    record Binary(Expr left, Lexer.Token operator, Expr right, int level) implements Expr {
        public Lexer.Token first() { return left.first(); }
    }
    record Conditional(Expr test, Lexer.Token question, Expr yes, Lexer.Token colon, Expr no)
        implements Expr {
        public Lexer.Token first() { return test.first(); }
        public int level() { return 0; }
    }
    record Call(Expr target, ListNode arguments) implements Expr {
        public Lexer.Token first() { return target.first(); }
    }
    record Index(Expr target, Lexer.Token left, Expr index, Lexer.Token right) implements Expr {
        public Lexer.Token first() { return target.first(); }
    }
    record Member(Expr target, Lexer.Token dot, Lexer.Token name) implements Expr {
        public Lexer.Token first() { return target.first(); }
    }
    static final Map<String, Integer> PRECEDENCE =
        Map.ofEntries(Map.entry("||", 1), Map.entry("&&", 2), Map.entry("==", 3),
                      Map.entry("!=", 3), Map.entry("<", 4), Map.entry("<=", 4), Map.entry(">", 4),
                      Map.entry(">=", 4), Map.entry("+", 5), Map.entry("-", 5), Map.entry("*", 6),
                      Map.entry("/", 6), Map.entry("%", 6));
    List<Lexer.Token> tokens;
    int cursor;
    Parser(List<Lexer.Token> tokens) { this.tokens = tokens; }
    Lexer.Token peek() { return tokens.get(cursor); }
    boolean at(String symbol) { return peek().text.equals(symbol); }
    void fail(String expected) {
        Lexer.Token actual = peek();
        String found = actual.kind.equals("end") ? "end of file" : "'" + actual.text + "'";
        throw new Lexer.SourceError(actual.line, actual.column,
                                    "expected " + expected + ", found " + found);
    }
    Lexer.Token take(String symbol) {
        if (!at(symbol))
            fail("'" + symbol + "'");
        return tokens.get(cursor++);
    }
    Lexer.Token identifier() {
        if (!peek().kind.equals("identifier"))
            fail("identifier");
        return tokens.get(cursor++);
    }
    Lexer.Token type() {
        if (!isType())
            fail("type");
        return tokens.get(cursor++);
    }
    boolean isType() { return Lexer.TYPES.contains(peek().text); }
    List<Item> parse() {
        List<Item> result = new ArrayList<>();
        while (!peek().kind.equals("end"))
            result.add(item());
        return result;
    }
    Item item() {
        Lexer.Token type = type(), name = identifier();
        type.allowed = true;
        if (at("(")) {
            ListNode parameters = list("(", ")", this::parameter, ListKind.PARAMETERS);
            return new Function(type, name, parameters, block());
        }
        return variable(type, name, true);
    }
    Parameter parameter() {
        Lexer.Token type = type(), name = identifier();
        List<Bracket> brackets = new ArrayList<>();
        while (at("["))
            brackets.add(new Bracket(take("["), null, take("]")));
        return new Parameter(type, name, brackets);
    }
    Variable variable(Lexer.Token type, Lexer.Token name, boolean semicolon) {
        List<Bracket> dimensions = new ArrayList<>();
        while (at("[")) {
            Lexer.Token left = take("[");
            Expr expression = at("]") ? null : expression();
            dimensions.add(new Bracket(left, expression, take("]")));
        }
        Lexer.Token equals = at("=") ? take("=") : null;
        Node initializer = equals == null ? null : initializer();
        return new Variable(type, name, dimensions, equals, initializer,
                            semicolon ? take(";") : null);
    }
    Node initializer() {
        return at("{") ? list("{", "}", this::initializer, ListKind.INITIALIZERS) : expression();
    }
    ListNode list(String opening, String closing, Supplier<? extends Node> element, ListKind kind) {
        Lexer.Token left = take(opening), trailing = null;
        List<Node> contents = new ArrayList<>();
        List<Lexer.Token> commas = new ArrayList<>();
        if (!at(closing)) {
            Node first = element.get();
            first.first().allowed = true;
            contents.add(first);
            while (at(",")) {
                Lexer.Token comma = take(",");
                if (kind == ListKind.INITIALIZERS && at(closing)) {
                    comma.trailingComma = true;
                    trailing = comma;
                    break;
                }
                commas.add(comma);
                Node item = element.get();
                item.first().allowed = true;
                contents.add(item);
            }
        }
        return new ListNode(left, take(closing), contents, commas, trailing, kind);
    }
    Block block() {
        Lexer.Token left = take("{");
        List<Statement> statements = new ArrayList<>();
        while (!at("}") && !peek().kind.equals("end")) {
            Statement statement = statement();
            statement.first().allowed = true;
            statements.add(statement);
        }
        Lexer.Token right = take("}");
        right.allowed = true;
        return new Block(left, statements, right);
    }
    Statement body() {
        Statement statement = statement();
        if (!(statement instanceof Block))
            statement.first().allowed = true;
        return statement;
    }
    Statement statement() {
        if (at("{"))
            return block();
        if (isType()) {
            Lexer.Token type = type(), name = identifier();
            return variable(type, name, true);
        }
        if (at("if"))
            return ifStatement();
        if (at("while")) {
            Lexer.Token keyword = take("while"), left = take("(");
            Expr test = expression();
            Lexer.Token right = take(")");
            return new While(keyword, left, test, right, body());
        }
        if (at("for"))
            return forStatement();
        if (at("switch"))
            return switchStatement();
        if (at("return")) {
            Lexer.Token keyword = take("return");
            Expr expression = at(";") ? null : expression();
            return new Return(keyword, expression, take(";"));
        }
        if (at("break") || at("continue"))
            return new Flow(tokens.get(cursor++), take(";"));
        return new SimpleStatement(simple(), take(";"));
    }
    If ifStatement() {
        Lexer.Token keyword = take("if"), left = take("(");
        Expr test = expression();
        Lexer.Token right = take(")");
        Statement body = body();
        Lexer.Token elseToken = at("else") ? take("else") : null;
        Statement alternative = null;
        if (elseToken != null) {
            if (at("if")) {
                alternative = ifStatement();
                alternative.first().allowed = false;
            } else
                alternative = body();
        }
        return new If(keyword, left, test, right, body, elseToken, alternative);
    }
    For forStatement() {
        Lexer.Token keyword = take("for"), left = take("(");
        Node initial = null;
        if (!at(";")) {
            if (isType()) {
                Lexer.Token type = type(), name = identifier();
                initial = variable(type, name, false);
            } else
                initial = simple();
        }
        Lexer.Token firstSemi = take(";");
        Expr condition = at(";") ? null : expression();
        Lexer.Token secondSemi = take(";");
        Simple update = at(")") ? null : simple();
        Lexer.Token right = take(")");
        return new For(keyword, left, initial, firstSemi, condition, secondSemi, update, right,
                       body());
    }
    Switch switchStatement() {
        Lexer.Token keyword = take("switch"), left = take("(");
        Expr test = expression();
        Lexer.Token right = take(")"), opening = take("{");
        List<Clause> clauses = new ArrayList<>();
        while (at("case") || at("default")) {
            Lexer.Token label = tokens.get(cursor++);
            label.allowed = true;
            Expr value = label.text.equals("case") ? expression() : null;
            Lexer.Token colon = take(":");
            List<Statement> statements = new ArrayList<>();
            while (!at("case") && !at("default") && !at("}") && !peek().kind.equals("end")) {
                Statement statement = statement();
                statement.first().allowed = true;
                statements.add(statement);
            }
            clauses.add(new Clause(label, value, colon, statements));
        }
        Lexer.Token closing = take("}");
        closing.allowed = true;
        return new Switch(keyword, left, test, right, opening, clauses, closing);
    }
    Simple simple() {
        Expr left = expression();
        if (Lexer.ASSIGNMENT.contains(peek().text)) {
            Lexer.Token operator = tokens.get(cursor++);
            return new Simple(left, operator, expression());
        }
        return new Simple(left, null, null);
    }
    Expr expression() {
        Expr condition = binary(1);
        if (at("?")) {
            Lexer.Token question = take("?");
            Expr yes = expression();
            Lexer.Token colon = take(":");
            return new Conditional(condition, question, yes, colon, expression());
        }
        return condition;
    }
    Expr binary(int precedence) {
        if (precedence > 6)
            return unary();
        Expr left = binary(precedence + 1);
        while (PRECEDENCE.getOrDefault(peek().text, 0) == precedence) {
            Lexer.Token operator = tokens.get(cursor++);
            left = new Binary(left, operator, binary(precedence + 1), precedence);
        }
        return left;
    }
    Expr unary() {
        if (at("-") || at("!"))
            return new Unary(tokens.get(cursor++), unary());
        Expr target = primary();
        while (true) {
            if (at("("))
                target = new Call(target, list("(", ")", this::expression, ListKind.ARGUMENTS));
            else if (at("[")) {
                Lexer.Token left = take("[");
                Expr index = expression();
                target = new Index(target, left, index, take("]"));
            } else if (at("."))
                target = new Member(target, take("."), identifier());
            else
                return target;
        }
    }
    Expr primary() {
        Lexer.Token token = peek();
        if (Set.of("identifier", "number", "string").contains(token.kind) ||
            Set.of("true", "false").contains(token.text)) {
            cursor++;
            return new Primary(token);
        }
        if (at("(")) {
            Lexer.Token left = take("(");
            Expr inner = expression();
            return new Paren(left, inner, take(")"));
        }
        fail("expression");
        throw new IllegalStateException();
    }
}
