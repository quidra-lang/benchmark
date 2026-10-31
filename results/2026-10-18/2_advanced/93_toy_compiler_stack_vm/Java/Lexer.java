import java.util.*;
final class Lexer {
    record Position(int line, int column) implements Comparable<Position> {
        public int compareTo(Position other) {
            int order = Integer.compare(line, other.line);
            return order == 0 ? Integer.compare(column, other.column) : order;
        }
        public String toString() { return line + ":" + column; }
    }
    record SourceLine(int number, String text) {}
    record Token(String kind, String spelling, Position position) {}
    static final Set<String>
        KEYWORDS = Set.of(
            "int bool void true false if else while for break continue return print read".split(
                " ")),
        PAIRS = Set.of("<=", ">=", "==", "!=", "&&", "||");
    static final class CompileError extends RuntimeException {
        String kind;
        Position position;
        CompileError(String kind, Position position, String message) {
            super(message);
            this.kind = kind;
            this.position = position;
        }
    }
    static boolean letter(char c) { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'; }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static List<Token> tokenize(List<SourceLine> lines) {
        StringJoiner joined = new StringJoiner("\n");
        for (SourceLine line : lines)
            joined.add(line.text());
        String source = joined + "\n";
        int line = lines.getFirst().number(), column = 1, index = 0;
        List<Token> tokens = new ArrayList<>();
        while (index < source.length()) {
            char c = source.charAt(index);
            if (c == ' ') {
                index++;
                column++;
                continue;
            }
            if (c == '\n') {
                index++;
                line++;
                column = 1;
                continue;
            }
            Position position = new Position(line, column);
            if (source.startsWith("//", index)) {
                int end = source.indexOf('\n', index);
                column += end - index;
                index = end;
                continue;
            }
            if (source.startsWith("/*", index)) {
                int end = source.indexOf("*/", index + 2);
                if (end < 0)
                    throw new CompileError("lexical", position, "unterminated comment");
                end += 2;
                while (index < end)
                    if (source.charAt(index++) == '\n') {
                        line++;
                        column = 1;
                    } else
                        column++;
                continue;
            }
            int end = index + 1;
            String spelling, kind;
            if (letter(c) || c == '_') {
                while (end < source.length() &&
                       (letter(source.charAt(end)) || digit(source.charAt(end)) ||
                        source.charAt(end) == '_'))
                    end++;
                spelling = source.substring(index, end);
                kind = KEYWORDS.contains(spelling) ? "keyword" : "identifier";
            } else if (digit(c)) {
                while (end < source.length() && digit(source.charAt(end)))
                    end++;
                spelling = source.substring(index, end);
                if (Long.parseLong(spelling) > Integer.MAX_VALUE)
                    throw new CompileError("lexical", position, "integer literal too large");
                kind = "integer";
            } else if (end < source.length() && PAIRS.contains(source.substring(index, end + 1))) {
                end++;
                spelling = source.substring(index, end);
                kind = "symbol";
            } else if ("+-*/%<>=!(){}[],;".indexOf(c) >= 0) {
                spelling = String.valueOf(c);
                kind = "symbol";
            } else
                throw new CompileError("lexical", position, "unexpected character '" + c + "'");
            tokens.add(new Token(kind, spelling, position));
            column += end - index;
            index = end;
        }
        SourceLine last = lines.getLast();
        tokens.add(new Token("end", "", new Position(last.number(), last.text().length() + 1)));
        return tokens;
    }
}
