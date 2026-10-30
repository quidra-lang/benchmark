import java.util.*;
final class Parser {
    sealed interface Expr permits Literal, Name, Fun, Apply, Binary, Negate, Conditional, Pair,
        ListExpr, Let, Match {
        Lexer.Position position();
    }
    record Literal(String kind, String value, Lexer.Position position) implements Expr {}
    record Name(Lexer.Token token) implements Expr {
        public Lexer.Position position() { return token.position(); }
    }
    record Fun(Lexer.Token parameter, Expr body, Lexer.Position position) implements Expr {}
    record Apply(Expr function, Expr argument) implements Expr {
        public Lexer.Position position() { return function.position(); }
    }
    record Binary(Expr left, Lexer.Token operator, Expr right) implements Expr {
        public Lexer.Position position() { return left.position(); }
    }
    record Negate(Lexer.Token operator, Expr operand) implements Expr {
        public Lexer.Position position() { return operator.position(); }
    }
    record Conditional(Expr condition, Expr yes, Expr no, Lexer.Position position) implements Expr {
    }
    record Pair(Expr first, Expr second, Lexer.Position position) implements Expr {}
    record ListExpr(List<Expr> elements, Lexer.Position position) implements Expr {}
    record Let(Group group, Expr body, Lexer.Position position) implements Expr {}
    record Match(Expr matched, List<Arm> arms, Lexer.Position position) implements Expr {}
    sealed interface Pattern permits Wildcard, PatternName, PatternLiteral, PatternPair,
        PatternList, Cons {
        Lexer.Position position();
    }
    record Wildcard(Lexer.Position position) implements Pattern {}
    record PatternName(Lexer.Token token) implements Pattern {
        public Lexer.Position position() { return token.position(); }
    }
    record PatternLiteral(String kind, String value, Lexer.Position position) implements Pattern {}
    record PatternPair(Pattern first, Pattern second, Lexer.Position position) implements Pattern {}
    record PatternList(List<Pattern> elements, Lexer.Position position) implements Pattern {}
    record Cons(Pattern first, Pattern rest) implements Pattern {
        public Lexer.Position position() { return first.position(); }
    }
    record Arm(Pattern pattern, Expr expression) {}
    static final class Binding {
        Lexer.Token token;
        Expr expression;
        Unifier.Scheme scheme;
        String classification = "";
        Binding(Lexer.Token token, Expr expression) {
            this.token = token;
            this.expression = expression;
        }
        String name() { return token.spelling(); }
        Lexer.Position position() { return token.position(); }
    }
    record Group(List<Binding> bindings, Lexer.Position recPosition) {}
    sealed interface TypeExpr permits TypeName, TypeVariableName, TypeConstructor {}
    record TypeName(String name) implements TypeExpr {}
    record TypeVariableName(String spelling) implements TypeExpr {}
    record TypeConstructor(String kind, List<TypeExpr> children) implements TypeExpr {}
    sealed interface Item permits Signature, Declaration, ExpressionItem {}
    record Signature(Lexer.Token name, TypeExpr declared) implements Item {}
    record Declaration(Group group) implements Item {}
    record ExpressionItem(Expr expression) implements Item {}
    record Operator(int precedence, boolean right) {}
    static final Map<String, Operator> OPERATORS = operators();
    static Map<String, Operator> operators() {
        Map<String, Operator> result = new HashMap<>();
        String[][] groups = {{"||"},      {"&&"},     {"=", "<>", "<", ">", "<=", ">="},
                             {"::", "^"}, {"+", "-"}, {"*", "/", "mod"}};
        for (int i = 0; i < groups.length; i++)
            for (String operator : groups[i])
                result.put(operator, new Operator(i + 1, i == 0 || i == 1 || i == 3));
        return Map.copyOf(result);
    }
    static final class SyntaxFailure extends RuntimeException {
        Lexer.Token token;
        SyntaxFailure(Lexer.Token token) { this.token = token; }
    }
    List<Lexer.Token> tokens;
    int index;
    Parser(List<Lexer.Token> tokens) { this.tokens = tokens; }
    Lexer.Token peek() { return tokens.get(index); }
    Lexer.Token accept(String kind) {
        return peek().kind().equals(kind) ? tokens.get(index++) : null;
    }
    Lexer.Token expect(String kind) {
        Lexer.Token token = accept(kind);
        if (token == null)
            throw new SyntaxFailure(peek());
        return token;
    }
    Lexer.Token name() {
        if (!peek().isName())
            throw new SyntaxFailure(peek());
        return expect("identifier");
    }
    void recover() {
        while (!Set.of(";;", "EOF").contains(peek().kind()))
            index++;
        accept(";;");
    }
    Item item() {
        if (accept("val") != null) {
            Lexer.Token name = name();
            expect(":");
            TypeExpr declared = typeExpression();
            expect(";;");
            return new Signature(name, declared);
        }
        Lexer.Token opening = accept("let");
        Item item;
        if (opening != null) {
            Group group = group();
            item = accept("in") != null
                       ? new ExpressionItem(new Let(group, expression(), opening.position()))
                       : new Declaration(group);
        } else
            item = new ExpressionItem(expression());
        expect(";;");
        return item;
    }
    Group group() {
        Lexer.Token rec = accept("rec");
        List<Binding> bindings = new ArrayList<>();
        bindings.add(binding());
        while (accept("and") != null)
            bindings.add(binding());
        return new Group(bindings, rec == null ? null : rec.position());
    }
    Binding binding() {
        Lexer.Token name = name();
        List<Lexer.Token> parameters = new ArrayList<>();
        while (peek().kind().equals("identifier"))
            parameters.add(expect("identifier"));
        expect("=");
        Expr expression = expression();
        for (int i = parameters.size() - 1; i >= 0; i--)
            expression = new Fun(parameters.get(i), expression, parameters.get(i).position());
        return new Binding(name, expression);
    }
    Expr expression() {
        Lexer.Token opening = accept("let");
        if (opening != null) {
            Group group = group();
            expect("in");
            return new Let(group, expression(), opening.position());
        }
        opening = accept("fun");
        if (opening != null) {
            List<Lexer.Token> parameters = new ArrayList<>();
            parameters.add(expect("identifier"));
            while (peek().kind().equals("identifier"))
                parameters.add(expect("identifier"));
            expect("->");
            Expr expression = expression();
            for (int i = parameters.size() - 1; i >= 0; i--)
                expression = new Fun(parameters.get(i), expression,
                                     i == 0 ? opening.position() : parameters.get(i).position());
            return expression;
        }
        opening = accept("if");
        if (opening != null) {
            Expr condition = expression();
            expect("then");
            Expr yes = expression();
            expect("else");
            return new Conditional(condition, yes, expression(), opening.position());
        }
        opening = accept("match");
        if (opening != null) {
            Expr matched = expression();
            expect("with");
            accept("|");
            List<Arm> arms = new ArrayList<>();
            arms.add(arm());
            while (accept("|") != null)
                arms.add(arm());
            return new Match(matched, arms, opening.position());
        }
        return binary(1);
    }
    Arm arm() {
        Pattern pattern = pattern();
        expect("->");
        return new Arm(pattern, expression());
    }
    Expr binary(int minimum) {
        Expr expression = unary();
        while (OPERATORS.containsKey(peek().kind())) {
            Operator operator = OPERATORS.get(peek().kind());
            if (operator.precedence() < minimum)
                break;
            Lexer.Token token = tokens.get(index++);
            Expr right = binary(operator.precedence() + (operator.right() ? 0 : 1));
            expression = new Binary(expression, token, right);
        }
        return expression;
    }
    boolean startsAtom() {
        return Set.of("integer", "string", "true", "false", "(", "[").contains(peek().kind()) ||
            peek().isName();
    }
    Expr unary() {
        Lexer.Token operator = accept("-");
        if (operator != null)
            return new Negate(operator, unary());
        Expr expression = atom();
        while (startsAtom())
            expression = new Apply(expression, atom());
        return expression;
    }
    Expr atom() {
        Lexer.Token token = peek();
        if (Set.of("integer", "string", "true", "false").contains(token.kind())) {
            index++;
            return new Literal(token.kind().equals("true") || token.kind().equals("false")
                                   ? "boolean"
                                   : token.kind(),
                               token.value(), token.position());
        }
        if (token.isName()) {
            index++;
            return new Name(token);
        }
        if (accept("(") != null) {
            Expr first = expression();
            if (accept(",") != null) {
                Expr second = expression();
                expect(")");
                return new Pair(first, second, token.position());
            }
            expect(")");
            return first;
        }
        if (accept("[") != null) {
            List<Expr> elements = new ArrayList<>();
            if (accept("]") == null) {
                elements.add(expression());
                while (accept(";") != null)
                    elements.add(expression());
                expect("]");
            }
            return new ListExpr(elements, token.position());
        }
        throw new SyntaxFailure(token);
    }
    Pattern pattern() {
        Pattern first = patternAtom();
        return accept("::") != null ? new Cons(first, pattern()) : first;
    }
    Pattern patternAtom() {
        Lexer.Token token = peek();
        if (token.kind().equals("identifier")) {
            index++;
            return token.spelling().equals("_") ? new Wildcard(token.position())
                                                : new PatternName(token);
        }
        if (accept("-") != null) {
            Lexer.Token integer = expect("integer");
            return new PatternLiteral("integer", Long.toString(-Long.parseLong(integer.value())),
                                      token.position());
        }
        if (Set.of("integer", "string", "true", "false").contains(token.kind())) {
            index++;
            return new PatternLiteral(token.kind().equals("true") || token.kind().equals("false")
                                          ? "boolean"
                                          : token.kind(),
                                      token.value(), token.position());
        }
        if (accept("(") != null) {
            Pattern first = pattern();
            if (accept(",") != null) {
                Pattern second = pattern();
                expect(")");
                return new PatternPair(first, second, token.position());
            }
            expect(")");
            return first;
        }
        if (accept("[") != null) {
            List<Pattern> elements = new ArrayList<>();
            if (accept("]") == null) {
                elements.add(pattern());
                while (accept(";") != null)
                    elements.add(pattern());
                expect("]");
            }
            return new PatternList(elements, token.position());
        }
        throw new SyntaxFailure(token);
    }
    TypeExpr typeExpression() {
        TypeExpr first = listType();
        if (accept("*") != null)
            first = new TypeConstructor("pair", List.of(first, listType()));
        if (accept("->") != null)
            first = new TypeConstructor("function", List.of(first, typeExpression()));
        return first;
    }
    TypeExpr listType() {
        TypeExpr expression = typeAtom();
        while (peek().kind().equals("identifier") && peek().spelling().equals("list")) {
            index++;
            expression = new TypeConstructor("list", List.of(expression));
        }
        return expression;
    }
    TypeExpr typeAtom() {
        Lexer.Token token = peek();
        if (token.kind().equals("identifier") &&
            Set.of("int", "bool", "string").contains(token.spelling())) {
            index++;
            return new TypeName(token.spelling());
        }
        if (accept("type_variable") != null)
            return new TypeVariableName(token.spelling());
        if (accept("(") != null) {
            TypeExpr expression = typeExpression();
            expect(")");
            return expression;
        }
        throw new SyntaxFailure(token);
    }
}
