import java.io.*;
import java.util.*;

public class Main {
    static final Object MISSING = new Object();
    static final String IDENT = "[A-Za-z_][A-Za-z0-9_]*";
    static final Set<String> COMMANDS = Set.of("GET", "COMPACT", "PRETTY", "TYPE", "LENGTH", "KEYS", "FLATTEN", "COUNT", "SUM", "MIN", "MAX", "AVG", "FILTER", "SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME", "UNDO");
    static Object document;
    static final List<Object> history = new ArrayList<>();
    static class Problem extends RuntimeException {
        Problem(String message) {
            super(message);
        }
    }

    static class ParseError extends RuntimeException {
        final int position;
        ParseError(int position, String reason) {
            super(reason);
            this.position = position;
        }
    }
    @SuppressWarnings("unchecked")
    static LinkedHashMap<String, Object> object(Object v) {
        return (LinkedHashMap<String, Object>) v;
    }
    @SuppressWarnings("unchecked")
    static List<Object> array(Object v) {
        return (List<Object>) v;
    }

    static boolean letter(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    }

    static boolean digit(char c) {
        return c >= '0' && c <= '9';
    }

    static boolean integerNotation(String s) {
        return s.matches("0|-?[1-9][0-9]{0,8}");
    }

    static String quote(String s, char delimiter) {
        StringBuilder out = new StringBuilder().append(delimiter);
        for (char c : s.toCharArray()) {
            if (c == delimiter || c == '\\') out.append('\\').append(c);
            else out.append(switch (c) {
                case '\b' -> "\\b"; case '\f' -> "\\f"; case '\n' -> "\\n"; case '\r' -> "\\r"; case '\t' -> "\\t"; default -> c < 32 || c == 127 ? String.format(Locale.ROOT, "\\u%04x", (int)c) : "" + c;
            });
        }
        return out.append(delimiter).toString();
    }

    static class Parser {
        final String text;
        int at;
        Parser(String text) {
            this.text = text;
        }
        char peek() {
            return at == text.length() ? '\0' : text.charAt(at);
        }
        void fail(String reason) {
            throw new ParseError(at, reason);
        }
        void whitespace() {
            while (peek() == ' ' || peek() == '\n') at++;
        }
        void needCharacter() {
            if (at == text.length()) fail("unexpected end of input");
        }
        String string(char delimiter) {
            at++;
            StringBuilder out = new StringBuilder();
            while (true) {
                if (at == text.length() || peek() == '\n') fail("unterminated string");
                char c = peek();
                if (c == delimiter) {
                    at++;
                    return out.toString();
                }
                if (c != '\\') {
                    out.append(c);
                    at++;
                    continue;
                }
                int start = at;
                at++;
                if (at == text.length() || peek() == '\n') fail("unterminated string");
                char escaped = peek();
                if (escaped == 'u') {
                    if (at + 4 >= text.length() || !text.substring(at + 1, at + 5).matches("[0-9A-Fa-f]{4}")) throw new ParseError(start, "bad unicode escape");
                    int value = Integer.parseInt(text.substring(at + 1, at + 5), 16);
                    if (value > 127) throw new ParseError(start, "non-ascii escape");
                    out.append((char)value);
                    at += 5;
                } else {
                    char value = switch (escaped) {
                        case '\\', '/' -> escaped;
                        case 'b' -> '\b';
                        case 'f' -> '\f';
                        case 'n' -> '\n';
                        case 'r' -> '\r';
                        case 't' -> '\t';
                        default -> escaped == delimiter ? delimiter : '\0';
                    };
                    if (value == '\0') throw new ParseError(start, "invalid escape '\\" + escaped + "'");
                    out.append(value);
                    at++;
                }
            }
        }
        Object value() {
            whitespace();
            needCharacter();
            char c = peek();
            if (c == '"') return string('"');
            if (c == '{') {
                at++;
                whitespace();
                LinkedHashMap<String, Object> map = new LinkedHashMap<>();
                if (peek() == '}') {
                    at++;
                    return map;
                }
                while (true) {
                    whitespace();
                    needCharacter();
                    if (peek() != '"') fail("expected key");
                    int start = at;
                    String key = string('"');
                    if (map.containsKey(key)) throw new ParseError(start, "duplicate key " + quote(key, '"'));
                    whitespace();
                    needCharacter();
                    if (peek() != ':') fail("expected ':'");
                    at++;
                    map.put(key, value());
                    whitespace();
                    if (peek() == '}') {
                        at++;
                        return map;
                    }
                    needCharacter();
                    if (peek() != ',') fail("expected ',' or '}'");
                    at++;
                    whitespace();
                    if (peek() == '}') fail("trailing comma");
                }
            }
            if (c == '[') {
                at++;
                whitespace();
                List<Object> list = new ArrayList<>();
                if (peek() == ']') {
                    at++;
                    return list;
                }
                while (true) {
                    list.add(value());
                    whitespace();
                    if (peek() == ']') {
                        at++;
                        return list;
                    }
                    needCharacter();
                    if (peek() != ',') fail("expected ',' or ']'");
                    at++;
                    whitespace();
                    if (peek() == ']') fail("trailing comma");
                }
            }
            if (c == '-' || digit(c)) {
                int start = at;
                if (c == '-') at++;
                int digits = at;
                while (digit(peek())) at++;
                if (at == digits) throw new ParseError(start, "invalid number");
                if (at - digits >= 2 && text.charAt(digits) == '0') throw new ParseError(digits, "leading zero");
                if (peek() == '.') fail("fraction not allowed");
                if (peek() == 'e' || peek() == 'E') fail("exponent not allowed");
                if (at - digits >= 10) throw new ParseError(start, "number out of range");
                return Integer.parseInt(text.substring(start, at));
            }
            if (letter(c)) {
                int start = at;
                while (letter(peek())) at++;
                String word = text.substring(start, at);
                return switch (word) {
                    case "true" -> true;
                    case "false" -> false;
                    case "null" -> null;
                    default -> throw new ParseError(start, "invalid literal '" + word + "'");
                };
            }
            fail("unexpected character '" + c + "'");
            return null;
        }
        Object whole() {
            Object result = value();
            whitespace();
            if (at != text.length()) fail("trailing characters");
            return result;
        }
    }

    static Object copy(Object v) {
        if (v instanceof Map) {
            LinkedHashMap<String, Object> out = new LinkedHashMap<>();
            object(v).forEach((key, value) -> out.put(key, copy(value)));
            return out;
        }
        if (v instanceof List) {
            List<Object> out = new ArrayList<>();
            for (Object item : array(v)) out.add(copy(item));
            return out;
        }
        return v;
    }

    static String compact(Object v) {
        if (v == null) return "null";
        if (v instanceof String s) return quote(s, '"');
        if (v instanceof Map) {
            List<String> parts = new ArrayList<>();
            object(v).forEach((key, value) -> parts.add(quote(key, '"') + ":" + compact(value)));
            return "{" + String.join(",", parts) + "}";
        }
        if (v instanceof List) {
            List<String> parts = new ArrayList<>();
            for (Object item : array(v)) parts.add(compact(item));
            return "[" + String.join(",", parts) + "]";
        }
        return v.toString();
    }

    static String pretty(Object v, String indent) {
        if (v instanceof Map && !object(v).isEmpty() || v instanceof List && !array(v).isEmpty()) {
            String child = indent + "  ";
            List<String> parts = new ArrayList<>();
            if (v instanceof Map) object(v).forEach((key, value) -> parts.add(child + quote(key, '"') + ": " + pretty(value, child)));
            else for (Object item : array(v)) parts.add(child + pretty(item, child));
            return (v instanceof Map ? "{" : "[") + "\n" + String.join(",\n", parts) + "\n" + indent + (v instanceof Map ? "}" : "]");
        }
        return compact(v);
    }

    static String type(Object v) {
        return v == null ? "null" : v instanceof Map ? "object" : v instanceof List ? "array" : v instanceof String ? "string" : v instanceof Integer ? "number" : "boolean";
    }
    record Selector(char kind, String key, Integer first, Integer last, boolean descendant) {}
    static class PathReader extends Parser {
        PathReader(String text) {
            super(text);
        }
        String identifier() {
            int start = at;
            if (!letter(peek()) && peek() != '_') throw new Problem("");
            at++;
            while (letter(peek()) || digit(peek()) || peek() == '_') at++;
            return text.substring(start, at);
        }
        List<Selector> read(boolean field) {
            if (peek() != (field ? '@' : '$')) throw new Problem("");
            at++;
            List<Selector> selectors = new ArrayList<>();
            while (at < text.length()) {
                boolean descendant = false;
                if (peek() == '.') {
                    at++;
                    if (peek() == '.') {
                        if (field) throw new Problem("");
                        descendant = true;
                        at++;
                    }
                    if (peek() == '*') {
                        if (field) throw new Problem("");
                        at++;
                        selectors.add(new Selector('A', null, null, null, descendant));
                        continue;
                    }
                    if (!(descendant && peek() == '[')) {
                        selectors.add(new Selector('K', identifier(), null, null, descendant));
                        continue;
                    }
                } else if (peek() != '[') throw new Problem("");
                if (peek() != '[') throw new Problem("");
                at++;
                if (peek() == '\'') {
                    String key = string('\'');
                    if (peek() != ']') throw new Problem("");
                    at++;
                    selectors.add(new Selector('K', key, null, null, descendant));
                    continue;
                }
                int end = text.indexOf(']', at);
                if (end < 0) throw new Problem("");
                String content = text.substring(at, end);
                at = end + 1;
                if (content.equals("*") && !field) selectors.add(new Selector('A', null, null, null, descendant));
                else if (integerNotation(content)) selectors.add(new Selector('I', null, Integer.valueOf(content), null, descendant));
                else if (!field && content.contains(":")) {
                    String[] parts = content.split(":", -1);
                    if (parts.length != 2 || !parts[0].isEmpty() && !integerNotation(parts[0]) || !parts[1].isEmpty() && !integerNotation(parts[1])) throw new Problem("");
                    selectors.add(new Selector('S', null, parts[0].isEmpty() ? null : Integer.valueOf(parts[0]), parts[1].isEmpty() ? null : Integer.valueOf(parts[1]), descendant));
                } else throw new Problem("");
            }
            return selectors;
        }
    }

    static List<Selector> path(String text, boolean field) {
        try {
            return new PathReader(text).read(field);
        } catch (Problem | ParseError ex) {
            throw new Problem("ERROR bad " + (field ? "field" : "path"));
        }
    }

    static String key(String text) {
        if (text.matches(IDENT)) return text;
        try {
            PathReader reader = new PathReader(text);
            if (reader.peek() != '\'') throw new Problem("");
            String key = reader.string('\'');
            if (reader.at != text.length()) throw new Problem("");
            return key;
        } catch (Problem | ParseError ex) {
            throw new Problem("ERROR bad key");
        }
    }
    record Step(Object key, int position) {}
    record Match(Object value, List<Step> location) {}

    static Match child(Match parent, Object key, int position) {
        List<Step> location = new ArrayList<>(parent.location());
        location.add(new Step(key, position));
        Object value = key instanceof String ? object(parent.value()).get(key) : array(parent.value()).get((int)key);
        return new Match(value, location);
    }

    static List<Match> children(Match parent) {
        List<Match> out = new ArrayList<>();
        if (parent.value() instanceof Map) {
            int i = 0;
            for (String key : object(parent.value()).keySet()) out.add(child(parent, key, i++));
        } else if (parent.value() instanceof List) for (int i = 0; i < array(parent.value()).size(); i++) out.add(child(parent, i, i));
        return out;
    }

    static void preorder(Match match, List<Match> out) {
        out.add(match);
        for (Match child : children(match)) preorder(child, out);
    }

    static List<Match> select(Match match, Selector selector) {
        List<Match> out = new ArrayList<>();
        Object value = match.value();
        if (selector.kind() == 'K' && value instanceof Map && object(value).containsKey(selector.key())) {
            int pos = new ArrayList<>(object(value).keySet()).indexOf(selector.key());
            out.add(child(match, selector.key(), pos));
        } else if (selector.kind() == 'A') out.addAll(children(match));
        else if (value instanceof List && (selector.kind() == 'I' || selector.kind() == 'S')) {
            int n = array(value).size();
            if (selector.kind() == 'I') {
                int i = selector.first() < 0 ? n + selector.first() : selector.first();
                if (i >= 0 && i < n) out.add(child(match, i, i));
            } else {
                int a = selector.first() == null ? 0 : selector.first(), b = selector.last() == null ? n : selector.last();
                if (a < 0) a += n;
                if (b < 0) b += n;
                a = Math.clamp(a, 0, n);
                b = Math.clamp(b, 0, n);
                for (int i = a; i < b; i++) out.add(child(match, i, i));
            }
        }
        return out;
    }

    static List<Match> apply(List<Match> matches, Selector selector) {
        List<Match> out = new ArrayList<>();
        for (Match match : matches) {
            List<Match> bases = new ArrayList<>();
            if (selector.descendant()) preorder(match, bases);
            else bases.add(match);
            for (Match base : bases) out.addAll(select(base, selector));
        }
        return out;
    }

    static List<Match> evaluate(List<Selector> selectors) {
        List<Match> matches = new ArrayList<>();
        matches.add(new Match(document, List.of()));
        for (Selector selector : selectors) matches = apply(matches, selector);
        return matches;
    }

    static String location(List<Step> steps) {
        StringBuilder out = new StringBuilder("$");
        for (Step step : steps) if (step.key() instanceof String s) out.append(s.matches(IDENT) ? "." + s : "[" + quote(s, '\'') + "]");
        else out.append("[").append(step.key()).append("]");
        return out.toString();
    }

    static Object at(Object root, List<Step> steps) {
        Object value = root;
        for (Step step : steps) value = step.key() instanceof String ? object(value).get(step.key()) : array(value).get((int)step.key());
        return value;
    }

    static Object field(Object value, List<Selector> selectors) {
        for (Selector selector : selectors) {
            List<Match> selected = select(new Match(value, List.of()), selector);
            if (selected.isEmpty()) return MISSING;
            value = selected.getFirst().value();
        }
        return value;
    }

    static boolean equal(Object a, Object b) {
        return Objects.equals(a, b);
    }

    static int rank(Object value) {
        return value == null ? 0 : value instanceof Integer ? 1 : value instanceof String ? 2 : 3;
    }

    static int compare(Object a, Object b) {
        int order = Integer.compare(rank(a), rank(b));
        if (order != 0) return order;
        return rank(a) == 1 ? Integer.compare((int)a, (int)b) : rank(a) == 2 ? ((String)a).compareTo((String)b) : 0;
    }

    static void merge(Object target, Object source) {
        for (var entry : object(source).entrySet()) {
            Object old = object(target).get(entry.getKey());
            if (old instanceof Map && entry.getValue() instanceof Map) merge(old, entry.getValue());
            else object(target).put(entry.getKey(), copy(entry.getValue()));
        }
    }

    static int compareLocations(Match a, Match b) {
        for (int i = 0; i < Math.min(a.location().size(), b.location().size()); i++) {
            int c = Integer.compare(a.location().get(i).position(), b.location().get(i).position());
            if (c != 0) return c;
        }
        return Integer.compare(a.location().size(), b.location().size());
    }

    static List<Match> targets(List<Match> matches) {
        Map<String, Match> unique = new LinkedHashMap<>();
        for (Match match : matches) unique.putIfAbsent(location(match.location()), match);
        List<Match> out = new ArrayList<>(unique.values());
        out.sort((a, b) -> compareLocations(b, a));
        return out;
    }

    static void require(boolean condition, String error) {
        if (!condition) throw new Problem(error);
    }

    static void requireType(List<Match> matches, String kind) {
        for (Match match : matches) require(type(match.value()).equals(kind), "ERROR not an " + kind + " at " + location(match.location()));
    }

    static Object jsonValue(String text) {
        try {
            return new Parser(text).whole();
        } catch (ParseError ex) {
            throw new Problem("PARSE ERROR col " + (ex.position + 1) + ": " + ex.getMessage());
        }
    }

    static List<String> execute(String line) {
        int space = line.indexOf(' ');
        String command = space < 0 ? line : line.substring(0, space), argument = space < 0 ? null : line.substring(space + 1);
        require(COMMANDS.contains(command), "ERROR unknown command '" + command + "'");
        String[] args = argument == null ? new String[0] : argument.split(" ", command.equals("SET") || command.equals("MERGE") ? 2 : command.equals("INSERT") ? 3 : command.equals("FILTER") ? 4 : -1);
        boolean shape = switch (command) {
            case "SET", "MERGE", "RENAME" -> args.length == 2;
            case "INSERT" -> args.length == 3;
            case "FILTER" -> args.length >= 3 && (args[2].equals("EXISTS") ? args.length == 3 : args.length == 4);
            case "COMPACT", "PRETTY", "FLATTEN" -> args.length <= 1;
            case "UNDO" -> args.length == 0;
            case "SORT" -> args.length >= 1 && args.length <= 3 && (args.length < 3 || !args[1].equals("DESC") && args[2].equals("DESC"));
            default -> args.length == 1;
        };
        require(shape, "ERROR bad arguments");
        if (command.equals("UNDO")) {
            require(!history.isEmpty(), "ERROR nothing to undo");
            document = history.removeLast();
            return List.of("UNDO " + history.size());
        }
        List<Selector> selectors = path(args.length == 0 ? "$" : args[0], false), fields = List.of();
        Object value = null;
        int index = 0;
        String rename = null, operator = null;
        if (command.equals("FILTER")) {
            fields = path(args[1], true);
            operator = args[2];
            require(Set.of("==", "!=", "<", "<=", ">", ">=", "EXISTS").contains(operator), "ERROR bad operator");
            if (!operator.equals("EXISTS")) value = jsonValue(args[3]);
        } else if (command.equals("SORT")) fields = path(args.length >= 2 && !args[1].equals("DESC") ? args[1] : "@", true);
        else if (command.equals("RENAME")) rename = key(args[1]);
        else if (command.equals("INSERT")) {
            require(integerNotation(args[1]), "ERROR bad index");
            index = Integer.parseInt(args[1]);
            value = jsonValue(args[2]);
        } else if (command.equals("SET") || command.equals("MERGE")) value = jsonValue(args[1]);
        if (command.equals("MERGE")) require(value instanceof Map, "ERROR merge value is not an object");
        if (command.equals("DELETE")) require(!selectors.isEmpty(), "ERROR cannot delete root");
        List<Match> matches = evaluate(selectors);
        if (Set.of("FILTER", "INSERT", "SORT").contains(command)) requireType(matches, "array");
        if (Set.of("KEYS", "MERGE").contains(command)) requireType(matches, "object");
        if (command.equals("LENGTH")) for (Match match : matches) require(match.value() instanceof Map || match.value() instanceof List || match.value() instanceof String, "ERROR no length at " + location(match.location()));
        if (command.equals("INSERT")) for (Match match : matches) require(index >= -array(match.value()).size() - 1 && index <= array(match.value()).size(), "ERROR index out of range at " + location(match.location()));
        if (command.equals("RENAME")) for (Match match : matches) require(!match.location().isEmpty() && match.location().getLast().key() instanceof String, "ERROR not a member at " + location(match.location()));
        List<String> out = new ArrayList<>();
        if (Set.of("SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME").contains(command)) {
            if (command.equals("SET") && !selectors.isEmpty()) {
                Selector last = selectors.getLast();
                if (last.kind() == 'K' && !last.descendant()) {
                    matches = new ArrayList<>();
                    for (Match parent : evaluate(selectors.subList(0, selectors.size() - 1))) if (parent.value() instanceof Map) {
                        List<Step> place = new ArrayList<>(parent.location());
                        int pos = new ArrayList<>(object(parent.value()).keySet()).indexOf(last.key());
                        place.add(new Step(last.key(), pos < 0 ? object(parent.value()).size() : pos));
                        matches.add(new Match(null, place));
                    }
                }
            }
            List<Match> targets = targets(matches);
            Object changed = copy(document);
            for (Match target : targets) {
                List<Step> place = target.location();
                Object current = command.equals("SET") ? null : at(changed, place);
                if (command.equals("SET")) {
                    if (place.isEmpty()) changed = copy(value);
                    else {
                        Object parent = at(changed, place.subList(0, place.size() - 1));
                        Object part = place.getLast().key();
                        if (part instanceof String s) object(parent).put(s, copy(value));
                        else array(parent).set((int)part, copy(value));
                    }
                } else if (command.equals("DELETE")) {
                    Object parent = at(changed, place.subList(0, place.size() - 1));
                    Object part = place.getLast().key();
                    if (part instanceof String) object(parent).remove(part);
                    else array(parent).remove((int)part);
                } else if (command.equals("INSERT")) array(current).add(index < 0 ? array(current).size() + 1 + index : index, copy(value));
                else if (command.equals("MERGE")) merge(current, value);
                else if (command.equals("SORT")) {
                    List<Selector> sortFields = fields;
                    boolean descending = args[args.length - 1].equals("DESC");
                    array(current).sort((a, b) -> (descending ? -1 : 1) * compare(field(a, sortFields), field(b, sortFields)));
                } else {
                    Object parent = at(changed, place.subList(0, place.size() - 1));
                    String old = (String)place.getLast().key();
                    require(old.equals(rename) || !object(parent).containsKey(rename), "ERROR key exists at " + location(place));
                    LinkedHashMap<String, Object> renamed = new LinkedHashMap<>();
                    for (var entry : object(parent).entrySet()) renamed.put(entry.getKey().equals(old) ? rename : entry.getKey(), entry.getValue());
                    object(parent).clear();
                    object(parent).putAll(renamed);
                }
            }
            history.add(copy(document));
            document = changed;
            return List.of(command + " " + targets.size());
        }
        if (command.equals("COUNT")) return List.of("COUNT " + matches.size());
        if (Set.of("SUM", "MIN", "MAX", "AVG").contains(command)) {
            long total = 0;
            Integer minimum = null, maximum = null;
            int count = 0;
            for (Match match : matches) if (match.value() instanceof Integer n) {
                total += n;
                count++;
                minimum = minimum == null ? n : Math.min(minimum, n);
                maximum = maximum == null ? n : Math.max(maximum, n);
            }
            String result = command.equals("SUM") ? "" + total : command.equals("MIN") ? "" + minimum : command.equals("MAX") ? "" + maximum : "null";
            if (command.equals("AVG") && count > 0) {
                long q = (Math.abs(total) * 200 + count) / (2L * count);
                result = (total < 0 && q > 0 ? "-" : "") + q / 100 + "." + String.format(Locale.ROOT, "%02d", q % 100);
            }
            return List.of(command + " " + result);
        }
        if (command.equals("FILTER")) {
            for (Match match : matches) for (Match child : children(match)) {
                Object f = field(child.value(), fields);
                boolean equality = f != MISSING && equal(f, value), pass;
                if (operator.equals("EXISTS")) pass = f != MISSING;
                else if (operator.equals("==") || operator.equals("!=")) pass = operator.equals("==") == equality;
                else {
                    boolean comparable = f instanceof Integer && value instanceof Integer || f instanceof String && value instanceof String;
                    int order = comparable ? compare(f, value) : 0;
                    pass = comparable && switch (operator) {
                        case "<" -> order < 0;
                        case "<=" -> order <= 0;
                        case ">" -> order > 0;
                        default -> order >= 0;
                    };
                }
                if (pass) out.add(location(child.location()) + " = " + compact(child.value()));
            }
        } else for (Match match : matches) {
            String place = location(match.location());
            Object item = match.value();
            switch (command) {
                case "GET":
                    out.add(place + " = " + compact(item));
                    break;
                case "COMPACT":
                    out.add(compact(item));
                    break;
                case "PRETTY":
                    out.add(pretty(item, ""));
                    break;
                case "TYPE":
                    out.add(place + " " + type(item));
                    break;
                case "LENGTH":
                    out.add(place + " " + (item instanceof Map ? object(item).size() : item instanceof List ? array(item).size() : ((String)item).length()));
                    break;
                case "KEYS":
                    out.add(place + " " + compact(new ArrayList<>(object(item).keySet())));
                    break;
                case "FLATTEN":
                    List<Match> descendants = new ArrayList<>();
                    preorder(match, descendants);
                    for (Match leaf : descendants) if (children(leaf).isEmpty()) out.add(location(leaf.location()) + " = " + compact(leaf.value()));
                    break;
            }
        }
        return out.isEmpty() ? List.of("no match") : out;
    }

    static int[] size(Object v) {
        int count = 1, depth = 1;
        for (Match child : children(new Match(v, List.of()))) {
            int[] childSize = size(child.value());
            count += childSize[0];
            depth = Math.max(depth, childSize[1] + 1);
        }
        return new int[]{count, depth};
    }

    static void load(List<String> body) {
        String text = String.join("\n", body);
        try {
            Object value = new Parser(text).whole();
            history.add(copy(document));
            document = value;
            int[] size = size(value);
            System.out.println("LOADED nodes=" + size[0] + " depth=" + size[1]);
        } catch (ParseError ex) {
            int line = 1, column = 1;
            for (int i = 0; i < ex.position; i++) {
                if (text.charAt(i) == '\n') {
                    line++;
                    column = 1;
                } else column++;
            }
            System.out.println("PARSE ERROR line " + line + " col " + column + ": " + ex.getMessage());
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        List<String> body = new ArrayList<>();
        String line;
        while (!(line = input.readLine()).equals("%%")) body.add(line);
        load(body);
        while (!(line = input.readLine()).equals("END")) {
            if (line.equals("LOAD")) {
                body = new ArrayList<>();
                while (!(line = input.readLine()).equals("%%")) body.add(line);
                load(body);
            } else try {
                execute(line).forEach(System.out::println);
            } catch (Problem ex) {
                System.out.println(ex.getMessage());
            }
        }
    }
}
