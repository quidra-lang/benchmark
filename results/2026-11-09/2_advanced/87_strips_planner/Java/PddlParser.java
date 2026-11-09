import java.util.*;
final class PddlParser {
    sealed interface Expression permits Word, Sequence {}
    record Word(String value) implements Expression {}
    record Sequence(List<Expression> values) implements Expression {}
    record Typed(String name, String type) {}
    record Atom(String predicate, List<String> terms) {
        Atom { terms = List.copyOf(terms); }
        public String toString() {
            return "(" + predicate + (terms.isEmpty() ? "" : " " + String.join(" ", terms)) + ")";
        }
    }
    record Literal(boolean positive, Atom atom) {}
    record Schema(String name, List<Typed> parameters, List<Literal> condition,
                  List<Literal> effects, int cost) {}
    static final class Domain {
        String name;
        Map<String, String> parents = new LinkedHashMap<>();
        List<String> typeOrder = new ArrayList<>();
        Map<String, List<String>> predicates = new LinkedHashMap<>();
        List<Schema> actions = new ArrayList<>();
        Map<String, Schema> byName = new LinkedHashMap<>();
        Set<String> fluent = new HashSet<>(), statics = new HashSet<>();
        List<String> diagnostics = new ArrayList<>();
        Domain(String name) {
            this.name = name;
            parents.put("object", null);
            typeOrder.add("object");
        }
    }
    static final class Problem {
        String name;
        Map<String, String> objects = new LinkedHashMap<>();
        List<Atom> initial = new ArrayList<>(), goals = new ArrayList<>();
        List<String> diagnostics = new ArrayList<>();
        Problem(String name) { this.name = name; }
    }
    static String word(Expression expression) { return ((Word)expression).value(); }
    static List<Expression> list(Expression expression) { return ((Sequence)expression).values(); }
    static List<String> words(List<Expression> expressions) {
        List<String> result = new ArrayList<>();
        for (Expression expression : expressions)
            result.add(word(expression));
        return result;
    }
    static List<Expression> expressions(String text) {
        List<Expression> roots = new ArrayList<>();
        Deque<List<Expression>> stack = new ArrayDeque<>();
        stack.push(roots);
        StringBuilder cleaned = new StringBuilder();
        for (String line : text.split("\n", -1)) {
            int comment = line.indexOf(';');
            cleaned.append(comment < 0 ? line : line.substring(0, comment)).append('\n');
        }
        String source = cleaned.toString();
        for (int i = 0; i < source.length();) {
            char c = source.charAt(i);
            if (c == ' ' || c == '\n') {
                i++;
                continue;
            }
            if (c == '(') {
                List<Expression> child = new ArrayList<>();
                stack.peek().add(new Sequence(child));
                stack.push(child);
                i++;
            } else if (c == ')') {
                stack.pop();
                i++;
            } else {
                int start = i;
                while (i < source.length() && " ()\n".indexOf(source.charAt(i)) < 0)
                    i++;
                stack.peek().add(new Word(source.substring(start, i)));
            }
        }
        return roots;
    }
    static List<Typed> typedList(List<String> words) {
        List<Typed> result = new ArrayList<>();
        List<String> pending = new ArrayList<>();
        for (int i = 0; i < words.size();) {
            String word = words.get(i);
            if (word.equals("-")) {
                String type = words.get(i + 1);
                for (String name : pending)
                    result.add(new Typed(name, type));
                pending.clear();
                i += 2;
            } else {
                pending.add(word);
                i++;
            }
        }
        for (String name : pending)
            result.add(new Typed(name, "object"));
        return result;
    }
    static Atom atom(Expression expression) {
        List<Expression> values = list(expression);
        return new Atom(word(values.getFirst()), words(values.subList(1, values.size())));
    }
    static List<Expression> elements(Expression expression, boolean empty) {
        List<Expression> values = list(expression);
        boolean conjunction = !values.isEmpty() && word(values.getFirst()).equals("and");
        for (Expression item : values.subList(1, values.size()))
            if (!(item instanceof Sequence))
                conjunction = false;
        return conjunction && (empty || values.size() > 1) ? values.subList(1, values.size())
                                                           : List.of(expression);
    }
    static Literal literal(Expression expression) {
        List<Expression> values = list(expression);
        if (word(values.getFirst()).equals("not") && values.size() == 2 &&
            values.get(1) instanceof Sequence)
            return new Literal(false, atom(values.get(1)));
        return new Literal(true, atom(expression));
    }
    static Domain readDomain(String text) {
        List<Expression> expression = list(expressions(text).getFirst());
        Domain domain = new Domain(word(list(expression.get(1)).get(1)));
        for (Expression raw : expression.subList(2, expression.size())) {
            List<Expression> section = list(raw);
            String kind = word(section.getFirst());
            if (kind.equals(":types")) {
                List<String> words = words(section.subList(1, section.size()));
                for (String name : words)
                    if (!name.equals("-") && !domain.parents.containsKey(name)) {
                        domain.parents.put(name, "object");
                        domain.typeOrder.add(name);
                    }
                for (Typed type : typedList(words))
                    domain.parents.put(type.name(), type.type());
            } else if (kind.equals(":predicates"))
                for (Expression declaration : section.subList(1, section.size())) {
                    List<Expression> values = list(declaration);
                    List<String> types = new ArrayList<>();
                    for (Typed parameter : typedList(words(values.subList(1, values.size()))))
                        types.add(parameter.type());
                    domain.predicates.put(word(values.getFirst()), types);
                }
            else if (kind.equals(":action")) {
                Map<String, Expression> fields = new HashMap<>();
                for (int i = 2; i < section.size(); i += 2)
                    fields.put(word(section.get(i)), section.get(i + 1));
                List<Literal> condition = new ArrayList<>();
                if (fields.containsKey(":precondition"))
                    for (Expression item : elements(fields.get(":precondition"), true))
                        condition.add(literal(item));
                List<Literal> effects = new ArrayList<>();
                int cost = 1;
                for (Expression item : elements(fields.get(":effect"), false)) {
                    List<Expression> value = list(item);
                    if (word(value.getFirst()).equals("increase") && value.size() == 3 &&
                        list(value.get(1)).size() == 1 &&
                        word(list(value.get(1)).getFirst()).equals("total-cost"))
                        cost = Integer.parseInt(word(value.get(2)));
                    else
                        effects.add(literal(item));
                }
                domain.actions.add(new Schema(word(section.get(1)),
                                              typedList(words(list(fields.get(":parameters")))),
                                              condition, effects, cost));
            }
        }
        return domain;
    }
    static List<Problem> readProblems(String text) {
        List<Problem> problems = new ArrayList<>();
        for (Expression raw : expressions(text)) {
            List<Expression> expression = list(raw);
            Problem problem = new Problem(word(list(expression.get(1)).get(1)));
            Map<String, List<Expression>> sections = new HashMap<>();
            for (Expression item : expression.subList(2, expression.size())) {
                List<Expression> section = list(item);
                sections.put(word(section.getFirst()), section.subList(1, section.size()));
            }
            for (Typed object : typedList(words(sections.get(":objects"))))
                problem.objects.put(object.name(), object.type());
            for (Expression item : sections.get(":init"))
                problem.initial.add(atom(item));
            for (Expression item : elements(sections.get(":goal").getFirst(), false))
                problem.goals.add(atom(item));
            problems.add(problem);
        }
        return problems;
    }
}
