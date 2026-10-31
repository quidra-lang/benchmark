using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
sealed record Token(string Kind, string Text, int Line, bool Space, HashSet<string> Hide) {
    public Token(string kind, string text, int line, bool space) : this(kind, text, line, space, new()) {
    }
}
sealed record LogicalLine(List<Token> Tokens, int Start, int End);
static class Lexer {
    static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    static bool Digit(char c) => c is >= '0' and <= '9';
    public static (string Kind, int Length) One(string text, int start = 0, bool header = false) {
        if (start == text.Length) return ("other", 0);
        char c = text[start];
        if (header && c == '<') {
            int end = start + 1;
            while (end < text.Length && text[end] != '\n' && text[end] != '>') end++;
            if (end < text.Length && text[end] == '>') return ("header", end - start + 1);
        }
        if (Letter(c) || c == '_') {
            int n = start + 1;
            while (n < text.Length && (Letter(text[n]) || Digit(text[n]) || text[n] == '_')) n++;
            return ("identifier", n - start);
        }
        if (Digit(c) || c == '.' && start + 1 < text.Length && Digit(text[start + 1])) {
            int n = start + 1;
            while (n < text.Length) {
                if ("eEpP".Contains(text[n]) && n + 1 < text.Length && "+-".Contains(text[n + 1])) n += 2;
                else if (Letter(text[n]) || Digit(text[n]) || "_.".Contains(text[n])) n++;
                else break;
            } return ("number", n - start);
        }
        if (c is '\'' or '"') {
            int n = start + 1;
            while (n < text.Length && text[n] != '\n') {
                if (text[n] == c) return (c == '\'' ? "character" : "string", n - start + 1);
                if (text[n] == '\\' && n + 1 < text.Length && text[n + 1] != '\n') n += 2;
                else n++;
            }
        }
        foreach (string punctuator in new[] {
            "...", "<<=", ">>=", "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "*=", "/=", "%=", "+=", "-=", "&=", "^=", "|=", "##"
        }) if (text.AsSpan(start).StartsWith(punctuator)) return ("punctuator", punctuator.Length);
        return ("[](){}.&*+-~!/%<>^|?:;=,#".Contains(c) ? "punctuator" : "other", 1);
    }
    public static string? Single(string text) {
        if (text.Length == 0 || text.StartsWith("//", StringComparison.Ordinal) || text.StartsWith("/*", StringComparison.Ordinal)) return null;
        var (kind, n) = One(text);
        return n == text.Length ? kind : null;
    }
    static bool Separator(string left, string right) => left == "/" && (right.StartsWith('/') || right.StartsWith('*')) || One(left + right).Length != left.Length;
    public static string Render(IReadOnlyList<Token> tokens, bool output = false) {
        StringBuilder text = new();
        for (int i = 0; i < tokens.Count; i++) {
            Token token = tokens[i];
            if (i > 0 && (token.Space || output && Separator(tokens[i - 1].Text, token.Text))) text.Append(' ');
            text.Append(token.Text);
        } return text.ToString();
    }
    public static List<LogicalLine> Lex(string source) {
        StringBuilder builder = new();
        List<int> physical = new();
        int i = 0, line = 1;
        while (i < source.Length) {
            if (source[i] == '\\' && i + 1 < source.Length && source[i + 1] == '\n') {
                i += 2;
                line++;
                continue;
            } builder.Append(source[i]);
            physical.Add(line);
            if (source[i] == '\n') line++;
            i++;
        }
        string text = builder.ToString();
        List<LogicalLine> result = new();
        List<Token> tokens = new();
        int start = 1;
        bool space = true;
        i = 0;
        while (i < text.Length) {
            if (text[i] == ' ') {
                i++;
                space = true;
                continue;
            }
            if (text[i] == '\n') {
                int end = physical[i];
                result.Add(new(new(tokens), start, end));
                tokens = new();
                start = end + 1;
                i++;
                space = true;
                continue;
            }
            if (text.AsSpan(i).StartsWith("//")) {
                while (i < text.Length && text[i] != '\n') i++;
                space = true;
                continue;
            }
            if (text.AsSpan(i).StartsWith("/*")) {
                i = text.IndexOf("*/", i + 2, StringComparison.Ordinal) + 2;
                space = true;
                continue;
            }
            bool header = tokens.Count == 2 && tokens[0].Text == "#" && tokens[1].Text == "include";
            var (kind, n) = One(text, i, header);
            tokens.Add(new(kind, text.Substring(i, n), physical[i], space));
            i += n;
            space = false;
        }
        if (tokens.Count > 0) result.Add(new(tokens, start, line));
        return result;
    }
}
