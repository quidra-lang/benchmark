import java.util.*;
final class Parser {
    interface Node {
        Lexer.Position pos();
    }
    sealed interface Expr extends Node permits Variable, ArrayAccess, Field, Literal, Paren,
                                  Assignment, Increment, Conditional, Unary, Membership, Binary,
                                  Call, Builtin, Getline {}
    sealed interface Stmt extends Node permits Block, Empty, ExpressionStatement, Output, If, While,
                                  DoWhile, For, ForIn, Delete, TransferStatement {}
    sealed interface Item extends Node permits Function, Rule {}
    record Variable(String name, Lexer.Position pos) implements Expr {}
    record ArrayAccess(String name, List<Expr> indexes, Lexer.Position pos) implements Expr {}
    record Field(Expr index, Lexer.Position pos) implements Expr {}
    record Literal(ValuesFields.Value value, Lexer.Position pos) implements Expr {}
    record Paren(Expr expression, Lexer.Position pos) implements Expr {}
    record Assignment(String operator, Expr location, Expr value, Lexer.Position pos)
        implements Expr {}
    record Increment(Expr location, int delta, boolean prefix, Lexer.Position pos) implements Expr {
    }
    record Conditional(Expr condition, Expr first, Expr second, Lexer.Position pos)
        implements Expr {}
    record Unary(String operator, Expr operand, Lexer.Position pos) implements Expr {}
    record Membership(List<Expr> indexes, Variable array, Lexer.Position pos) implements Expr {}
    record Binary(String operator, Expr left, Expr right, Lexer.Position pos) implements Expr {}
    record Call(String name, List<Expr> arguments, Lexer.Position pos) implements Expr {}
    record Builtin(String name, List<Expr> arguments, Lexer.Position pos) implements Expr {}
    record Getline(Expr target, Expr filename, Lexer.Position pos) implements Expr {}
    record Block(List<Stmt> statements, Lexer.Position pos) implements Stmt {}
    record Empty(Lexer.Position pos) implements Stmt {}
    record ExpressionStatement(Expr expression, Lexer.Position pos) implements Stmt {}
    record Output(boolean formatted, List<Expr> arguments, String redirect,
                  Lexer.Position redirectPos, Expr filename, Lexer.Position pos) implements Stmt {}
    record If(Expr condition, Stmt first, Stmt second, Lexer.Position pos) implements Stmt {}
    record While(Expr condition, Stmt body, Lexer.Position pos) implements Stmt {}
    record DoWhile(Stmt body, Expr condition, Lexer.Position pos) implements Stmt {}
    record For(Expr initial, Expr condition, Expr update, Stmt body, Lexer.Position pos)
        implements Stmt {}
    record ForIn(Variable variable, Variable array, Stmt body, Lexer.Position pos) implements Stmt {
    }
    record Delete(Variable array, List<Expr> indexes, Lexer.Position pos) implements Stmt {}
    record TransferStatement(String kind, Expr value, Lexer.Position pos) implements Stmt {}
    static final class Function implements Item {
        final String name;
        final Lexer.Position pos, namePos;
        final List<Variable> parameters;
        final Block body;
        final Set<String> parameterNames = new HashSet<>();
        int calls, active, depth;
        Function(String name, Lexer.Position pos, Lexer.Position namePos, List<Variable> parameters,
                 Block body) {
            this.name = name;
            this.pos = pos;
            this.namePos = namePos;
            this.parameters = parameters;
            this.body = body;
        }
        public Lexer.Position pos() { return pos; }
    }
    static final class Rule implements Item {
        final String flavor;
        final Lexer.Position pos;
        final List<Expr> patterns;
        final Block action;
        int count;
        boolean inside;
        Rule(String flavor, Lexer.Position pos, List<Expr> patterns, Block action) {
            this.flavor = flavor;
            this.pos = pos;
            this.patterns = patterns;
            this.action = action;
        }
        public Lexer.Position pos() { return pos; }
    }
    static final Set<String> ASSIGNMENTS = Set.of("=", "+=", "-=", "*=", "/=", "%=", "^="),
                             COMPARISONS = Set.of("<", "<=", "==", "!=", ">=", ">");
    final List<Lexer.Token> tokens;
    int index, loopDepth;
    boolean function;
    String phase;
    Parser(List<Lexer.Token> tokens) { this.tokens = tokens; }
    Lexer.Token peek() { return tokens.get(index); }
    Lexer.Token take() { return tokens.get(index++); }
    boolean at(String text) { return peek().text().equals(text); }
    Lexer.Token accept(String text) { return at(text) ? take() : null; }
    Lexer.Token expect(String text) {
        if (!at(text))
            fail();
        return take();
    }
    void fail() { throw new Lexer.SyntaxIssue(peek().pos()); }
    void fail(Lexer.Position pos) { throw new Lexer.SyntaxIssue(pos); }
    Variable name() {
        if (peek().kind() != Lexer.Kind.NAME)
            fail();
        Lexer.Token token = take();
        return new Variable(token.text(), token.pos());
    }
    void newlines() {
        while (accept("\n") != null) {
        }
    }
    List<Item> parse() {
        List<Item> items = new ArrayList<>();
        while (peek().kind() != Lexer.Kind.END) {
            if (at("\n") || at(";")) {
                take();
                continue;
            }
            Lexer.Token start = peek();
            if (accept("function") != null) {
                if (peek().kind() != Lexer.Kind.NAME && peek().kind() != Lexer.Kind.FUNCNAME)
                    fail();
                Lexer.Token name = take();
                expect("(");
                List<Variable> parameters = new ArrayList<>();
                if (!at(")")) {
                    while (true) {
                        parameters.add(name());
                        if (accept(",") == null)
                            break;
                        newlines();
                    }
                }
                expect(")");
                newlines();
                function = true;
                Block body = block();
                function = false;
                items.add(new Function(name.text(), start.pos(), name.pos(), parameters, body));
                continue;
            }
            List<Expr> patterns = new ArrayList<>();
            String flavor;
            if (at("BEGIN") || at("END"))
                flavor = take().text();
            else if (at("{"))
                flavor = "all";
            else {
                patterns.add(expression());
                if (accept(",") != null) {
                    newlines();
                    patterns.add(expression());
                }
                flavor = patterns.size() == 2 ? "range" : "pattern";
            }
            phase = flavor;
            Block action = null;
            if (flavor.equals("BEGIN") || flavor.equals("END") || flavor.equals("all") || at("{"))
                action = block();
            else if (!at("\n") && !at(";") && peek().kind() != Lexer.Kind.END)
                fail();
            phase = null;
            items.add(new Rule(flavor, start.pos(), patterns, action));
        }
        return items;
    }
    Block block() {
        Lexer.Token opening = expect("{");
        List<Stmt> statements = new ArrayList<>();
        while (!at("}")) {
            if (at("\n") || at(";"))
                take();
            else
                statements.add(statement());
        }
        expect("}");
        return new Block(statements, opening.pos());
    }
    Expr condition() {
        expect("(");
        Expr value = expression();
        expect(")");
        return value;
    }
    Stmt loopBody() {
        newlines();
        loopDepth++;
        Stmt body = statement();
        loopDepth--;
        return body;
    }
    void terminator() {
        if (at(";") || at("\n"))
            take();
        else if (!at("}"))
            fail();
    }
    Stmt statement() {
        Lexer.Token token = peek();
        String spelling = token.text();
        if (at("{"))
            return block();
        if (accept(";") != null)
            return new Empty(token.pos());
        if (accept("if") != null) {
            Expr condition = condition();
            newlines();
            Stmt first = statement();
            newlines();
            Stmt second = null;
            if (accept("else") != null) {
                newlines();
                second = statement();
            }
            return new If(condition, first, second, token.pos());
        }
        if (accept("while") != null) {
            Expr condition = condition();
            return new While(condition, loopBody(), token.pos());
        }
        if (accept("do") != null) {
            Stmt body = loopBody();
            newlines();
            expect("while");
            Expr condition = condition();
            terminator();
            return new DoWhile(body, condition, token.pos());
        }
        if (accept("for") != null) {
            expect("(");
            if (index + 3 < tokens.size() && peek().kind() == Lexer.Kind.NAME &&
                tokens.get(index + 1).text().equals("in") &&
                tokens.get(index + 2).kind() == Lexer.Kind.NAME &&
                tokens.get(index + 3).text().equals(")")) {
                Variable variable = name();
                expect("in");
                Variable array = name();
                expect(")");
                return new ForIn(variable, array, loopBody(), token.pos());
            }
            Expr initial = at(";") ? null : expression();
            expect(";");
            newlines();
            Expr condition = at(";") ? null : expression();
            expect(";");
            newlines();
            Expr update = at(")") ? null : expression();
            expect(")");
            return new For(initial, condition, update, loopBody(), token.pos());
        }
        Stmt result;
        if (spelling.equals("print") || spelling.equals("printf")) {
            take();
            result = output(token);
        } else if (accept("delete") != null) {
            Variable array = name();
            List<Expr> indexes = null;
            if (accept("[") != null) {
                indexes = expressionList(true);
                expect("]");
            }
            result = new Delete(array, indexes, token.pos());
        } else if (Set.of("next", "break", "continue", "exit", "return").contains(spelling)) {
            take();
            if (spelling.equals("next") && !function &&
                (Objects.equals(phase, "BEGIN") || Objects.equals(phase, "END")))
                fail(token.pos());
            if (spelling.equals("return") && !function)
                fail(token.pos());
            if ((spelling.equals("break") || spelling.equals("continue")) && loopDepth == 0)
                fail(token.pos());
            Expr value = null;
            if ((spelling.equals("exit") || spelling.equals("return")) && !at(";") && !at("\n") &&
                !at("}"))
                value = expression();
            result = new TransferStatement(spelling, value, token.pos());
        } else
            result = new ExpressionStatement(expression(), token.pos());
        terminator();
        return result;
    }
    boolean parenthesizedOutput() {
        if (!at("("))
            return false;
        int depth = 0;
        for (int i = index; i < tokens.size(); i++) {
            String spelling = tokens.get(i).text();
            if (spelling.equals("("))
                depth++;
            else if (spelling.equals(")") && --depth == 0) {
                Lexer.Token next = tokens.get(i + 1);
                return Set.of(";", "\n", "}", ">", ">>").contains(next.text()) ||
                    next.kind() == Lexer.Kind.END;
            }
        }
        return false;
    }
    Output output(Lexer.Token token) {
        List<Expr> arguments = new ArrayList<>();
        if (parenthesizedOutput()) {
            expect("(");
            arguments = expressionList(true);
            expect(")");
        } else if (!Set.of(";", "\n", "}", ">", ">>").contains(peek().text()))
            arguments = expressionList(false);
        if (token.text().equals("printf") && arguments.isEmpty())
            fail();
        Lexer.Token redirect = at(">") || at(">>") ? take() : null;
        Expr filename = redirect == null ? null : concatenation();
        return new Output(token.text().equals("printf"), arguments,
                          redirect == null ? null : redirect.text(),
                          redirect == null ? null : redirect.pos(), filename, token.pos());
    }
    List<Expr> expressionList(boolean greater) {
        List<Expr> result = new ArrayList<>();
        result.add(expression(greater));
        while (accept(",") != null) {
            newlines();
            result.add(expression(greater));
        }
        return result;
    }
    Expr expression() { return expression(true); }
    Expr expression(boolean greater) {
        Expr left = conditional(greater);
        if (lvalue(left) && ASSIGNMENTS.contains(peek().text())) {
            Lexer.Token operator = take();
            return new Assignment(operator.text(), left, expression(greater), operator.pos());
        }
        return left;
    }
    static boolean lvalue(Expr expr) {
        return expr instanceof Variable || expr instanceof ArrayAccess || expr instanceof Field;
    }
    Expr conditional(boolean greater) {
        Expr condition = logical(0, greater);
        Lexer.Token operator = accept("?");
        if (operator == null)
            return condition;
        Expr first = conditional(greater);
        expect(":");
        return new Conditional(condition, first, conditional(greater), operator.pos());
    }
    Expr binary(Lexer.Token operator, Expr left, Expr right) {
        return new Binary(operator.text(), left, right, operator.pos());
    }
    Expr logical(int level, boolean greater) {
        if (level == 2)
            return membership(greater);
        String operatorName = level == 0 ? "||" : "&&";
        Expr left = logical(level + 1, greater);
        while (at(operatorName)) {
            Lexer.Token operator = take();
            newlines();
            left = binary(operator, left, logical(level + 1, greater));
        }
        return left;
    }
    Expr membership(boolean greater) {
        Expr left = comparison(greater);
        while (at("in")) {
            Lexer.Token operator = take();
            left = new Membership(List.of(left), name(), operator.pos());
        }
        return left;
    }
    Expr comparison(boolean greater) {
        Expr left = concatenation();
        while (COMPARISONS.contains(peek().text()) && (greater || !at(">"))) {
            Lexer.Token operator = take();
            left = binary(operator, left, concatenation());
        }
        return left;
    }
    Expr concatenation() {
        Expr left = additive();
        while (Set.of(Lexer.Kind.NUMBER, Lexer.Kind.STRING, Lexer.Kind.NAME, Lexer.Kind.FUNCNAME,
                      Lexer.Kind.BUILTIN)
                   .contains(peek().kind()) ||
               Set.of("$", "(", "++", "--").contains(peek().text())) {
            Lexer.Position pos = peek().pos();
            left = new Binary("concat", left, additive(), pos);
        }
        return left;
    }
    Expr additive() {
        Expr left = multiplicative();
        while (at("+") || at("-")) {
            Lexer.Token operator = take();
            left = binary(operator, left, multiplicative());
        }
        return left;
    }
    Expr multiplicative() {
        Expr left = unary();
        while (at("*") || at("/") || at("%")) {
            Lexer.Token operator = take();
            left = binary(operator, left, unary());
        }
        return left;
    }
    Expr unary() {
        if (at("!") || at("-") || at("+")) {
            Lexer.Token operator = take();
            return new Unary(operator.text(), unary(), operator.pos());
        }
        Expr left = postfix();
        if (at("^")) {
            Lexer.Token operator = take();
            left = binary(operator, left, unary());
        }
        return left;
    }
    Expr prefix() {
        Lexer.Token operator = take();
        return new Increment(lvalue(), operator.text().equals("++") ? 1 : -1, true, operator.pos());
    }
    Expr postfix() {
        if (at("++") || at("--"))
            return prefix();
        Expr left = atom();
        if (lvalue(left) && (at("++") || at("--"))) {
            Lexer.Token operator = take();
            return new Increment(left, operator.text().equals("++") ? 1 : -1, false,
                                 operator.pos());
        }
        return left;
    }
    Expr lvalue() {
        if (peek().kind() == Lexer.Kind.NAME) {
            Variable node = name();
            if (accept("[") != null) {
                List<Expr> indexes = expressionList(true);
                expect("]");
                return new ArrayAccess(node.name(), indexes, node.pos());
            }
            return node;
        }
        Lexer.Token dollar = accept("$");
        if (dollar != null)
            return new Field(at("++") || at("--") ? prefix() : atom(), dollar.pos());
        fail();
        throw new AssertionError();
    }
    Expr atom() {
        Lexer.Token token = peek();
        if (token.kind() == Lexer.Kind.NUMBER || token.kind() == Lexer.Kind.STRING) {
            take();
            return new Literal(token.kind() == Lexer.Kind.NUMBER
                                   ? ValuesFields.number(Integer.parseInt(token.value()))
                                   : ValuesFields.string(token.value()),
                               token.pos());
        }
        if (token.kind() == Lexer.Kind.NAME || at("$"))
            return lvalue();
        if (accept("(") != null) {
            List<Expr> expressions = expressionList(true);
            expect(")");
            if (expressions.size() == 1)
                return new Paren(expressions.getFirst(), token.pos());
            expect("in");
            return new Membership(expressions, name(), token.pos());
        }
        if (token.kind() == Lexer.Kind.FUNCNAME || token.kind() == Lexer.Kind.BUILTIN) {
            take();
            List<Expr> arguments = new ArrayList<>();
            if (accept("(") != null) {
                if (!at(")"))
                    arguments = expressionList(true);
                expect(")");
            } else if (token.kind() == Lexer.Kind.FUNCNAME || !token.text().equals("length"))
                fail();
            if (token.kind() == Lexer.Kind.BUILTIN) {
                checkBuiltin(token, arguments);
                return new Builtin(token.text(), arguments, token.pos());
            }
            return new Call(token.text(), arguments, token.pos());
        }
        if (accept("getline") != null) {
            Expr target = peek().kind() == Lexer.Kind.NAME || at("$") ? lvalue() : null;
            Expr filename = accept("<") != null ? atom() : null;
            return new Getline(target, filename, token.pos());
        }
        fail();
        throw new AssertionError();
    }
    void checkBuiltin(Lexer.Token token, List<Expr> arguments) {
        int count = arguments.size();
        boolean valid = switch (token.text()) {
            case "length" -> count == 0 || count == 1;
            case "substr", "split" -> count == 2 || count == 3;
            case "index" -> count == 2;
            case "sprintf" -> count >= 1;
            default -> count == 1;
        };
        if (!valid || token.text().equals("split") && !(arguments.get(1) instanceof Variable))
            fail(token.pos());
    }
}
