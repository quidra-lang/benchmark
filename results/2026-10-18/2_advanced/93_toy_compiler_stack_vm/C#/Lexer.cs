using System;
using System.Collections.Generic;
using System.Linq;
readonly record struct Position(int Line, int Column) : IComparable<Position> {
    public int CompareTo(Position other) {
        int order = Line.CompareTo(other.Line);
        return order == 0 ? Column.CompareTo(other.Column) : order;
    }
    public override string ToString() => $"{Line}:{Column}";
}
sealed class CompileError(string kind, Position position, string reason) : Exception(reason) {
    public string Kind {
        get;
    } = kind;
    public Position Position {
        get;
    } = position;
    public string Reason {
        get;
    } = reason;
}
sealed record Token(string Kind, string Text, Position Position);
static class Lexer {
    static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    static bool Digit(char c) => c is >= '0' and <= '9';
    public static List<Token> Lex(List<(int Number, string Text)> lines) {
        string text = string.Concat(lines.Select(line => line.Text + "\n"));
        List<Position> positions = new();
        foreach (var (number, line) in lines) for (int j = 0; j <= line.Length; j++) positions.Add(new(number, j + 1));
        List<Token> tokens = new();
        int i = 0;
        while (i < text.Length) {
            if (text[i] is ' ' or '\n') {
                i++;
                continue;
            } int start = i;
            string kind = "symbol";
            CompileError Failure(string reason) => new("lexical", positions[start], reason);
            if (text.AsSpan(i).StartsWith("//")) {
                while (i < text.Length && text[i] != '\n') i++;
                continue;
            }
            if (text.AsSpan(i).StartsWith("/*")) {
                int end = text.IndexOf("*/", i + 2, StringComparison.Ordinal);
                if (end < 0) throw Failure("unterminated comment");
                i = end + 2;
                continue;
            }
            if (Letter(text[i]) || text[i] == '_') {
                i++;
                while (i < text.Length && (Letter(text[i]) || Digit(text[i]) || text[i] == '_')) i++;
                kind = new[] {
                    "int", "bool", "void", "true", "false", "if", "else", "while", "for", "break", "continue", "return", "print", "read"
                }.Contains(text[start..i]) ? "keyword" : "identifier";
            }
            else if (Digit(text[i])) {
                i++;
                while (i < text.Length && Digit(text[i])) i++;
                if (long.Parse(text[start..i]) > int.MaxValue) throw Failure("integer literal too large");
                kind = "integer";
            }
            else if (i + 1 < text.Length && new[] {
                "<=", ">=", "==", "!=", "&&", "||"
            }.Contains(text.Substring(i, 2))) i += 2;
            else if ("+-*/%<>=!(){}[],;".Contains(text[i])) i++;
            else throw Failure($"unexpected character '{text[i]}'");
            tokens.Add(new(kind, text[start..i], positions[start]));
        }
        tokens.Add(new("end", "", new(lines[^1].Number, lines[^1].Text.Length + 1)));
        return tokens;
    }
}
