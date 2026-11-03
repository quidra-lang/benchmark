using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
readonly record struct Position(int File, int Line, int Column) : IComparable<Position> {
    public int CompareTo(Position other) {
        int order = File.CompareTo(other.File);
        if (order == 0) order = Line.CompareTo(other.Line);
        return order == 0 ? Column.CompareTo(other.Column) : order;
    }
}
sealed record Token(string Kind, string Spelling, string Value, Position Position);
static class Lexer {
    static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    static bool Digit(char c) => c is >= '0' and <= '9';
    public static List<Token> Lex(string text, int file) {
        List<Position> positions = new();
        int row = 1, column = 1;
        foreach (char c in text) {
            positions.Add(new(file, row, column));
            if (c == '\n') {
                row++;
                column = 1;
            } else column++;
        } positions.Add(new(file, row, column));
        List<Token> tokens = new();
        int i = 0;
        while (i < text.Length) {
            if (text[i] is ' ' or '\n') {
                i++;
                continue;
            } int start = i;
            string kind, value = "";
            if (text.AsSpan(i).StartsWith("(*")) {
                int end = text.IndexOf("*)", i + 2, StringComparison.Ordinal);
                if (end >= 0) {
                    i = end + 2;
                    continue;
                } tokens.Add(new("invalid", text[start..], "unterminated comment", positions[start]));
                break;
            }
            if (Digit(text[i])) {
                i++;
                while (i < text.Length && Digit(text[i])) i++;
                string digits = text[start..i].TrimStart('0');
                if (digits.Length == 0) digits = "0";
                if (long.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out long n) && n <= int.MaxValue) {
                    kind = "integer";
                    value = n.ToString(CultureInfo.InvariantCulture);
                } else {
                    kind = "invalid";
                    value = "integer literal too large";
                }
            } else if (Letter(text[i]) || text[i] == '_') {
                i++;
                while (i < text.Length && (Letter(text[i]) || Digit(text[i]) || text[i] is '_' or '\'')) i++;
                value = text[start..i];
                kind = new[] {
                    "let", "rec", "and", "in", "fun", "if", "then", "else", "match", "with", "true", "false", "mod", "val"
                }.Contains(value) ? "keyword" : "identifier";
            } else if (text[i] == '\'' && i + 1 < text.Length && text[i + 1] is >= 'a' and <= 'z') {
                i += 2;
                while (i < text.Length && (Letter(text[i]) || Digit(text[i]) || text[i] == '_')) i++;
                kind = "type_variable";
                value = text[start..i];
            } else if (text[i] == '"') {
                i++;
                bool closed = false, valid = true;
                System.Text.StringBuilder decoded = new();
                while (i < text.Length && text[i] != '\n') {
                    if (text[i] == '"') {
                        i++;
                        closed = true;
                        break;
                    }
                    if (text[i] == '\\' && i + 1 < text.Length && text[i + 1] != '\n') {
                        switch (text[i + 1]) {
                            case 'n': decoded.Append('\n');
                            break;
                            case 't': decoded.Append('\t');
                            break;
                            case '\\': decoded.Append('\\');
                            break;
                            case '"': decoded.Append('"');
                            break;
                            default: valid = false;
                            break;
                        } i += 2;
                    }
                    else if (text[i] == '\\') i++;
                    else decoded.Append(text[i++]);
                }
                if (!closed) {
                    kind = "invalid";
                    value = "unterminated string";
                } else if (!valid) {
                    kind = "invalid";
                    value = "invalid escape sequence";
                } else {
                    kind = "string";
                    value = decoded.ToString();
                }
            } else {
                if (i + 1 < text.Length && new[] {
                    ";;", "->", "::", "||", "&&", "<=", ">=", "<>"
                }.Contains(text.Substring(i, 2))) {
                    i += 2;
                    kind = "symbol";
                    value = text[start..i];
                }
                else if (":;=<>+-*/^()[],|".Contains(text[i])) {
                    i++;
                    kind = "symbol";
                    value = text[start..i];
                }
                else {
                    kind = "invalid";
                    value = $"illegal character '{text[i++]}'";
                }
            }
            tokens.Add(new(kind, text[start..i], value, positions[start]));
        }
        tokens.Add(new("eof", "", "", positions[^1]));
        return tokens;
    }
}
