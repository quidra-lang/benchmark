import java.util.*;
final class Lexer {
    record Position(String file, int line, int column) implements Comparable<Position> {
        public int compareTo(Position other) {
            int order = file.compareTo(other.file);
            if (order == 0)
                order = Integer.compare(line, other.line);
            return order == 0 ? Integer.compare(column, other.column) : order;
        }
    }
    record Token(String kind, String spelling, String value, Position position) {
        boolean isName() { return kind.equals("identifier") && !spelling.equals("_"); }
    }
    static final Set<String>
        KEYWORDS =
            Set.of("let rec and in fun if then else match with true false mod val".split(" ")),
        SYMBOLS = Set.of(";; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |".split(" "));
    static boolean letter(char c) { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'; }
    static boolean word(char c) { return letter(c) || c >= '0' && c <= '9' || c == '_'; }
    static List<Token> tokenize(String source, String file) {
        List<Token> tokens = new ArrayList<>();
        int index = 0, line = 1, column = 1;
        while (index < source.length()) {
            int start = index;
            Position position = new Position(file, line, column);
            char character = source.charAt(index);
            String kind = null, value = null;
            if (character == ' ' || character == '\n')
                index++;
            else if (source.startsWith("(*", index)) {
                int closing = source.indexOf("*)", index + 2);
                if (closing < 0) {
                    kind = "invalid";
                    value = "unterminated comment";
                    index = source.length();
                } else
                    index = closing + 2;
            } else if (character >= '0' && character <= '9') {
                index++;
                while (index < source.length() && source.charAt(index) >= '0' &&
                       source.charAt(index) <= '9')
                    index++;
                String digits = source.substring(start, index).replaceFirst("^0+", "");
                if (digits.isEmpty())
                    digits = "0";
                if (digits.length() > 10 ||
                    digits.length() == 10 && digits.compareTo("2147483647") > 0) {
                    kind = "invalid";
                    value = "integer literal too large";
                } else {
                    kind = "integer";
                    value = digits;
                }
            } else if (letter(character) || character == '_') {
                index++;
                while (index < source.length() &&
                       (word(source.charAt(index)) || source.charAt(index) == '\''))
                    index++;
                value = source.substring(start, index);
                kind = KEYWORDS.contains(value) ? value : "identifier";
            } else if (character == '\'' && index + 1 < source.length() &&
                       source.charAt(index + 1) >= 'a' && source.charAt(index + 1) <= 'z') {
                index += 2;
                while (index < source.length() && word(source.charAt(index)))
                    index++;
                kind = "type_variable";
                value = source.substring(start, index);
            } else if (character == '"') {
                index++;
                StringBuilder decoded = new StringBuilder();
                boolean invalid = false;
                while (index < source.length() && source.charAt(index) != '"' &&
                       source.charAt(index) != '\n') {
                    char c = source.charAt(index);
                    if (c == '\\' && index + 1 < source.length() &&
                        source.charAt(index + 1) != '\n') {
                        char escape = source.charAt(index + 1);
                        switch (escape) {
                        case 'n' -> decoded.append('\n');
                        case 't' -> decoded.append('\t');
                        case '\\' -> decoded.append('\\');
                        case '"' -> decoded.append('"');
                        default -> invalid = true;
                        }
                        index += 2;
                    } else {
                        decoded.append(c);
                        index++;
                    }
                }
                if (index == source.length() || source.charAt(index) == '\n') {
                    kind = "invalid";
                    value = "unterminated string";
                } else {
                    index++;
                    kind = invalid ? "invalid" : "string";
                    value = invalid ? "invalid escape sequence" : decoded.toString();
                }
            } else {
                String symbol =
                    index + 1 < source.length() ? source.substring(index, index + 2) : "";
                if (SYMBOLS.contains(symbol))
                    index += 2;
                else {
                    symbol = String.valueOf(character);
                    index++;
                }
                if (SYMBOLS.contains(symbol))
                    kind = value = symbol;
                else {
                    kind = "invalid";
                    value = "illegal character '" + character + "'";
                }
            }
            String consumed = source.substring(start, index);
            if (kind != null)
                tokens.add(new Token(kind, consumed, value, position));
            for (int i = start; i < index; i++)
                if (source.charAt(i) == '\n') {
                    line++;
                    column = 1;
                } else
                    column++;
        }
        tokens.add(new Token("EOF", "", null, new Position(file, line, 1)));
        return tokens;
    }
}
