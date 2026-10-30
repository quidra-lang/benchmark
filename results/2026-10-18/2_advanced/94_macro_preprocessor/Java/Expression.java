import java.util.*;
import java.util.function.Consumer;
final class Expression {
    static final List<Set<String>> LEVELS = List.of(
        Set.of("||"), Set.of("&&"), Set.of("|"), Set.of("^"), Set.of("&"), Set.of("==", "!="),
        Set.of("<", ">", "<=", ">="), Set.of("<<", ">>"), Set.of("+", "-"), Set.of("*", "/", "%"));
    static final class ExpressionError extends RuntimeException {
        ExpressionError(String message) { super(message); }
    }
    sealed interface Node permits Constant, Identifier, Unary, Binary, Conditional {}
    record Constant(long value) implements Node {}
    record Identifier(String name) implements Node {}
    record Unary(String operator, Node operand) implements Node {}
    record Binary(String operator, Node first, Node second) implements Node {}
    record Conditional(Node condition, Node yes, Node no) implements Node {}
    static long integerValue(String spelling) {
        String value = spelling;
        for (String suffix : List.of("ll", "LL", "l", "L"))
            if (value.endsWith(suffix) && value.length() > suffix.length()) {
                value = value.substring(0, value.length() - suffix.length());
                break;
            }
        if (value.matches("0[xX][0-9a-fA-F]+"))
            return Long.parseLong(value.substring(2), 16);
        if (value.matches("0[0-7]*"))
            return Long.parseLong(value, 8);
        if (value.matches("[1-9][0-9]*"))
            return Long.parseLong(value);
        throw new ExpressionError("invalid integer constant \"" + spelling + "\"");
    }
    static long characterValue(String spelling) {
        String value = spelling.substring(1, spelling.length() - 1);
        if (value.length() == 1 && value.charAt(0) != '\'' && value.charAt(0) != '\\')
            return value.charAt(0);
        if (value.length() == 2 && value.charAt(0) == '\\') {
            int result = switch (value.charAt(1)) {
                case 'n' -> 10;
                case 't' -> 9;
                case '\\' -> 92;
                case '\'' -> 39;
                case '"' -> 34;
                case '0' -> 0;
                default -> -1;
            };
            if (result >= 0)
                return result;
        }
        throw new ExpressionError("invalid character constant " + spelling);
    }
    List<Lexer.Token> tokens;
    int position;
    Expression(List<Lexer.Token> tokens) { this.tokens = tokens; }
    String peek() { return position < tokens.size() ? tokens.get(position).spelling() : null; }
    Node expression() {
        Node left = binary(0);
        if ("?".equals(peek())) {
            position++;
            Node yes = expression();
            if (!":".equals(peek()))
                throw new ExpressionError("'?' without following ':'");
            position++;
            left = new Conditional(left, yes, expression());
        }
        return left;
    }
    Node binary(int level) {
        if (level == LEVELS.size())
            return unary();
        Node left = binary(level + 1);
        while (peek() != null && LEVELS.get(level).contains(peek())) {
            String operator = peek();
            position++;
            left = new Binary(operator, left, binary(level + 1));
        }
        return left;
    }
    Node unary() {
        String next = peek();
        if (next != null && Set.of("+", "-", "!", "~").contains(next)) {
            position++;
            return new Unary(next, unary());
        }
        if (position == tokens.size())
            throw new ExpressionError("expected value at end of expression");
        Lexer.Token token = tokens.get(position++);
        if (token.kind().equals("number"))
            return new Constant(integerValue(token.spelling()));
        if (token.kind().equals("character"))
            return new Constant(characterValue(token.spelling()));
        if (token.kind().equals("identifier"))
            return new Identifier(token.spelling());
        if (token.spelling().equals("(")) {
            Node node = expression();
            if (!")".equals(peek()))
                throw new ExpressionError("missing ')' in expression");
            position++;
            return node;
        }
        throw new ExpressionError("expected value before \"" + token.spelling() + "\"");
    }
    static Node parse(List<Lexer.Token> tokens, String directive) {
        if (tokens.isEmpty())
            throw new ExpressionError("#" + directive + " with no expression");
        Expression parser = new Expression(tokens);
        Node tree = parser.expression();
        if (parser.peek() != null)
            throw new ExpressionError("missing binary operator before \"" + parser.peek() + "\"");
        return tree;
    }
    static long binaryValue(String operator, long a, long b) {
        if ((operator.equals("/") || operator.equals("%")) && b == 0)
            throw new ExpressionError("division by zero in #if");
        return switch (operator) {
            case "/" -> a / b;
            case "%" -> a % b;
            case "+" -> a + b;
            case "-" -> a - b;
            case "*" -> a *b;
            case "<<" -> a << b;
            case ">>" -> a >> b;
            case "&" -> a & b;
            case "|" -> a | b;
            case "^" -> a ^ b;
            case "==" -> a == b ? 1 : 0;
            case "!=" -> a != b ? 1 : 0;
            case "<" -> a < b ? 1 : 0;
            case ">" -> a > b ? 1 : 0;
            case "<=" -> a <= b ? 1 : 0;
            default -> a >= b ? 1 : 0;
        };
    }
    record Work(String operation, Node node, String operator) {}
    static long evaluate(Node tree, Consumer<String> warning) {
        Deque<Work> pending = new ArrayDeque<>();
        Deque<Long> values = new ArrayDeque<>();
        pending.push(new Work("evaluate", tree, null));
        while (!pending.isEmpty()) {
            Work work = pending.pop();
            switch (work.operation()) {
            case "evaluate" -> {
                switch (work.node()) {
                case Constant constant -> values.push(constant.value());
                case Identifier identifier -> {
                    warning.accept("identifier \"" + identifier.name() + "\" evaluates to 0");
                    values.push(0L);
                }
                case Unary unary -> {
                    pending.push(new Work("unary", null, unary.operator()));
                    pending.push(new Work("evaluate", unary.operand(), null));
                }
                case Conditional conditional -> {
                    pending.push(new Work("choose", conditional, null));
                    pending.push(new Work("evaluate", conditional.condition(), null));
                }
                case Binary binary -> {
                    if (Set.of("&&", "||").contains(binary.operator())) {
                        pending.push(new Work("logical", binary.second(), binary.operator()));
                        pending.push(new Work("evaluate", binary.first(), null));
                    } else {
                        pending.push(new Work("binary", null, binary.operator()));
                        pending.push(new Work("evaluate", binary.second(), null));
                        pending.push(new Work("evaluate", binary.first(), null));
                    }
                }
                }
            }
            case "choose" -> {
                Conditional conditional = (Conditional)work.node();
                pending.push(new Work(
                    "evaluate", values.pop() != 0 ? conditional.yes() : conditional.no(), null));
            }
            case "logical" -> {
                long first = values.pop();
                if (work.operator().equals("&&") && first == 0 ||
                    work.operator().equals("||") && first != 0)
                    values.push(first != 0 ? 1L : 0L);
                else {
                    pending.push(new Work("truth", null, null));
                    pending.push(new Work("evaluate", work.node(), null));
                }
            }
            case "truth" -> values.push(values.pop() != 0 ? 1L : 0L);
            case "unary" -> {
                long value = values.pop();
                values.push(switch (work.operator()) {
                    case "+" -> value;
                    case "-" -> -value;
                    case "!" -> value == 0 ? 1L : 0L;
                    default -> -value - 1;
                });
            }
            case "binary" -> {
                long second = values.pop(), first = values.pop();
                values.push(binaryValue(work.operator(), first, second));
            }
            }
        }
        return values.pop();
    }
}
