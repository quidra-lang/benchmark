using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Driver {
    public record Input(string name, int position) {
    }
    public sealed class Node {
        public string symbol, mark;
        public List<Node> children = new();
        public Node(string symbol) {
            this.symbol = symbol;
        }
    }
    public record StackEntry(string symbol, Node node) {
    }
    public record Trace(int step, List<string> stack, List<string> input, string action) {
    }
    public record Event(int step, string kind, string symbol, string token, int position) {
    }
    public sealed class Result {
        public Node root;
        public List<Trace> trace = new();
        public List<int> leftParse = new();
        public List<Event> errors = new();
        public int predicts, matches, skip, pop, missing, maxStack;
    }
    public static Result Parse(List<Input> original, GrammarParser.Grammar grammar, FirstFollow.Sets sets,
                               Table.Result table) {
        List<Input> input = new(original);
        input.Add(new Input("$", original.Count + 1));
        Result result = new Result();
        result.root = new Node(grammar.start);
        List<StackEntry> stack = new();
        stack.Add(new StackEntry("$", null));
        stack.Add(new StackEntry(grammar.start, result.root));
        int cursor = 0, step = 0;
        while (true) {
            step++;
            StackEntry entry = stack[^1];
            string top = entry.symbol;
            Input token = input[cursor];
            string current = token.name;
            result.maxStack = Math.Max(result.maxStack, stack.Count);
            List<string> beforeStack = new(), beforeInput = new();
            foreach (StackEntry value in stack)
                beforeStack.Add(value.symbol);
            for (int i = cursor; i < input.Count; i++)
                beforeInput.Add(input[i].name);
            string action;
            bool terminate = false;
            Event errorEvent = null;
            if (top.Equals("$") && current.Equals("$")) {
                action = "accept";
                terminate = true;
            } else if (top.Equals("$")) {
                action = "error: skip " + current;
                errorEvent = new Event(step, "skip", top, current, token.position);
                cursor++;
                result.skip++;
            } else if (!GrammarParser.Nonterminal(top)) {
                if (top.Equals(current)) {
                    action = "match " + current;
                    stack.RemoveAt(stack.Count - 1);
                    cursor++;
                    result.matches++;
                } else {
                    action = "error: missing " + top;
                    entry.node.mark = "missing";
                    stack.RemoveAt(stack.Count - 1);
                    result.missing++;
                    errorEvent = new Event(step, "missing", top, current, token.position);
                }
            } else if (table.choices.ContainsKey(new Table.Cell(top, current))) {
                int number = table.choices[new Table.Cell(top, current)];
                Table.Production production = table.productions[number - 1];
                action = "predict " + number + ": " + production.Notation();
                result.leftParse.Add(number);
                stack.RemoveAt(stack.Count - 1);
                if (production.rhs.Count == 0)
                    entry.node.children.Add(new Node("%empty"));
                else {
                    List<Node> children = new();
                    foreach (string symbol in production.rhs)
                        children.Add(new Node(symbol));
                    entry.node.children.AddRange(children);
                    for (int i = children.Count - 1; i >= 0; i--)
                        stack.Add(new StackEntry(children[i].symbol, children[i]));
                }
                result.predicts++;
            } else if (current.Equals("$") || sets.follow[top].Contains(current)) {
                action = "error: pop " + top;
                entry.node.mark = "error";
                stack.RemoveAt(stack.Count - 1);
                result.pop++;
                errorEvent = new Event(step, "pop", top, current, token.position);
            } else {
                action = "error: skip " + current;
                cursor++;
                result.skip++;
                errorEvent = new Event(step, "skip", top, current, token.position);
            }
            result.trace.Add(new Trace(step, beforeStack, beforeInput, action));
            if (errorEvent != null)
                result.errors.Add(errorEvent);
            if (terminate)
                return result;
        }
    }
}
