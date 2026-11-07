import java.util.*;

final class Driver {
    record Input(String name, int position) {}
    static final class Node {
        String symbol, mark;
        List<Node> children = new ArrayList<>();
        Node(String symbol) {
            this.symbol = symbol;
        }
    }
    record StackEntry(String symbol, Node node) {}
    record Trace(int step, List<String> stack, List<String> input, String action) {}
    record Event(int step, String kind, String symbol, String token, int position) {}
    static final class Result {
        Node root;
        List<Trace> trace = new ArrayList<>();
        List<Integer> leftParse = new ArrayList<>();
        List<Event> errors = new ArrayList<>();
        int predicts, matches, skip, pop, missing, maxStack;
    }
    static Result parse(List<Input> original, GrammarParser.Grammar grammar, FirstFollow.Sets sets,
                        Table.Result table) {
        List<Input> input = new ArrayList<>(original);
        input.add(new Input("$", original.size() + 1));
        Result result = new Result();
        result.root = new Node(grammar.start);
        List<StackEntry> stack = new ArrayList<>();
        stack.add(new StackEntry("$", null));
        stack.add(new StackEntry(grammar.start, result.root));
        int cursor = 0, step = 0;
        while (true) {
            step++;
            StackEntry entry = stack.getLast();
            String top = entry.symbol();
            Input token = input.get(cursor);
            String current = token.name();
            result.maxStack = Math.max(result.maxStack, stack.size());
            List<String> beforeStack = new ArrayList<>(), beforeInput = new ArrayList<>();
            for (StackEntry value : stack)
                beforeStack.add(value.symbol());
            for (int i = cursor; i < input.size(); i++)
                beforeInput.add(input.get(i).name());
            String action;
            boolean terminate = false;
            Event event = null;
            if (top.equals("$") && current.equals("$")) {
                action = "accept";
                terminate = true;
            } else if (top.equals("$")) {
                action = "error: skip " + current;
                event = new Event(step, "skip", top, current, token.position());
                cursor++;
                result.skip++;
            } else if (!GrammarParser.nonterminal(top)) {
                if (top.equals(current)) {
                    action = "match " + current;
                    stack.removeLast();
                    cursor++;
                    result.matches++;
                } else {
                    action = "error: missing " + top;
                    entry.node().mark = "missing";
                    stack.removeLast();
                    result.missing++;
                    event = new Event(step, "missing", top, current, token.position());
                }
            } else if (table.choices.containsKey(new Table.Cell(top, current))) {
                int number = table.choices.get(new Table.Cell(top, current));
                Table.Production production = table.productions.get(number - 1);
                action = "predict " + number + ": " + production.notation();
                result.leftParse.add(number);
                stack.removeLast();
                if (production.rhs.isEmpty())
                    entry.node().children.add(new Node("%empty"));
                else {
                    List<Node> children = new ArrayList<>();
                    for (String symbol : production.rhs)
                        children.add(new Node(symbol));
                    entry.node().children.addAll(children);
                    for (int i = children.size() - 1; i >= 0; i--)
                        stack.add(new StackEntry(children.get(i).symbol, children.get(i)));
                }
                result.predicts++;
            } else if (current.equals("$") || sets.follow.get(top).contains(current)) {
                action = "error: pop " + top;
                entry.node().mark = "error";
                stack.removeLast();
                result.pop++;
                event = new Event(step, "pop", top, current, token.position());
            } else {
                action = "error: skip " + current;
                cursor++;
                result.skip++;
                event = new Event(step, "skip", top, current, token.position());
            }
            result.trace.add(new Trace(step, beforeStack, beforeInput, action));
            if (event != null)
                result.errors.add(event);
            if (terminate)
                return result;
        }
    }
}
