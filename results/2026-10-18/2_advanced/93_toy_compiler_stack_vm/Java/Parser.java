import java.util.*;
final class Parser {
    enum Type {
        INT,
        BOOL,
        VOID;
        public String toString() { return name().toLowerCase(Locale.ROOT); }
    }
    enum Storage { GLOBAL, PARAMETER, LOCAL }
    static abstract sealed class Declaration permits VariableDecl, Function {
        Type type;
        String name;
        Lexer.Position position, namePosition;
        List<Lexer.Position> references = new ArrayList<>();
        int reads;
        Declaration(Type type, Lexer.Token name, Lexer.Position position) {
            this.type = type;
            this.name = name.spelling();
            this.namePosition = name.position();
            this.position = position;
        }
    }
    static final class VariableDecl extends Declaration implements Statement {
        Storage storage;
        Integer size;
        Lexer.Position sizePosition;
        Expr initializer;
        int address, slot;
        VariableDecl(Type type, Lexer.Token name, Lexer.Position position, Storage storage) {
            super(type, name, position);
            this.storage = storage;
        }
        public Lexer.Position position() { return position; }
    }
    static final class Function extends Declaration {
        List<VariableDecl> parameters;
        Block body;
        Set<Function> calls = new HashSet<>();
        Function(Type type, Lexer.Token name, Lexer.Position position,
                 List<VariableDecl> parameters, Block body) {
            super(type, name, position);
            this.parameters = parameters;
            this.body = body;
        }
    }
    static abstract sealed class Expr permits Literal, Variable, ArrayElement, Read, Call, Unary,
        Binary {
        Lexer.Position position;
        Type type;
        Expr(Lexer.Position position) { this.position = position; }
    }
    static final class Literal extends Expr {
        int value;
        Literal(int value, Type type, Lexer.Position position) {
            super(position);
            this.value = value;
            this.type = type;
        }
    }
    static final class Variable extends Expr {
        String name;
        VariableDecl referent;
        Variable(String name, Lexer.Position position) {
            super(position);
            this.name = name;
        }
    }
    static final class ArrayElement extends Expr {
        String name;
        Expr index;
        VariableDecl referent;
        ArrayElement(String name, Expr index, Lexer.Position position) {
            super(position);
            this.name = name;
            this.index = index;
        }
    }
    static final class Read extends Expr {
        Read(Lexer.Position position) { super(position); }
    }
    static final class Call extends Expr {
        String name;
        List<Expr> arguments;
        Function referent;
        Call(String name, List<Expr> arguments, Lexer.Position position) {
            super(position);
            this.name = name;
            this.arguments = arguments;
        }
    }
    static final class Unary extends Expr {
        String operator;
        Expr operand;
        Unary(String operator, Expr operand, Lexer.Position position) {
            super(position);
            this.operator = operator;
            this.operand = operand;
        }
    }
    static final class Binary extends Expr {
        String operator;
        Expr left, right;
        Binary(String operator, Expr left, Expr right, Lexer.Position position) {
            super(position);
            this.operator = operator;
            this.left = left;
            this.right = right;
        }
    }
    sealed interface Statement permits VariableDecl, Block, Assignment, CallStatement, Print, If,
        While, For, Flow, Return, Empty {
        Lexer.Position position();
    }
    static final class Block implements Statement {
        Lexer.Position position, endPosition;
        List<Statement> statements;
        Block(Lexer.Position position, List<Statement> statements, Lexer.Position endPosition) {
            this.position = position;
            this.statements = statements;
            this.endPosition = endPosition;
        }
        public Lexer.Position position() { return position; }
    }
    static final class Assignment implements Statement {
        String name;
        Expr index, value;
        VariableDecl referent;
        Lexer.Position position;
        Assignment(String name, Expr index, Expr value, Lexer.Position position) {
            this.name = name;
            this.index = index;
            this.value = value;
            this.position = position;
        }
        public Lexer.Position position() { return position; }
    }
    static final class CallStatement implements Statement {
        Expr expression;
        CallStatement(Expr expression) { this.expression = expression; }
        public Lexer.Position position() { return expression.position; }
    }
    static final class Print implements Statement {
        List<Expr> arguments;
        Lexer.Position position;
        Print(List<Expr> arguments, Lexer.Position position) {
            this.arguments = arguments;
            this.position = position;
        }
        public Lexer.Position position() { return position; }
    }
    static final class If implements Statement {
        Expr condition;
        Statement thenStatement, otherwise;
        Lexer.Position position;
        If(Expr condition, Statement thenStatement, Statement otherwise, Lexer.Position position) {
            this.condition = condition;
            this.thenStatement = thenStatement;
            this.otherwise = otherwise;
            this.position = position;
        }
        public Lexer.Position position() { return position; }
    }
    static final class While implements Statement {
        Expr condition;
        Statement body;
        Lexer.Position position;
        While(Expr condition, Statement body, Lexer.Position position) {
            this.condition = condition;
            this.body = body;
            this.position = position;
        }
        public Lexer.Position position() { return position; }
    }
    static final class For implements Statement {
        Statement initial, update, body;
        Expr condition;
        Lexer.Position position;
        For(Statement initial, Expr condition, Statement update, Statement body,
            Lexer.Position position) {
            this.initial = initial;
            this.condition = condition;
            this.update = update;
            this.body = body;
            this.position = position;
        }
        public Lexer.Position position() { return position; }
    }
    record Flow(String kind, Lexer.Position position) implements Statement {}
    static final class Return implements Statement {
        Expr value;
        Lexer.Position position;
        Return(Expr value, Lexer.Position position) {
            this.value = value;
            this.position = position;
        }
        public Lexer.Position position() { return position; }
    }
    record Empty(Lexer.Position position) implements Statement {}
    record Head(Type type, Lexer.Token name, Lexer.Position position) {}
    static final Set<String> TYPES = Set.of("int", "bool", "void");
    static final List<Set<String>> OPERATORS =
        List.of(Set.of("||"), Set.of("&&"), Set.of("==", "!="), Set.of("<", "<=", ">", ">="),
                Set.of("+", "-"), Set.of("*", "/", "%"));
    static List<Expr> expressionChildren(Expr expression) {
        return switch (expression) {
            case Binary binary -> List.of(binary.left, binary.right);
            case Unary unary -> List.of(unary.operand);
            case ArrayElement array -> List.of(array.index);
            case Call call -> call.arguments;
            default -> List.of();
        };
    }
    static List<Statement> statementChildren(Statement statement) {
        return switch (statement) {
            case Block block -> block.statements;
            case If conditional ->
                conditional.otherwise == null
                    ? List.of(conditional.thenStatement)
                    : List.of(conditional.thenStatement, conditional.otherwise);
            case While loop -> List.of(loop.body);
            case For loop -> {
                List<Statement> children = new ArrayList<>();
                if (loop.initial != null)
                    children.add(loop.initial);
                if (loop.update != null)
                    children.add(loop.update);
                children.add(loop.body);
                yield children;
            }
            default -> List.of();
        };
    }
    List<Lexer.Token> tokens;
    int index;
    Parser(List<Lexer.Token> tokens) { this.tokens = tokens; }
    Lexer.Token peek() { return tokens.get(index); }
    void fail() {
        throw new Lexer.CompileError("syntax", peek().position(),
                                     peek().kind().equals("end")
                                         ? "unexpected end of program"
                                         : "unexpected '" + peek().spelling() + "'");
    }
    Lexer.Token take() { return tokens.get(index++); }
    Lexer.Token accept(String spelling) {
        return peek().spelling().equals(spelling) ? take() : null;
    }
    Lexer.Token expect(String spelling) {
        if (!peek().spelling().equals(spelling))
            fail();
        return take();
    }
    Lexer.Token identifier() {
        if (!peek().kind().equals("identifier"))
            fail();
        return take();
    }
    Head head() {
        if (!TYPES.contains(peek().spelling()))
            fail();
        Lexer.Token type = take(), name = identifier();
        return new Head(Type.valueOf(type.spelling().toUpperCase(Locale.ROOT)), name,
                        type.position());
    }
    List<Declaration> parse() {
        List<Declaration> declarations = new ArrayList<>();
        while (!peek().kind().equals("end")) {
            Head head = head();
            if (accept("(") != null) {
                List<VariableDecl> parameters = new ArrayList<>();
                if (!peek().spelling().equals(")"))
                    do {
                        Head parameter = head();
                        parameters.add(new VariableDecl(parameter.type(), parameter.name(),
                                                        parameter.position(), Storage.PARAMETER));
                    } while (accept(",") != null);
                expect(")");
                declarations.add(
                    new Function(head.type(), head.name(), head.position(), parameters, block()));
            } else {
                VariableDecl variable =
                    new VariableDecl(head.type(), head.name(), head.position(), Storage.GLOBAL);
                if (accept("[") != null) {
                    if (!peek().kind().equals("integer"))
                        fail();
                    Lexer.Token size = take();
                    variable.size = Integer.parseInt(size.spelling());
                    variable.sizePosition = size.position();
                    expect("]");
                } else if (accept("=") != null)
                    variable.initializer = expression();
                expect(";");
                declarations.add(variable);
            }
        }
        return declarations;
    }
    VariableDecl declaration(boolean forInitial) {
        Head head = head();
        VariableDecl variable =
            new VariableDecl(head.type(), head.name(), head.position(), Storage.LOCAL);
        if (forInitial) {
            expect("=");
            variable.initializer = expression();
        } else {
            if (accept("=") != null)
                variable.initializer = expression();
            expect(";");
        }
        return variable;
    }
    Block block() {
        Lexer.Token opening = expect("{");
        List<Statement> statements = new ArrayList<>();
        while (!peek().spelling().equals("}"))
            statements.add(TYPES.contains(peek().spelling()) ? declaration(false) : statement());
        return new Block(opening.position(), statements, expect("}").position());
    }
    Statement statement() {
        Lexer.Token token = peek();
        String spelling = token.spelling();
        if (spelling.equals("{"))
            return block();
        if (spelling.equals("if") || spelling.equals("while")) {
            take();
            expect("(");
            Expr condition = expression();
            expect(")");
            Statement body = statement();
            if (spelling.equals("while"))
                return new While(condition, body, token.position());
            Statement otherwise = accept("else") == null ? null : statement();
            return new If(condition, body, otherwise, token.position());
        }
        if (spelling.equals("for")) {
            take();
            expect("(");
            Statement initial = null;
            if (TYPES.contains(peek().spelling()))
                initial = declaration(true);
            else if (!peek().spelling().equals(";"))
                initial = simple();
            expect(";");
            Expr condition = peek().spelling().equals(";") ? null : expression();
            expect(";");
            Statement update = peek().spelling().equals(")") ? null : simple();
            expect(")");
            return new For(initial, condition, update, statement(), token.position());
        }
        if (spelling.equals("break") || spelling.equals("continue")) {
            take();
            expect(";");
            return new Flow(spelling, token.position());
        }
        if (spelling.equals("return")) {
            take();
            Expr value = peek().spelling().equals(";") ? null : expression();
            expect(";");
            return new Return(value, token.position());
        }
        if (spelling.equals("print")) {
            take();
            expect("(");
            List<Expr> arguments = new ArrayList<>();
            arguments.add(expression());
            while (accept(",") != null)
                arguments.add(expression());
            expect(")");
            expect(";");
            return new Print(arguments, token.position());
        }
        if (token.kind().equals("identifier") || spelling.equals("read")) {
            Statement result = simple();
            expect(";");
            return result;
        }
        fail();
        throw new IllegalStateException();
    }
    Statement simple() {
        if (!peek().kind().equals("identifier") && !peek().spelling().equals("read"))
            fail();
        Expr value = primary();
        if (value instanceof Call || value instanceof Read)
            return new CallStatement(value);
        expect("=");
        if (value instanceof ArrayElement array)
            return new Assignment(array.name, array.index, expression(), array.position);
        Variable variable = (Variable)value;
        return new Assignment(variable.name, null, expression(), variable.position);
    }
    Expr expression() { return expression(0); }
    Expr expression(int level) {
        if (level == OPERATORS.size()) {
            if (Set.of("-", "!").contains(peek().spelling())) {
                Lexer.Token operator = take();
                return new Unary(operator.spelling(), expression(level), operator.position());
            }
            return primary();
        }
        Expr expression = expression(level + 1);
        while (OPERATORS.get(level).contains(peek().spelling())) {
            Lexer.Token operator = take();
            expression = new Binary(operator.spelling(), expression, expression(level + 1),
                                    operator.position());
        }
        return expression;
    }
    Expr primary() {
        Lexer.Token token = peek();
        if (token.kind().equals("integer")) {
            take();
            return new Literal(Integer.parseInt(token.spelling()), Type.INT, token.position());
        }
        if (Set.of("true", "false").contains(token.spelling())) {
            take();
            return new Literal(token.spelling().equals("true") ? 1 : 0, Type.BOOL,
                               token.position());
        }
        if (token.spelling().equals("read")) {
            take();
            expect("(");
            expect(")");
            return new Read(token.position());
        }
        if (accept("(") != null) {
            Expr result = expression();
            expect(")");
            return result;
        }
        if (token.kind().equals("identifier")) {
            take();
            if (accept("(") != null) {
                List<Expr> arguments = new ArrayList<>();
                if (!peek().spelling().equals(")")) {
                    arguments.add(expression());
                    while (accept(",") != null)
                        arguments.add(expression());
                }
                expect(")");
                return new Call(token.spelling(), arguments, token.position());
            }
            if (accept("[") != null) {
                Expr index = expression();
                expect("]");
                return new ArrayElement(token.spelling(), index, token.position());
            }
            return new Variable(token.spelling(), token.position());
        }
        fail();
        throw new IllegalStateException();
    }
}
