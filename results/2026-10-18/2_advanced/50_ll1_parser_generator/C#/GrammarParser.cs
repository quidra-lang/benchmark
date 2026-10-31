using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class GrammarParser {
    public sealed class Grammar {
        public List<string> order = new();
        public Dictionary<string, List<List<string>>> rules = new();
        public string start;
        public HashSet<string> declared = new();
        public bool hasDeclaration;
        public Dictionary<string, int> words = new();
        public List<string> diagnostics = new();
    }
    public record Token(string kind, string value, int start, int end) {
    }
    public record Parsed(string kind, string lhs, List<List<string>> alternatives, List<string> words,
                         int error) {
    }
    public static bool Nonterminal(string symbol) {
        return symbol.StartsWith("<") && symbol.EndsWith(">");
    }
    public static bool Letter(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    }
    public static bool Word(char c) {
        return Letter(c) || c >= '0' && c <= '9' || c == '_';
    }
    public static List<Token> Lex(string line) {
        List<Token> tokens = new();
        int i = 0;
        while (i < line.Length) {
            char c = line[i];
            if (c == ' ') {
                i++;
                continue;
            }
            if (c == '#')
                break;
            int start = i;
            string kind = "invalid", value = c.ToString();
            if (c == '<') {
                int j = i + 1;
                if (j < line.Length && Letter(line[j])) {
                    j++;
                    while (j < line.Length && Word(line[j]))
                        j++;
                    if (j < line.Length && line[j] == '>') {
                        kind = "nonterminal";
                        i = j + 1;
                        value = line.Substring(start, i - (start));
                    }
                }
            } else if (c == '"') {
                int j = i + 1;
                while (j < line.Length && line[j] != ' ' && line[j] != '"')
                    j++;
                if (j > i + 1 && j < line.Length && line[j] == '"') {
                    kind = "terminal";
                    value = line.Substring(i + 1, j - (i + 1));
                    i = j + 1;
                }
            } else if (Letter(c)) {
                int j = i + 1;
                while (j < line.Length && Word(line[j]))
                    j++;
                kind = "word";
                i = j;
                value = line.Substring(start, i - (start));
            } else if (line.IndexOf("::=", i, StringComparison.Ordinal) == i) {
                kind = "definition";
                value = "::=";
                i += 3;
            } else if (c == '|') {
                kind = "separator";
                value = "|";
                i++;
            } else if (c == '%') {
                int j = i + 1;
                while (j < line.Length && Letter(line[j]))
                    j++;
                string directive = line.Substring(i + 1, j - (i + 1));
                if (new string[] { "empty", "start", "token" }.Contains(directive)) {
                    kind = "directive";
                    value = "%" + directive;
                    i = j;
                }
            }
            if (kind.Equals("invalid"))
                i = start + 1;
            tokens.Add(new Token(kind, value, start + 1, i));
            if (kind.Equals("invalid"))
                break;
        }
        return tokens;
    }
    public static int Error(List<Token> tokens, int cursor) {
        return cursor < tokens.Count ? tokens[cursor].start : tokens[^1].end + 1;
    }
    public static Parsed Bad(List<Token> tokens, int cursor) {
        return new Parsed("", null, null, null, Error(tokens, cursor));
    }
    public static bool Symbol(Token token) {
        return new string[] { "nonterminal", "terminal", "word" }.Contains(token.kind);
    }
    public static Parsed Alternatives(List<Token> tokens, int cursor, string kind, string lhs) {
        List<List<string>> alternatives = new();
        while (true) {
            if (cursor >= tokens.Count)
                return Bad(tokens, cursor);
            Token first = tokens[cursor];
            List<string> alternative = new();
            if (first.kind.Equals("directive") && first.value.Equals("%empty")) {
                cursor++;
                if (cursor < tokens.Count && !tokens[cursor].kind.Equals("separator"))
                    return Bad(tokens, cursor);
            } else if (Symbol(first)) {
                while (cursor < tokens.Count && Symbol(tokens[cursor]))
                    alternative.Add(tokens[cursor++].value);
            } else
                return Bad(tokens, cursor);
            alternatives.Add(alternative);
            if (cursor >= tokens.Count)
                return new Parsed(kind, lhs, alternatives, null, 0);
            if (!tokens[cursor].kind.Equals("separator"))
                return Bad(tokens, cursor);
            cursor++;
        }
    }
    public static Parsed Line(List<Token> tokens) {
        if (tokens.Count == 0)
            return new Parsed("blank", null, null, null, 0);
        Token first = tokens[0];
        if (first.kind.Equals("nonterminal")) {
            if (tokens.Count < 2)
                return Bad(tokens, tokens.Count);
            if (!tokens[1].kind.Equals("definition"))
                return Bad(tokens, 1);
            return Alternatives(tokens, 2, "rule", first.value);
        }
        if (first.kind.Equals("separator"))
            return Alternatives(tokens, 1, "continuation", null);
        if (first.kind.Equals("directive") && first.value.Equals("%start")) {
            if (tokens.Count < 2)
                return Bad(tokens, tokens.Count);
            if (!tokens[1].kind.Equals("nonterminal"))
                return Bad(tokens, 1);
            if (tokens.Count > 2)
                return Bad(tokens, 2);
            return new Parsed("start", tokens[1].value, null, null, 0);
        }
        if (first.kind.Equals("directive") && first.value.Equals("%token")) {
            if (tokens.Count < 2)
                return Bad(tokens, tokens.Count);
            List<string> words = new();
            for (int i = 1; i < tokens.Count; i++) {
                if (!tokens[i].kind.Equals("word"))
                    return Bad(tokens, i);
                words.Add(tokens[i].value);
            }
            return new Parsed("declaration", null, null, words, 0);
        }
        return Bad(tokens, 0);
    }
    public static string Notation(List<string> symbols) {
        return symbols.Count == 0 ? "%empty" : string.Join(" ", symbols);
    }
    public static string Production(string lhs, List<string> rhs) {
        return lhs + " -> " + Notation(rhs);
    }
    public static Grammar Parse(List<string> lines) {
        Grammar grammar = new Grammar();
        string attachment = null;
        for (int i = 0; i < lines.Count; i++) {
            int number = i + 1;
            List<Token> tokens = Lex(lines[i]);
            Parsed parsed = Line(tokens);
            if (parsed.error > 0) {
                grammar.diagnostics.Add("line " + number + ": syntax error at column " + parsed.error);
                attachment = null;
                continue;
            }
            if (parsed.kind.Equals("blank"))
                continue;
            string lhs = parsed.lhs;
            if (parsed.kind.Equals("rule")) {
                attachment = lhs;
                if (!grammar.rules.ContainsKey(lhs)) {
                    grammar.order.Add(lhs);
                    grammar.rules[lhs] = new();
                }
            } else if (parsed.kind.Equals("continuation")) {
                if (attachment == null) {
                    grammar.diagnostics.Add("line " + number + ": continuation without a rule");
                    continue;
                }
                lhs = attachment;
            } else if (parsed.kind.Equals("start")) {
                attachment = null;
                if (grammar.start == null)
                    grammar.start = lhs;
                else
                    grammar.diagnostics.Add("line " + number + ": duplicate %start");
            } else {
                attachment = null;
                grammar.hasDeclaration = true;
                grammar.declared.UnionWith(parsed.words);
            }
            if (parsed.kind.Equals("rule") || parsed.kind.Equals("continuation")) {
                foreach (Token token in tokens)
                    if (token.kind.Equals("word"))
                        grammar.words.TryAdd(token.value, number);
                foreach (List<string> alternative in parsed.alternatives) {
                    if (grammar.rules[lhs].Any(old => old.SequenceEqual(alternative)))
                        grammar.diagnostics.Add("line " + number + ": duplicate alternative " +
                                                Production(lhs, alternative));
                    else
                        grammar.rules[lhs].Add(alternative);
                }
            }
        }
        if (grammar.start == null)
            grammar.start = grammar.order[0];
        return grammar;
    }
    public static Grammar Copy(Grammar original) {
        Grammar result = new Grammar();
        result.order.AddRange(original.order);
        result.start = original.start;
        foreach (string lhs in original.order) {
            List<List<string>> alternatives = new();
            foreach (List<string> rhs in original.rules[lhs])
                alternatives.Add(new(rhs));
            result.rules[lhs] = alternatives;
        }
        return result;
    }
}
