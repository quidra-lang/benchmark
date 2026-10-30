using System;
using System.Collections.Generic;
using System.Linq;
sealed class SourceError(int line, int column, string reason) : Exception(reason) {
    public int Line {
        get;
    } = line;
    public int Column {
        get;
    } = column;
    public string Reason {
        get;
    } = reason;
}
sealed record Comment(string Text, int Line, int Column, int Blank, bool LineComment) {
    public bool Own {
        get;
        set;
    }
}
sealed record Token(string Text, string Kind, int Line, int Column, int Blank) {
    public List<Comment> Leading {
        get;
    } = new();
    public List<Comment> Trailing {
        get;
    } = new();
}
readonly record struct Occurrence(bool IsToken, int Index);
sealed class Lexed {
    public List<Token> Tokens {
        get;
    } = new();
    public List<Comment> Comments {
        get;
    } = new();
    public List<Occurrence> Order {
        get;
    } = new();
}
static class Lexer {
    public static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    public static bool Digit(char c) => c is >= '0' and <= '9';
    public static string Trim(string text) => text.TrimEnd(' ');
    public static Lexed Lex(IReadOnlyList<string> lines) {
        Lexed result = new();
        int previous = 0;
        for (int row = 0; row < lines.Count; row++) {
            string line = lines[row];
            int i = 0;
            while (i < line.Length) {
                if (line[i] == ' ') {
                    i++;
                    continue;
                }
                int start = i, lineNumber = row + 1, blank = Math.Max(0, lineNumber - previous - 1);
                SourceError Failure(string reason) => new(lineNumber, start + 1, reason);
                if (line.AsSpan(i).StartsWith("//")) {
                    result.Order.Add(new(false, result.Comments.Count));
                    result.Comments.Add(new(Trim(line[i..]), lineNumber, i + 1, blank, true));
                    previous = lineNumber;
                    break;
                }
                if (line.AsSpan(i).StartsWith("/*")) {
                    int end = line.IndexOf("*/", i + 2, StringComparison.Ordinal);
                    if (end < 0) throw Failure("unterminated comment");
                    result.Order.Add(new(false, result.Comments.Count));
                    result.Comments.Add(new(line[i..(end + 2)], lineNumber, i + 1, blank, false));
                    previous = lineNumber;
                    i = end + 2;
                    continue;
                }
                string kind;
                if (Letter(line[i]) || line[i] == '_') {
                    i++;
                    while (i < line.Length && (Letter(line[i]) || Digit(line[i]) || line[i] == '_')) i++;
                    kind = new[] {
                        "int", "float", "bool", "string", "void", "if", "else", "while", "for", "return", "break", "continue", "true", "false", "switch", "case", "default"
                    }.Contains(line[start..i]) ? "keyword" : "identifier";
                } else if (Digit(line[i])) {
                    i++;
                    while (i < line.Length && Digit(line[i])) i++;
                    if (i + 1 < line.Length && line[i] == '.' && Digit(line[i + 1])) {
                        i += 2;
                        while (i < line.Length && Digit(line[i])) i++;
                    }
                    kind = "number";
                } else if (line[i] == '"') {
                    i++;
                    bool closed = false;
                    while (i < line.Length) {
                        if (line[i] == '\\') i += 2;
                        else if (line[i] == '"') {
                            i++;
                            closed = true;
                            break;
                        } else i++;
                    }
                    if (!closed) throw Failure("unterminated string");
                    kind = "string";
                } else if (i + 1 < line.Length && new[] {
                    "<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%="
                }.Contains(line.Substring(i, 2))) {
                    i += 2;
                    kind = "symbol";
                }
                else if ("+-*/%<>=!()[]{},;.?:".Contains(line[i])) {
                    i++;
                    kind = "symbol";
                }
                else throw Failure($"unexpected character '{line[i]}'");
                result.Order.Add(new(true, result.Tokens.Count));
                result.Tokens.Add(new(line[start..i], kind, lineNumber, start + 1, blank));
                previous = lineNumber;
            }
        }
        result.Tokens.Add(new("", "end", lines.Count + 1, 1, 0));
        return result;
    }
}
