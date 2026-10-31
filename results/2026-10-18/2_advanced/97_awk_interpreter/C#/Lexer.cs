readonly record struct Position(int Line, int Column) : IComparable<Position> {
    public int CompareTo(Position other) {
        int order = Line.CompareTo(other.Line);
        return order == 0 ? Column.CompareTo(other.Column) : order;
    }
    public override string ToString() => $"{Line}:{Column}";
}
sealed class SyntaxError(Position position) : Exception {
    public Position Position {
        get;
    } = position;
}
sealed record Token(string Kind, string Text, string Value, Position Position);
static class Lexer {
    public static bool Letter(char c) => c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    public static bool Digit(char c) => c >= '0' && c <= '9';
    public static List<Token> Lex(string text) {
        List<Position> positions = new();
        int line = 1, column = 1;
        foreach (char c in text) {
            positions.Add(new(line, column));
            if (c == 10) {
                line++;
                column = 1;
            } else column++;
        }
        positions.Add(new(line, column));
        List<Token> result = new();
        int i = 0;
        HashSet<string> keywords = new(new[] {
            "BEGIN", "END", "function", "if", "else", "while", "for", "do", "break", "continue", "next", "exit", "return", "delete", "in", "getline", "print", "printf"
        }, StringComparer.Ordinal);
        HashSet<string> builtins = new(new[] {
            "length", "substr", "index", "split", "sprintf", "toupper", "tolower", "close", "int"
        }, StringComparer.Ordinal);
        HashSet<string> symbols = new(new[] {
            "+=", "-=", "*=", "/=", "%=", "^=", "==", "<=", ">=", "!=", "++", "--", "&&", "||", ">>"
        }, StringComparer.Ordinal);
        while (i < text.Length) {
            if (text[i] == ' ') {
                i++;
                continue;
            }
            if (text[i] == 92 && i + 1 < text.Length && text[i + 1] == 10) {
                i += 2;
                continue;
            }
            if (text[i] == '#') {
                while (i < text.Length && text[i] != 10) i++;
                continue;
            }
            int start = i;
            string kind = "symbol", value = "";
            if (text[i] == 10) {
                i++;
                kind = "newline";
            }
            else if (Digit(text[i])) {
                while (i < text.Length && Digit(text[i])) i++;
                kind = "number";
            }
            else if (Letter(text[i]) || text[i] == '_') {
                while (i < text.Length && (Letter(text[i]) || Digit(text[i]) || text[i] == '_')) i++;
                string name = text[start..i];
                kind = keywords.Contains(name) ? "keyword" : builtins.Contains(name) ? "builtin" : i < text.Length && text[i] == '(' ? "function" : "name";
            } else if (text[i] == 34) {
                i++;
                bool closed = false;
                StringBuilder decoded = new();
                while (i < text.Length) {
                    if (text[i] == 10) throw new SyntaxError(positions[start]);
                    if (text[i] == 34) {
                        i++;
                        closed = true;
                        break;
                    }
                    if (text[i] == 92) {
                        int slash = i++;
                        if (i == text.Length) throw new SyntaxError(positions[start]);
                        decoded.Append(text[i] switch {
                            'n' => (char)10, 't' => (char)9, (char)92 or (char)34 or '/' => text[i], _ => throw new SyntaxError(positions[slash])
                        });
                        i++;
                    }
                    else decoded.Append(text[i++]);
                }
                if (!closed) throw new SyntaxError(positions[start]);
                kind = "string";
                value = decoded.ToString();
            } else if (i + 1 < text.Length && symbols.Contains(text.Substring(i, 2))) i += 2;
            else if ("+-*/%^!><?:=()[]{},;$".Contains(text[i])) i++;
            else throw new SyntaxError(positions[i]);
            result.Add(new(kind, text[start..i], value, positions[start]));
        }
        result.Add(new("end", "", "", positions.Last()));
        return result;
    }
}
