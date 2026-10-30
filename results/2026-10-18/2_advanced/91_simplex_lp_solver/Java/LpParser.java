import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class LpParser {
    record Term(String name, Rational coefficient) {}
    record Named(String name, List<Term> terms) {}
    record Constraint(int line, String name, List<Term> terms, String comparison, Rational rhs) {}
    record Bound(int line, String name, String kind, Rational lower, Rational upper) {}
    record Declaration(int line, List<String> names) {}
    record Error(int line, String message) {}
    record Line(int number, String text) {}
    static final class Parsed {
        String name, direction;
        Error error;
        List<Term> objective;
        List<Constraint> constraints = new ArrayList<>();
        List<Bound> bounds = new ArrayList<>();
        List<Declaration> integers = new ArrayList<>(), binaries = new ArrayList<>();
        Parsed(String name) { this.name = name; }
    }
    record Settings(int level, int limit, Map<String, Integer> logs, Map<String, Integer> limits) {}
    static boolean name(String word) {
        return word.matches("[a-z][a-z0-9_]*") &&
            !Set.of("bounds", "integer", "binary", "free", "inf").contains(word);
    }
    static List<Term> expression(List<String> words) {
        List<Term> terms = new ArrayList<>();
        int position = 0, sign = 1;
        if (!words.isEmpty() && words.getFirst().equals("-")) {
            sign = -1;
            position = 1;
        }
        while (position < words.size()) {
            Rational coefficient = Rational.read(words.get(position), false);
            String name;
            if (coefficient != null) {
                if (position + 1 == words.size() || !name(words.get(position + 1)))
                    return null;
                name = words.get(position + 1);
                position += 2;
            } else if (name(words.get(position))) {
                coefficient = Rational.ONE;
                name = words.get(position++);
            } else
                return null;
            terms.add(new Term(name, coefficient.multiply(sign)));
            if (position == words.size())
                return terms;
            if (!Set.of("+", "-").contains(words.get(position)))
                return null;
            sign = words.get(position++).equals("+") ? 1 : -1;
        }
        return null;
    }
    static Named named(List<String> words) {
        if (words.size() < 2 || !words.getFirst().endsWith(":"))
            return null;
        String name = words.getFirst().substring(0, words.getFirst().length() - 1);
        List<Term> terms = expression(words.subList(1, words.size()));
        return name(name) && terms != null ? new Named(name, terms) : null;
    }
    static Constraint constraint(List<String> words, int line) {
        if (words.size() < 4 || !Set.of("<=", ">=", "=").contains(words.get(words.size() - 2)))
            return null;
        Rational rhs = Rational.read(words.getLast(), true);
        Named named = named(words.subList(0, words.size() - 2));
        return rhs == null || named == null
            ? null
            : new Constraint(line, named.name(), named.terms(), words.get(words.size() - 2), rhs);
    }
    static Bound bound(List<String> words, int line) {
        if (words.size() == 2 && name(words.get(0)) && words.get(1).equals("free"))
            return new Bound(line, words.get(0), "both", null, null);
        if (words.size() == 3 && name(words.get(0))) {
            String name = words.get(0), operator = words.get(1), word = words.get(2);
            Rational value = Rational.read(word, true);
            if (operator.equals(">=") && (value != null || word.equals("-inf")))
                return new Bound(line, name, "lower", value, null);
            if (operator.equals("<=") && (value != null || word.equals("inf")))
                return new Bound(line, name, "upper", null, value);
            if (operator.equals("=") && value != null)
                return new Bound(line, name, "both", value, value);
        }
        if (words.size() == 5 && words.get(1).equals("<=") && words.get(3).equals("<=") &&
            name(words.get(2))) {
            Rational lower = Rational.read(words.get(0), true),
                     upper = Rational.read(words.get(4), true);
            if ((lower != null || words.get(0).equals("-inf")) &&
                (upper != null || words.get(4).equals("inf")))
                return new Bound(line, words.get(2), "both", lower, upper);
        }
        return null;
    }
    static Parsed block(String name, List<Line> body, int endLine) {
        Parsed result = new Parsed(name);
        char state = 'A';
        for (Line line : body) {
            String text = line.text();
            List<String> words = List.of(text.split(" "));
            boolean accepted = false;
            if (state == 'A' && Set.of("maximize", "minimize").contains(text)) {
                result.direction = text;
                state = 'B';
                accepted = true;
            } else if (state == 'B') {
                Named named = named(words);
                if (named != null) {
                    result.objective = named.terms();
                    state = 'C';
                    accepted = true;
                }
            } else if (state == 'C' && text.equals("subject to")) {
                state = 'D';
                accepted = true;
            } else if (state == 'D' || state == 'E') {
                if (state == 'E' && Set.of("bounds", "integer", "binary").contains(text)) {
                    state = text.equals("bounds") ? 'F' : text.equals("integer") ? 'G' : 'H';
                    accepted = true;
                } else {
                    Constraint constraint = constraint(words, line.number());
                    if (constraint != null) {
                        result.constraints.add(constraint);
                        state = 'E';
                        accepted = true;
                    }
                }
            } else if (state == 'F') {
                if (Set.of("integer", "binary").contains(text)) {
                    state = text.equals("integer") ? 'G' : 'H';
                    accepted = true;
                } else {
                    Bound bound = bound(words, line.number());
                    if (bound != null) {
                        result.bounds.add(bound);
                        accepted = true;
                    }
                }
            } else if (state == 'G' || state == 'H') {
                if (state == 'G' && text.equals("binary")) {
                    state = 'H';
                    accepted = true;
                } else if (words.stream().allMatch(LpParser::name)) {
                    (state == 'G' ? result.integers : result.binaries)
                        .add(new Declaration(line.number(), words));
                    accepted = true;
                }
            }
            if (!accepted) {
                result.error = new Error(line.number(), "syntax error");
                return result;
            }
        }
        if (state == 'A' || state == 'B' || state == 'C' || state == 'D')
            result.error = new Error(endLine, "syntax error");
        return result;
    }
    static List<Parsed> models() throws Exception {
        List<Parsed> models = new ArrayList<>();
        String name = null;
        List<Line> body = new ArrayList<>();
        List<String> lines =
            Files.readAllLines(Path.of("input", "models.lp"), StandardCharsets.US_ASCII);
        for (int i = 0; i < lines.size(); i++) {
            String text = lines.get(i);
            if (text.isEmpty() || text.startsWith("#"))
                continue;
            if (name == null) {
                name = text.split(" ")[1];
                body = new ArrayList<>();
            } else if (text.equals("end")) {
                models.add(block(name, body, i + 1));
                name = null;
            } else
                body.add(new Line(i + 1, text));
        }
        return models;
    }
    static Settings settings() throws Exception {
        List<String> lines =
            Files.readAllLines(Path.of("input", "params.txt"), StandardCharsets.US_ASCII);
        int level = Integer.parseInt(lines.get(0).split(" ")[1]),
            limit = Integer.parseInt(lines.get(1).split(" ")[1]);
        Map<String, Integer> logs = new HashMap<>(), limits = new HashMap<>();
        for (int i = 2; i < lines.size(); i++)
            if (!lines.get(i).isEmpty()) {
                String[] fields = lines.get(i).split(" ");
                (fields[0].equals("log") ? logs : limits)
                    .put(fields[1], Integer.parseInt(fields[2]));
            }
        return new Settings(level, limit, logs, limits);
    }
}
