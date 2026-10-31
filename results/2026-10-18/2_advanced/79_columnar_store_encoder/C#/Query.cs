using System;
using System.Collections.Generic;
public static class Query {
    public record Literal(string kind, SchemaIo.Value value);
    public record Item(string operation, string name);
    public abstract record Condition;
    public sealed record Logical(string operation, Condition first, Condition second) : Condition;
    public sealed record Comparison : Condition {
        public string operation, name;
        public List<Literal> literals;
        public int index;
        public List<SchemaIo.Value> values;
        public Comparison(string operation, string name, List<Literal> literals) {
            this.operation = operation;
            this.name = name;
            this.literals = literals;
        }
    }
    public record Raw(List<Item> items, Condition condition, string group, string order,
                      bool descending, int? limit);
    public static List<string> Tokenize(string text) {
        List<string> tokens = new();
        int position = 0;
        while (position < text.Length) {
            char c = text[position];
            if (c == ' ') {
                position++;
                continue;
            }
            int start = position++;
            if (c == '\'')
                position = text.IndexOf('\'', position) + 1;
            else if (char.IsAsciiLetter(c) || c == '_') {
                while (position < text.Length &&
                       (char.IsAsciiLetterOrDigit(text[position]) || text[position] == '_'))
                    position++;
            } else if (c == '-' || char.IsAsciiDigit(c)) {
                while (position < text.Length && char.IsAsciiDigit(text[position]))
                    position++;
            } else if (position < text.Length && new List<string> { "<=", ">=", "<>" }.Contains(
                                                     text.Substring(start, position + 1 - start)))
                position++;
            tokens.Add(text.Substring(start, position - start));
        }
        return tokens;
    }
    public sealed class Parser {
        public List<string> tokens;
        public int position;
        public Parser(string text) { tokens = Tokenize(text); }
        public string Peek() => position < tokens.Count ? tokens[position] : "";
        public string Take() => tokens[position++];
        public bool Accept(string token) {
            if (Peek() != token)
                return false;
            position++;
            return true;
        }
        public Raw Parse() {
            Take();
            List<Item> items = null;
            if (!Accept("*")) {
                items = new() { ParseItem() };
                while (Accept(","))
                    items.Add(ParseItem());
            }
            Condition condition = Accept("WHERE") ? ParseCondition() : null;
            string group = null, order = null;
            bool descending = false;
            if (Accept("GROUP")) {
                Take();
                group = Take();
            }
            if (Accept("ORDER")) {
                Take();
                order = Take();
                if (Accept("DESC"))
                    descending = true;
                else
                    Accept("ASC");
            }
            int? limit = Accept("LIMIT") ? int.Parse(Take()) : null;
            return new(items, condition, group, order, descending, limit);
        }
        public Item ParseItem() {
            string name = Take();
            if (name[0] >= 'a' && name[0] <= 'z')
                return new("COLUMN", name);
            Take();
            string operation = Accept("DISTINCT") ? "COUNT_DISTINCT" : name;
            string column = Accept("*") ? null : Take();
            Take();
            return new(operation, column);
        }
        public Literal ParseLiteral() {
            string token = Take();
            if (token.StartsWith('\''))
                return new("STRING", new SchemaIo.TextValue(token[1.. ^ 1]));
            if (token == "TRUE" || token == "FALSE")
                return new("BOOL", new SchemaIo.BoolValue(token == "TRUE"));
            return new("INT", new SchemaIo.NumberValue(long.Parse(token)));
        }
        public Condition ParseCondition() {
            Condition tree = Conjunction();
            while (Accept("OR"))
                tree = new Logical("OR", tree, Conjunction());
            return tree;
        }
        public Condition Conjunction() {
            Condition tree = Negation();
            while (Accept("AND"))
                tree = new Logical("AND", tree, Negation());
            return tree;
        }
        public Condition Negation() {
            if (Accept("NOT"))
                return new Logical("NOT", Negation(), null);
            if (Accept("(")) {
                Condition tree = ParseCondition();
                Take();
                return tree;
            }
            string column = Take(), operation = Take();
            List<Literal> literals = new();
            if (operation == "IS") {
                operation = Accept("NOT") ? "IS_NOT_NULL" : "IS_NULL";
                Take();
            } else if (operation == "BETWEEN") {
                literals.Add(ParseLiteral());
                Take();
                literals.Add(ParseLiteral());
            } else if (operation == "IN") {
                Take();
                literals.Add(ParseLiteral());
                while (Accept(","))
                    literals.Add(ParseLiteral());
                Take();
            } else
                literals.Add(ParseLiteral());
            return new Comparison(operation, column, literals);
        }
    }
}
