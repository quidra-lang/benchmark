import java.util.*;
final class Query {
    record Literal(String kind, SchemaIo.Value value) {}
    record Item(String operation, String name) {}
    sealed interface Condition permits Logical, Comparison {}
    record Logical(String operation, Condition first, Condition second) implements Condition {}
    static final class Comparison implements Condition {
        String operation, name;
        List<Literal> literals;
        int index;
        List<SchemaIo.Value> values;
        Comparison(String operation, String name, List<Literal> literals) {
            this.operation = operation;
            this.name = name;
            this.literals = literals;
        }
    }
    record Raw(List<Item> items, Condition condition, String group, String order,
               boolean descending, Integer limit) {}
    static List<String> tokenize(String text) {
        List<String> tokens = new ArrayList<>();
        int position = 0;
        while (position < text.length()) {
            char c = text.charAt(position);
            if (c == ' ') {
                position++;
                continue;
            }
            int start = position++;
            if (c == '\'')
                position = text.indexOf('\'', position) + 1;
            else if (Character.isLetter(c) || c == '_') {
                while (position < text.length() &&
                       (Character.isLetterOrDigit(text.charAt(position)) ||
                        text.charAt(position) == '_'))
                    position++;
            } else if (c == '-' || Character.isDigit(c)) {
                while (position < text.length() && Character.isDigit(text.charAt(position)))
                    position++;
            } else if (position < text.length() &&
                       List.of("<=", ">=", "<>").contains(text.substring(start, position + 1)))
                position++;
            tokens.add(text.substring(start, position));
        }
        return tokens;
    }
    static final class Parser {
        List<String> tokens;
        int position;
        Parser(String text) { tokens = tokenize(text); }
        String peek() { return position < tokens.size() ? tokens.get(position) : ""; }
        String take() { return tokens.get(position++); }
        boolean accept(String token) {
            if (!peek().equals(token))
                return false;
            position++;
            return true;
        }
        Raw parse() {
            take();
            List<Item> items = null;
            if (!accept("*")) {
                items = new ArrayList<>();
                items.add(item());
                while (accept(","))
                    items.add(item());
            }
            Condition condition = accept("WHERE") ? condition() : null;
            String group = null, order = null;
            boolean descending = false;
            if (accept("GROUP")) {
                take();
                group = take();
            }
            if (accept("ORDER")) {
                take();
                order = take();
                if (accept("DESC"))
                    descending = true;
                else
                    accept("ASC");
            }
            Integer limit = accept("LIMIT") ? Integer.parseInt(take()) : null;
            return new Raw(items, condition, group, order, descending, limit);
        }
        Item item() {
            String name = take();
            if (name.charAt(0) >= 'a' && name.charAt(0) <= 'z')
                return new Item("COLUMN", name);
            take();
            String operation = accept("DISTINCT") ? "COUNT_DISTINCT" : name;
            String column = accept("*") ? null : take();
            take();
            return new Item(operation, column);
        }
        Literal literal() {
            String token = take();
            if (token.startsWith("'"))
                return new Literal("STRING",
                                   new SchemaIo.TextValue(token.substring(1, token.length() - 1)));
            if (token.equals("TRUE") || token.equals("FALSE"))
                return new Literal("BOOL", new SchemaIo.BoolValue(token.equals("TRUE")));
            return new Literal("INT", new SchemaIo.NumberValue(Long.parseLong(token)));
        }
        Condition condition() {
            Condition tree = conjunction();
            while (accept("OR"))
                tree = new Logical("OR", tree, conjunction());
            return tree;
        }
        Condition conjunction() {
            Condition tree = negation();
            while (accept("AND"))
                tree = new Logical("AND", tree, negation());
            return tree;
        }
        Condition negation() {
            if (accept("NOT"))
                return new Logical("NOT", negation(), null);
            if (accept("(")) {
                Condition tree = condition();
                take();
                return tree;
            }
            String column = take(), operation = take();
            List<Literal> literals = new ArrayList<>();
            if (operation.equals("IS")) {
                operation = accept("NOT") ? "IS_NOT_NULL" : "IS_NULL";
                take();
            } else if (operation.equals("BETWEEN")) {
                literals.add(literal());
                take();
                literals.add(literal());
            } else if (operation.equals("IN")) {
                take();
                literals.add(literal());
                while (accept(","))
                    literals.add(literal());
                take();
            } else
                literals.add(literal());
            return new Comparison(operation, column, literals);
        }
    }
}
