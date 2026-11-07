import java.math.BigInteger;
import java.util.*;
final class Reader {
    static final String SYMBOLS = "+-*/\\^<>=~:.?@#&$";
    record Operator(int priority, int left, int right) {}
    static final Map<String, Operator> INFIX = new HashMap<>();
    static final Map<String, Integer> PREFIX = Map.of("\\+", 900, "-", 200);
    static {
        operators(1200, "xfx", ":-");
        operators(1100, "xfy", ";");
        operators(1050, "xfy", "->");
        operators(1000, "xfy", ",");
        operators(700, "xfx", "=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<",
                  ">=", "=..");
        operators(500, "yfx", "+", "-");
        operators(400, "yfx", "*", "/", "//", "mod", "rem");
    }
    static void operators(int priority, String kind, String... names) {
        for (String name : names)
            INFIX.put(name, new Operator(priority, kind.equals("yfx") ? priority : priority - 1,
                                         kind.equals("xfy") ? priority : priority - 1));
    }
    enum Kind { INTEGER, VARIABLE, NAME, QUOTED, PUNCT, END, INVALID, EOF }
    record Token(Kind kind, String value, String spelling, int line, int column, boolean space,
                 int index) {}
    static final class SyntaxIssue extends RuntimeException {
        final Token token;
        SyntaxIssue(Token token) {
            this(token, switch (token.kind()) {
                case INVALID -> token.value();
                case EOF -> "unexpected end of file";
                case END -> "unexpected end of clause";
                default ->
                    token.kind() == Kind.NAME &&INFIX.containsKey(token.value())
                        ? "operator priority clash"
                        : "unexpected \"" + token.spelling() + "\"";
            });
        }
        SyntaxIssue(Token token, String message) {
            super(message);
            this.token = token;
        }
    }
    static boolean lower(char c) { return c >= 'a' && c <= 'z'; }
    static boolean upper(char c) { return c >= 'A' && c <= 'Z'; }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static boolean alphanumeric(char c) { return lower(c) || upper(c) || digit(c) || c == '_'; }
    static List<Token> tokenize(String text, int column) {
        List<Token> result = new ArrayList<>();
        int position = 0, line = 1;
        boolean space = true;
        while (position < text.length()) {
            char c = text.charAt(position);
            if (c == ' ' || c == '\n') {
                if (c == '\n') {
                    line++;
                    column = 1;
                } else
                    column++;
                position++;
                space = true;
                continue;
            }
            if (c == '%') {
                int end = text.indexOf('\n', position);
                if (end < 0)
                    end = text.length();
                column += end - position;
                position = end;
                space = true;
                continue;
            }
            int start = position, startColumn = column;
            Kind kind;
            String value;
            if (digit(c)) {
                position++;
                while (position < text.length() && digit(text.charAt(position)))
                    position++;
                value = text.substring(start, position);
                kind = new BigInteger(value).compareTo(BigInteger.valueOf(Integer.MAX_VALUE)) > 0
                           ? Kind.INVALID
                           : Kind.INTEGER;
                if (kind == Kind.INVALID)
                    value = "integer too large";
            } else if (lower(c) || upper(c) || c == '_') {
                position++;
                while (position < text.length() && alphanumeric(text.charAt(position)))
                    position++;
                value = text.substring(start, position);
                kind = lower(c) ? Kind.NAME : Kind.VARIABLE;
            } else if (SYMBOLS.indexOf(c) >= 0) {
                position++;
                while (position < text.length() && SYMBOLS.indexOf(text.charAt(position)) >= 0)
                    position++;
                value = text.substring(start, position);
                kind = value.equals(".") && (position == text.length() ||
                                             " \n%".indexOf(text.charAt(position)) >= 0)
                           ? Kind.END
                           : Kind.NAME;
            } else if (c == '!' || c == ';') {
                position++;
                kind = Kind.NAME;
                value = String.valueOf(c);
            } else if (",|()[]".indexOf(c) >= 0) {
                position++;
                kind = Kind.PUNCT;
                value = String.valueOf(c);
            } else if (c == '\'') {
                position++;
                StringBuilder represented = new StringBuilder();
                boolean incorrect = false;
                while (true) {
                    if (position == text.length() || text.charAt(position) == '\n') {
                        kind = Kind.INVALID;
                        value = "unterminated quoted atom";
                        break;
                    }
                    char current = text.charAt(position);
                    if (current == '\'') {
                        if (position + 1 < text.length() && text.charAt(position + 1) == '\'') {
                            represented.append('\'');
                            position += 2;
                        } else {
                            position++;
                            kind = incorrect ? Kind.INVALID : Kind.QUOTED;
                            value =
                                incorrect ? "undefined escape sequence" : represented.toString();
                            break;
                        }
                    } else if (current == '\\') {
                        position++;
                        if (position < text.length() && text.charAt(position) != '\n') {
                            char escaped = text.charAt(position++);
                            if ("nt\\'".indexOf(escaped) < 0)
                                incorrect = true;
                            represented.append(switch (escaped) {
                                case 'n' -> '\n';
                                case 't' -> '\t';
                                default -> escaped;
                            });
                        }
                    } else {
                        represented.append(current);
                        position++;
                    }
                }
            } else {
                position++;
                kind = Kind.INVALID;
                value = "illegal character '" + c + "'";
            }
            result.add(new Token(kind, value, text.substring(start, position), line, startColumn,
                                 space, result.size()));
            column += position - start;
            space = false;
        }
        result.add(new Token(Kind.EOF, null, "", line, column, space, result.size()));
        return result;
    }
    final List<Token> tokens;
    int position;
    final LinkedHashMap<String, Terms.Variable> names = new LinkedHashMap<>();
    final LinkedHashMap<String, Integer> counts = new LinkedHashMap<>();
    Reader(String text) { this(text, 1); }
    Reader(String text, int column) { tokens = tokenize(text, column); }
    Token peek() { return tokens.get(position); }
    Token take() {
        Token token = peek();
        if (token.kind() != Kind.EOF)
            position++;
        return token;
    }
    boolean punctuation(String value) {
        return peek().kind() == Kind.PUNCT && peek().value().equals(value);
    }
    void expect(String value) {
        Token token = take();
        if (token.kind() != Kind.PUNCT || !token.value().equals(value))
            throw new SyntaxIssue(token);
    }
    Terms.Term clause(boolean query) {
        names.clear();
        counts.clear();
        Terms.Term term = term(1200).term();
        Token token = take();
        if (token.kind() != Kind.END)
            throw new SyntaxIssue(token);
        if (query && peek().kind() != Kind.EOF)
            throw new SyntaxIssue(peek());
        return term;
    }
    record Parsed(Terms.Term term, int priority) {}
    Parsed term(int limit) {
        Parsed parsed = primary(limit);
        while (true) {
            Token token = peek();
            boolean operator = token.kind() == Kind.NAME && INFIX.containsKey(token.value()) ||
                               token.kind() == Kind.PUNCT && token.value().equals(",");
            if (!operator)
                return parsed;
            Operator op = INFIX.get(token.value());
            if (op.priority() > limit || parsed.priority() > op.left())
                return parsed;
            take();
            Terms.Term right = term(op.right()).term();
            parsed = new Parsed(Terms.compound(token.value(), parsed.term(), right), op.priority());
        }
    }
    boolean canStart() {
        Token token = peek();
        return token.kind() == Kind.INTEGER || token.kind() == Kind.VARIABLE ||
            token.kind() == Kind.QUOTED ||
            token.kind() == Kind.PUNCT &&
                (token.value().equals("(") || token.value().equals("[")) ||
            token.kind() == Kind.NAME &&
                (!INFIX.containsKey(token.value()) || PREFIX.containsKey(token.value()));
    }
    Parsed primary(int limit) {
        Token token = take();
        if (token.kind() == Kind.INTEGER)
            return new Parsed(Terms.integer(Integer.parseInt(token.value())), 0);
        if (token.kind() == Kind.VARIABLE) {
            String name = token.value();
            counts.merge(name, 1, Integer::sum);
            return new Parsed(name.equals("_")
                                  ? new Terms.Variable()
                                  : names.computeIfAbsent(name, key -> new Terms.Variable()),
                              0);
        }
        if (token.kind() == Kind.PUNCT && token.value().equals("(")) {
            Terms.Term term = term(1200).term();
            expect(")");
            return new Parsed(term, 0);
        }
        if (token.kind() == Kind.PUNCT && token.value().equals("[")) {
            if (punctuation("]")) {
                take();
                return new Parsed(Terms.NIL, 0);
            }
            List<Terms.Term> elements = new ArrayList<>();
            elements.add(term(999).term());
            while (punctuation(",")) {
                take();
                elements.add(term(999).term());
            }
            Terms.Term tail = Terms.NIL;
            if (punctuation("|")) {
                take();
                tail = term(999).term();
            }
            expect("]");
            return new Parsed(Terms.list(elements, tail), 0);
        }
        if (token.kind() == Kind.NAME || token.kind() == Kind.QUOTED) {
            if (punctuation("(") && !peek().space()) {
                take();
                List<Terms.Term> arguments = new ArrayList<>();
                arguments.add(term(999).term());
                while (punctuation(",")) {
                    take();
                    arguments.add(term(999).term());
                }
                expect(")");
                return new Parsed(new Terms.Compound(token.value(), arguments), 0);
            }
            if (token.kind() == Kind.NAME && token.value().equals("-") &&
                peek().kind() == Kind.INTEGER && !peek().space())
                return new Parsed(Terms.integer(-Integer.parseInt(take().value())), 0);
            if (token.kind() == Kind.NAME && PREFIX.containsKey(token.value()) && canStart()) {
                int priority = PREFIX.get(token.value());
                if (priority > limit)
                    throw new SyntaxIssue(token, "operator priority clash");
                return new Parsed(Terms.compound(token.value(), term(priority).term()), priority);
            }
            return new Parsed(Terms.atom(token.value()), 0);
        }
        throw new SyntaxIssue(token);
    }
}
