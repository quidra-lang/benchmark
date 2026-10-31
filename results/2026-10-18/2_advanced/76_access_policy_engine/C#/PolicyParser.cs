using System;
using System.Collections.Generic;
using System.IO;
public static class PolicyParser {
    public record Clause(string reference, bool mandatory, string op, Expressions.Expr literal);
    public record Argument(string name, Expressions.Expr expression);
    public record Attachment(string effect, string identifier, List<Argument> arguments);
    public sealed class Element {
        public string kind, identifier, behavior;
        public Element parent;
        public List<List<List<Clause>>> targets = new();
        public List<Element> children = new();
        public Expressions.Expr condition;
        public List<Attachment> obligations = new(), advice = new();
        public Element(string kind, string identifier, string behavior, Element parent) {
            this.kind = kind;
            this.identifier = identifier;
            this.behavior = behavior;
            this.parent = parent;
        }
    }
    public record Policies(Element root, List<Element> elements);
    public static List<List<Clause>> Target(string text) {
        List<List<Clause>> alternatives = new();
        foreach (string alternative in text.Split(" | ")) {
            List<Clause> clauses = new();
            foreach (string clause in alternative.Split(" & ")) {
                string[] fields = clause.Split(' ');
                string reference = fields[0];
                bool mandatory = reference.EndsWith('!');
                if (mandatory)
                    reference = reference[..^ 1];
                clauses.Add(new(reference, mandatory, fields[1], Expressions.Parse(fields[2])));
            }
            alternatives.Add(clauses);
        }
        return alternatives;
    }
    public static Policies Read() {
        List<Element> elements = new();
        Stack<Element> stack = new();
        foreach (string raw in File.ReadAllLines("input/policies.txt")) {
            string line = raw.TrimStart(' ');
            if (line.Length == 0 || line.StartsWith('#'))
                continue;
            int separator = line.IndexOf(' ');
            string keyword = separator < 0 ? line : line[..separator],
                   rest = separator < 0 ? "" : line[(separator + 1)..];
            switch (keyword) {
            case "POLICYSET":
            case "POLICY":
            case "RULE": {
                string[] fields = rest.Split(' ');
                Element element = new(keyword.ToLowerInvariant(), fields[0], fields[1],
                                      stack.Count == 0 ? null : stack.Peek());
                if (stack.Count != 0)
                    stack.Peek().children.Add(element);
                elements.Add(element);
                stack.Push(element);
                break;
            }
            case "END":
                stack.Pop();
                break;
            case "TARGET":
                stack.Peek().targets.Add(Target(rest));
                break;
            case "CONDITION":
                stack.Peek().condition = Expressions.Parse(rest);
                break;
            default: {
                string[] fields = rest.Split(' ', 3);
                List<Argument> arguments = new();
                if (fields.Length == 3)
                    foreach (string part in fields[2].Split(';')) {
                        string item = part.Trim(' ');
                        int equals = item.IndexOf('=');
                        arguments.Add(new(item[..equals], Expressions.Parse(item[(equals + 1)..])));
                    }
                Attachment attachment = new(fields[0], fields[1], arguments);
                (keyword == "OBLIGATION" ? stack.Peek().obligations : stack.Peek().advice)
                    .Add(attachment);
                break;
            }
            }
        }
        return new(elements[0], elements);
    }
}
