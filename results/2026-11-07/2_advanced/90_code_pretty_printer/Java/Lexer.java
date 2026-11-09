import java.util.*;
final class Lexer {
    static final Set<String>
        KEYWORDS = Set.of(
            "int float bool string void if else while for return break continue true false switch case default"
                .split(" ")),
        TYPES = Set.of("int", "float", "bool", "string", "void"),
        DOUBLE = Set.of("<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%="),
        ASSIGNMENT = Set.of("=", "+=", "-=", "*=", "/=", "%=");
    static final class SourceError extends RuntimeException {
        int line, column;
        SourceError(int line, int column, String message) {
            super(message);
            this.line = line;
            this.column = column;
        }
    }
    static abstract class Entry {
        String kind, text;
        int line, column, blank;
        Entry(String kind, String text, int line, int column, int blank) {
            this.kind = kind;
            this.text = text;
            this.line = line;
            this.column = column;
            this.blank = blank;
        }
    }
    static final class Comment extends Entry {
        boolean ownLine;
        Comment(String kind, String text, int line, int column, int blank) {
            super(kind, text, line, column, blank);
        }
    }
    static final class Token extends Entry {
        int index;
        List<Comment> leading = new ArrayList<>(), trailing = new ArrayList<>();
        boolean allowed, trailingComma, originalTrailing;
        Token(String kind, String text, int line, int column, int blank, int index) {
            super(kind, text, line, column, blank);
            this.index = index;
        }
    }
    record Lexed(List<Token> tokens, List<Comment> comments, List<Entry> items) {}
    static boolean letter(char c) { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'; }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static String trim(String s) {
        int end = s.length();
        while (end > 0 && s.charAt(end - 1) == ' ')
            end--;
        return s.substring(0, end);
    }
    static Lexed analyze(List<String> lines) {
        List<Token> tokens = new ArrayList<>();
        List<Comment> comments = new ArrayList<>();
        List<Entry> items = new ArrayList<>();
        int previous = 0;
        for (int row = 0; row < lines.size(); row++) {
            String line = lines.get(row);
            int pos = 0;
            while (pos < line.length()) {
                char ch = line.charAt(pos);
                if (ch == ' ') {
                    pos++;
                    continue;
                }
                int start = pos;
                String kind, text;
                if (line.startsWith("//", pos)) {
                    kind = "line_comment";
                    pos = line.length();
                    text = trim(line.substring(start));
                } else if (line.startsWith("/*", pos)) {
                    int end = line.indexOf("*/", pos + 2);
                    if (end < 0)
                        throw new SourceError(row + 1, pos + 1, "unterminated comment");
                    kind = "block_comment";
                    pos = end + 2;
                    text = line.substring(start, pos);
                } else if (letter(ch) || ch == '_') {
                    pos++;
                    while (pos < line.length() &&
                           (letter(line.charAt(pos)) || digit(line.charAt(pos)) ||
                            line.charAt(pos) == '_'))
                        pos++;
                    text = line.substring(start, pos);
                    kind = KEYWORDS.contains(text) ? "keyword" : "identifier";
                } else if (digit(ch)) {
                    pos++;
                    while (pos < line.length() && digit(line.charAt(pos)))
                        pos++;
                    if (pos + 1 < line.length() && line.charAt(pos) == '.' &&
                        digit(line.charAt(pos + 1))) {
                        pos += 2;
                        while (pos < line.length() && digit(line.charAt(pos)))
                            pos++;
                    }
                    kind = "number";
                    text = line.substring(start, pos);
                } else if (ch == '"') {
                    pos++;
                    boolean closed = false;
                    while (pos < line.length()) {
                        if (line.charAt(pos) == '\\')
                            pos += 2;
                        else if (line.charAt(pos) == '"') {
                            pos++;
                            closed = true;
                            break;
                        } else
                            pos++;
                    }
                    if (!closed)
                        throw new SourceError(row + 1, start + 1, "unterminated string");
                    kind = "string";
                    text = line.substring(start, pos);
                } else if (pos + 1 < line.length() &&
                           DOUBLE.contains(line.substring(pos, pos + 2))) {
                    pos += 2;
                    kind = "symbol";
                    text = line.substring(start, pos);
                } else if ("+-*/%<>=!()[]{},;.?:".indexOf(ch) >= 0) {
                    pos++;
                    kind = "symbol";
                    text = String.valueOf(ch);
                } else
                    throw new SourceError(row + 1, start + 1, "unexpected character '" + ch + "'");
                int blank = Math.max(0, row + 1 - previous - 1);
                previous = row + 1;
                Entry entry;
                if (kind.endsWith("_comment")) {
                    Comment comment = new Comment(kind, text, row + 1, start + 1, blank);
                    comments.add(comment);
                    entry = comment;
                } else {
                    Token token = new Token(kind, text, row + 1, start + 1, blank, tokens.size());
                    tokens.add(token);
                    entry = token;
                }
                items.add(entry);
            }
        }
        Token end = new Token("end", "", lines.size() + 1, 1, 0, tokens.size());
        end.allowed = true;
        tokens.add(end);
        return new Lexed(tokens, comments, items);
    }
}
