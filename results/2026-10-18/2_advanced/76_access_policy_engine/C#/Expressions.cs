using System;
using System.Collections.Generic;
public static class Expressions {
    public abstract record Expr;
    public record Literal(object value) : Expr;
    public record Reference(string name) : Expr;
    public record Current : Expr;
    public record Operation(string name, List<Expr> arguments) : Expr;
    public static List<string> Lex(string text) {
        List<string> tokens = new();
        for (int i = 0; i < text.Length;) {
            char c = text[i];
            if (c == ' ') {
                i++;
                continue;
            }
            int start = i++;
            if (c == '"') {
                while (text[i] != '"')
                    i++;
                i++;
            } else if (c >= '0' && c <= '9') {
                while (i < text.Length && text[i] >= '0' && text[i] <= '9')
                    i++;
            } else if (c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z') {
                while (i < text.Length) {
                    char n = text[i];
                    if (!(n >= 'A' && n <= 'Z' || n >= 'a' && n <= 'z' || n >= '0' && n <= '9' ||
                          n == '_' || n == '.'))
                        break;
                    i++;
                }
            } else if (i < text.Length && text[i] == '=' && "=!<>".IndexOf(c) >= 0)
                i++;
            tokens.Add(text[start..i]);
        }
        return tokens;
    }
    public sealed class Parser {
        public List<string> tokens;
        public int position;
        public Parser(string text) { tokens = Lex(text); }
        public string Peek() => position < tokens.Count ? tokens[position] : "";
        public string Take() => tokens[position++];
        public Expr Disjunction() {
            Expr tree = Conjunction();
            while (Peek() == "or") {
                string op = Take();
                tree = new Operation(op, new() { tree, Conjunction() });
            }
            return tree;
        }
        public Expr Conjunction() {
            Expr tree = Negation();
            while (Peek() == "and") {
                string op = Take();
                tree = new Operation(op, new() { tree, Negation() });
            }
            return tree;
        }
        public Expr Negation() {
            if (Peek() == "not") {
                Take();
                return new Operation("not", new() { Negation() });
            }
            return Comparison();
        }
        public Expr Comparison() {
            Expr tree = Sum();
            if (new HashSet<string> { "==", "!=", "<", "<=", ">", ">=", "in" }.Contains(Peek())) {
                string op = Take();
                tree = new Operation(op, new() { tree, Sum() });
            }
            return tree;
        }
        public Expr Sum() {
            Expr tree = Product();
            while (Peek() == "+" || Peek() == "-") {
                string op = Take();
                tree = new Operation(op, new() { tree, Product() });
            }
            return tree;
        }
        public Expr Product() {
            Expr tree = Unary();
            while (Peek() == "*") {
                string op = Take();
                tree = new Operation(op, new() { tree, Unary() });
            }
            return tree;
        }
        public Expr Unary() {
            if (Peek() == "-") {
                Take();
                return new Operation("-", new() { Unary() });
            }
            return Primary();
        }
        public Expr Primary() {
            string token = Take();
            if (token[0] >= '0' && token[0] <= '9')
                return new Literal(int.Parse(token));
            if (token.StartsWith('"'))
                return new Literal(token[1.. ^ 1]);
            if (token == "true" || token == "false")
                return new Literal(token == "true");
            if (token == "it")
                return new Current();
            if (token.Contains('.'))
                return new Reference(token);
            if (token == "(") {
                Expr tree = Disjunction();
                Take();
                return tree;
            }
            if (token == "[") {
                List<string> values = new();
                while (Peek() != "]") {
                    string value = Take();
                    values.Add(value[1.. ^ 1]);
                    if (Peek() != "]")
                        Take();
                }
                Take();
                return new Literal(values);
            }
            Take();
            List<Expr> arguments = new();
            while (Peek() != ")") {
                arguments.Add(Disjunction());
                if (Peek() != ")")
                    Take();
            }
            Take();
            return new Operation(token, arguments);
        }
    }
    public static Expr Parse(string text) => new Parser(text).Disjunction();
}
