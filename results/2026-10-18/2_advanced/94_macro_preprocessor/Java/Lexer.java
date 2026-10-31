import java.util.*;
final class Lexer {
    record Token(String kind, String spelling, int line, boolean space, Set<String> hide) {
        Token(String kind, String spelling, int line, boolean space) {
            this(kind, spelling, line, space, Set.of());
        }
        Token { hide = Set.copyOf(hide); }
        Token spaced(boolean value) { return new Token(kind, spelling, line, value, hide); }
        Token substituted(int line, boolean space, Set<String> hide) {
            return new Token(kind, spelling, line, space, hide);
        }
    }
    record LogicalLine(List<Token> tokens, int start, int end) {}
    record Read(String kind, String spelling, int end) {}
    record Spliced(String text, int[] positions) {}
    static final List<String> PUNCTUATORS = List.of(
        "...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||",
        "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##", "[", "]", "(", ")", "{", "}", ".",
        "&", "*", "+", "-", "~", "!", "/", "%", "<", ">", "^", "|", "?", ":", ";", "=", ",", "#");
    static boolean identifierStart(char c) {
        return c == '_' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z';
    }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static Read readToken(String text, int position, boolean header) {
        char c = text.charAt(position);
        int length = text.length();
        if (header && c == '<') {
            int closing = text.indexOf('>', position + 1), newline =
                                                               text.indexOf('\n', position + 1);
            if (closing >= 0 && (newline < 0 || closing < newline))
                return new Read("header", text.substring(position, closing + 1), closing + 1);
        }
        if (identifierStart(c)) {
            int end = position + 1;
            while (end < length && (identifierStart(text.charAt(end)) || digit(text.charAt(end))))
                end++;
            return new Read("identifier", text.substring(position, end), end);
        }
        if (digit(c) || c == '.' && position + 1 < length && digit(text.charAt(position + 1))) {
            int end = position + 1;
            while (end < length) {
                char next = text.charAt(end);
                if ("eEpP".indexOf(next) >= 0 && end + 1 < length &&
                    "+-".indexOf(text.charAt(end + 1)) >= 0)
                    end += 2;
                else if (identifierStart(next) || digit(next) || next == '.')
                    end++;
                else
                    break;
            }
            return new Read("number", text.substring(position, end), end);
        }
        if (c == '\'' || c == '"') {
            int end = position + 1;
            while (end < length && text.charAt(end) != '\n') {
                if (text.charAt(end) == c)
                    return new Read(c == '"' ? "string" : "character",
                                    text.substring(position, end + 1), end + 1);
                if (text.charAt(end) == '\\' && end + 1 < length && text.charAt(end + 1) != '\n')
                    end += 2;
                else
                    end++;
            }
        }
        for (String punctuator : PUNCTUATORS)
            if (text.startsWith(punctuator, position))
                return new Read("punctuator", punctuator, position + punctuator.length());
        return new Read("other", String.valueOf(c), position + 1);
    }
    static Spliced splice(String source) {
        StringBuilder text = new StringBuilder();
        List<Integer> positions = new ArrayList<>();
        int index = 0, line = 1;
        while (index < source.length()) {
            if (source.startsWith("\\\n", index)) {
                index += 2;
                line++;
                continue;
            }
            char c = source.charAt(index++);
            text.append(c);
            positions.add(line);
            if (c == '\n')
                line++;
        }
        int[] numbers = new int[positions.size()];
        for (int i = 0; i < numbers.length; i++)
            numbers[i] = positions.get(i);
        return new Spliced(text.toString(), numbers);
    }
    static List<LogicalLine> scan(String text, int[] positions, int start) {
        List<LogicalLine> lines = new ArrayList<>();
        List<Token> tokens = new ArrayList<>();
        int index = 0;
        boolean spaced = true;
        while (index < text.length()) {
            char c = text.charAt(index);
            if (c == ' ') {
                spaced = true;
                index++;
            } else if (c == '\n') {
                int end = positions[index];
                lines.add(new LogicalLine(List.copyOf(tokens), start, end));
                tokens = new ArrayList<>();
                start = end + 1;
                spaced = true;
                index++;
            } else if (text.startsWith("/*", index)) {
                int closing = text.indexOf("*/", index + 2);
                index = closing < 0 ? text.length() : closing + 2;
                spaced = true;
            } else if (text.startsWith("//", index)) {
                int closing = text.indexOf('\n', index + 2);
                index = closing < 0 ? text.length() : closing;
                spaced = true;
            } else {
                boolean header = tokens.size() == 2 && tokens.get(0).spelling().equals("#") &&
                                 tokens.get(1).spelling().equals("include");
                Read read = readToken(text, index, header);
                tokens.add(new Token(read.kind(), read.spelling(), positions[index], spaced));
                index = read.end();
                spaced = false;
            }
        }
        if (!tokens.isEmpty())
            lines.add(new LogicalLine(List.copyOf(tokens), start, positions[positions.length - 1]));
        return lines;
    }
    static List<LogicalLine> source(String text) {
        Spliced spliced = splice(text);
        return scan(spliced.text(), spliced.positions(), 1);
    }
    static List<Token> definition(String text, int line) {
        text += "\n";
        int[] positions = new int[text.length()];
        Arrays.fill(positions, line);
        List<Token> tokens = new ArrayList<>();
        for (LogicalLine logical : scan(text, positions, line))
            tokens.addAll(logical.tokens());
        return tokens;
    }
    static String render(List<Token> tokens) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < tokens.size(); i++) {
            Token token = tokens.get(i);
            if (i > 0 && token.space())
                result.append(' ');
            result.append(token.spelling());
        }
        return result.toString();
    }
    static String singleToken(String text) {
        if (text.isEmpty() || text.startsWith("//") || text.startsWith("/*"))
            return null;
        Read read = readToken(text, 0, false);
        return read.end() == text.length() ? read.kind() : null;
    }
}
