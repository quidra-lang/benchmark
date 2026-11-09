import java.nio.file.*;
import java.util.*;
final class PolicyParser {
    record Clause(String reference, boolean mandatory, String operator, Expressions.Expr literal) {}
    record Argument(String name, Expressions.Expr expression) {}
    record Attachment(String effect, String identifier, List<Argument> arguments) {}
    static final class Element {
        String kind, identifier, behavior;
        Element parent;
        List<List<List<Clause>>> targets = new ArrayList<>();
        List<Element> children = new ArrayList<>();
        Expressions.Expr condition;
        List<Attachment> obligations = new ArrayList<>(), advice = new ArrayList<>();
        Element(String kind, String identifier, String behavior, Element parent) {
            this.kind = kind;
            this.identifier = identifier;
            this.behavior = behavior;
            this.parent = parent;
        }
    }
    record Policies(Element root, List<Element> elements) {}
    static List<List<Clause>> target(String text) {
        List<List<Clause>> alternatives = new ArrayList<>();
        for (String alternative : text.split(" \\| ")) {
            List<Clause> clauses = new ArrayList<>();
            for (String clause : alternative.split(" & ")) {
                String[] fields = clause.split(" ");
                String reference = fields[0];
                boolean mandatory = reference.endsWith("!");
                if (mandatory)
                    reference = reference.substring(0, reference.length() - 1);
                clauses.add(
                    new Clause(reference, mandatory, fields[1], Expressions.parse(fields[2])));
            }
            alternatives.add(clauses);
        }
        return alternatives;
    }
    static Policies read() throws Exception {
        List<Element> elements = new ArrayList<>();
        Deque<Element> stack = new ArrayDeque<>();
        for (String raw : Files.readAllLines(Path.of("input", "policies.txt"))) {
            String line = raw.stripLeading();
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            int separator = line.indexOf(' ');
            String keyword = separator < 0 ? line : line.substring(0, separator),
                   rest = separator < 0 ? "" : line.substring(separator + 1);
            switch (keyword) {
            case "POLICYSET", "POLICY", "RULE": {
                String[] fields = rest.split(" ");
                Element element = new Element(keyword.toLowerCase(Locale.ROOT), fields[0],
                                              fields[1], stack.peekLast());
                if (!stack.isEmpty())
                    stack.getLast().children.add(element);
                elements.add(element);
                stack.addLast(element);
                break;
            }
            case "END":
                stack.removeLast();
                break;
            case "TARGET":
                stack.getLast().targets.add(target(rest));
                break;
            case "CONDITION":
                stack.getLast().condition = Expressions.parse(rest);
                break;
            default: {
                String[] fields = rest.split(" ", 3);
                List<Argument> arguments = new ArrayList<>();
                if (fields.length == 3)
                    for (String part : fields[2].split(";")) {
                        String item = part.strip();
                        int equals = item.indexOf('=');
                        arguments.add(new Argument(item.substring(0, equals),
                                                   Expressions.parse(item.substring(equals + 1))));
                    }
                Attachment attachment = new Attachment(fields[0], fields[1], arguments);
                (keyword.equals("OBLIGATION") ? stack.getLast().obligations
                                              : stack.getLast().advice)
                    .add(attachment);
            }
            }
        }
        return new Policies(elements.getFirst(), elements);
    }
}
