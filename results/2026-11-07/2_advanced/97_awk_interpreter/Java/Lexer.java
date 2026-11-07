import java.util.*;
final class Lexer {
    record Position(int line, int column) implements Comparable<Position> {
        public int compareTo(Position other) {
            int order = Integer.compare(line, other.line);
            return order != 0 ? order : Integer.compare(column, other.column);
        }
        public String toString() { return line + ":" + column; }
    }
    enum Kind { NUMBER, STRING, NAME, FUNCNAME, BUILTIN, KEYWORD, SYMBOL, NEWLINE, END }
    record Token(Kind kind, String text, String value, Position pos) {}
    static final class SyntaxIssue extends RuntimeException {
        final Position pos;
        SyntaxIssue(Position pos) { this.pos = pos; }
    }
    static final Set<String> KEYWORDS =
                                 Set.of("BEGIN", "END", "function", "if", "else", "while", "for",
                                        "do", "break", "continue", "next", "exit", "return",
                                        "delete", "in", "getline", "print", "printf"),
                             BUILTINS = Set.of("length", "substr", "index", "split", "sprintf",
                                               "toupper", "tolower", "close", "int"),
                             PAIRS = Set.of("+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=",
                                            "!=", "++", "--", "&&", "||", ">>");
    static boolean letter(char c) {
        return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_';
    }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static List<Token> tokenize(String source) {
        List<Token> result = new ArrayList<>();
        int index = 0, line = 1, column = 1;
        while (index < source.length()) {
            char c = source.charAt(index);
            Position start = new Position(line, column);
            if (c == ' ') {
                index++;
                column++;
                continue;
            }
            if (c == '\\' && index + 1 < source.length() && source.charAt(index + 1) == '\n') {
                index += 2;
                line++;
                column = 1;
                continue;
            }
            if (c == '#') {
                int end = source.indexOf('\n', index);
                if (end < 0)
                    end = source.length();
                column += end - index;
                index = end;
                continue;
            }
            if (c == '\n') {
                result.add(new Token(Kind.NEWLINE, "\n", null, start));
                index++;
                line++;
                column = 1;
                continue;
            }
            int end = index + 1;
            Kind kind;
            String value = null;
            if (digit(c)) {
                while (end < source.length() && digit(source.charAt(end)))
                    end++;
                kind = Kind.NUMBER;
                value = source.substring(index, end);
            } else if (letter(c)) {
                while (end < source.length() &&
                       (letter(source.charAt(end)) || digit(source.charAt(end))))
                    end++;
                String word = source.substring(index, end);
                kind = KEYWORDS.contains(word)                              ? Kind.KEYWORD
                       : BUILTINS.contains(word)                            ? Kind.BUILTIN
                       : end < source.length() && source.charAt(end) == '(' ? Kind.FUNCNAME
                                                                            : Kind.NAME;
            } else if (c == '"') {
                StringBuilder text = new StringBuilder();
                while (end < source.length() && source.charAt(end) != '"') {
                    char next = source.charAt(end);
                    if (next == '\n')
                        throw new SyntaxIssue(start);
                    if (next == '\\') {
                        if (end + 1 == source.length())
                            throw new SyntaxIssue(new Position(line, column + end - index));
                        char escaped = source.charAt(end + 1);
                        if ("nt\\\"/".indexOf(escaped) < 0)
                            throw new SyntaxIssue(new Position(line, column + end - index));
                        text.append(switch (escaped) {
                            case 'n' -> '\n';
                            case 't' -> '\t';
                            default -> escaped;
                        });
                        end += 2;
                    } else {
                        text.append(next);
                        end++;
                    }
                }
                if (end == source.length())
                    throw new SyntaxIssue(start);
                end++;
                kind = Kind.STRING;
                value = text.toString();
            } else if (end < source.length() && PAIRS.contains(source.substring(index, end + 1))) {
                end++;
                kind = Kind.SYMBOL;
            } else if ("+-*/%^!><?:=()[]{},;$".indexOf(c) >= 0)
                kind = Kind.SYMBOL;
            else
                throw new SyntaxIssue(start);
            result.add(new Token(kind, source.substring(index, end), value, start));
            column += end - index;
            index = end;
        }
        result.add(new Token(Kind.END, "", null, new Position(line, 1)));
        return result;
    }
}
