import java.util.*;
final class Printer {
    record Command(int indent, boolean flat, Doc doc) {}
    static void push(List<Command> stack, int indent, boolean flat, List<Doc> documents) {
        for (int index = documents.size() - 1; index >= 0; index--)
            stack.add(new Command(indent, flat, documents.get(index)));
    }
    static boolean fits(int remaining, Command candidate, List<Command> rest) {
        if (remaining < 0)
            return false;
        List<Command> check = new ArrayList<>();
        check.add(candidate);
        int existing = rest.size() - 1;
        while (true) {
            if (check.isEmpty()) {
                if (existing < 0)
                    return true;
                check.add(rest.get(existing--));
            }
            Command command = check.removeLast();
            int indent = command.indent();
            boolean flat = command.flat();
            Doc doc = command.doc();
            if (doc instanceof DocBuilder.Text text)
                remaining -= text.value().length();
            else if (doc instanceof DocBuilder.IfBreak conditional)
                remaining -= (flat ? conditional.flat() : conditional.broken()).length();
            else if (doc == DocBuilder.Break.LINE) {
                if (!flat)
                    return true;
                remaining--;
            } else if (doc == DocBuilder.Break.SOFTLINE) {
                if (!flat)
                    return true;
            } else if (doc == DocBuilder.Break.HARDLINE)
                return true;
            else if (doc instanceof DocBuilder.Concat concat)
                push(check, indent, flat, concat.items());
            else if (doc instanceof DocBuilder.Group group)
                check.add(new Command(indent, group.forced ? false : flat, group.child));
            else if (doc instanceof DocBuilder.Nest nest)
                check.add(new Command(indent, flat, nest.child()));
            else if (doc instanceof DocBuilder.Align align)
                check.add(new Command(indent, flat, align.child()));
            if (remaining < 0)
                return false;
        }
    }
    static void finalizeLine(List<String> result, StringBuilder current, List<String> pending,
                             int width, int column) {
        String output = Lexer.trim(current.toString());
        if (!pending.isEmpty()) {
            String comments = String.join(" ", pending);
            if (column > 0 && output.length() < column - 1 &&
                column - 1 + comments.length() <= width)
                output += " ".repeat(column - 1 - output.length()) + comments;
            else
                output += " " + comments;
            pending.clear();
        }
        result.add(output);
    }
    static List<String> layout(Doc document, int width, int column) {
        List<String> result = new ArrayList<>(), pending = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        List<Command> stack = new ArrayList<>();
        stack.add(new Command(0, false, document));
        while (!stack.isEmpty()) {
            Command command = stack.removeLast();
            int indent = command.indent();
            boolean flat = command.flat();
            Doc doc = command.doc();
            if (doc instanceof DocBuilder.Text text)
                current.append(text.value());
            else if (doc instanceof DocBuilder.IfBreak conditional)
                current.append(flat ? conditional.flat() : conditional.broken());
            else if (doc == DocBuilder.Break.HARDLINE || doc == DocBuilder.Break.LINE && !flat ||
                     doc == DocBuilder.Break.SOFTLINE && !flat) {
                finalizeLine(result, current, pending, width, column);
                current.setLength(0);
                current.append(" ".repeat(indent));
            } else if (doc == DocBuilder.Break.LINE)
                current.append(' ');
            else if (doc instanceof DocBuilder.Concat concat)
                push(stack, indent, flat, concat.items());
            else if (doc instanceof DocBuilder.Nest nest)
                stack.add(new Command(indent + nest.amount(), flat, nest.child()));
            else if (doc instanceof DocBuilder.Align align)
                stack.add(new Command(current.length(), flat, align.child()));
            else if (doc instanceof DocBuilder.Suffix suffix)
                pending.add(suffix.value());
            else if (doc instanceof DocBuilder.Group group) {
                String mode =
                    flat           ? "flat"
                    : group.forced ? "forced"
                    : fits(width - current.length(), new Command(indent, true, group.child), stack)
                        ? "flat"
                        : "break";
                group.mode = mode;
                stack.add(new Command(indent, mode.equals("flat"), group.child));
            }
        }
        finalizeLine(result, current, pending, width, column);
        return result;
    }
}
