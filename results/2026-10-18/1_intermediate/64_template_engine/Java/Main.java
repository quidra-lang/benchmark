import java.io.*;
import java.util.*;
import java.util.regex.*;

public class Main {
    static final String IDENT = "[A-Za-z_][A-Za-z0-9_]*";
    static final String INDEX = "(?:0|[1-9][0-9]*)";
    static final String NAME = "(?:\\.|@(?:index|number|first|last)|(?:" + IDENT + "|" + INDEX + ")(?:\\.(?:" + IDENT + "|" + INDEX + "))*)";
    static final Set<String> FILTERS = Set.of("upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items", "comma", "sum", "min", "max", "default", "eq", "pad", "lpad", "truncate", "replace", "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt");
    record Line(int number, String text) {}
    record Part(Object key, String prefix) {}
    record Filter(String name, List<Object> args) {}
    record Expression(String name, List<Filter> filters) {}
    static class Failure extends RuntimeException {
        final int line;
        Failure(String reason) {
            this(0, reason);
        }
        Failure(int line, String reason) {
            super(reason);
            this.line = line;
        }
    }

    static class Node {
        char kind;
        int line;
        String text, indent = "";
        Expression expression;
        List<Node> children = new ArrayList<>();
        Node(char kind, int line, String text) {
            this.kind = kind;
            this.line = line;
            this.text = text;
        }
    }

    static Map<String, Object> root = new TreeMap<>();
    static Map<String, List<Line>> partials = new HashMap<>(), templates = new HashMap<>();
    static boolean strict;
    static String strip(String text) {
        int first = 0, last = text.length();
        while (first < last && text.charAt(first) == ' ') first++;
        while (last > first && text.charAt(last - 1) == ' ') last--;
        return text.substring(first, last);
    }
    @SuppressWarnings("unchecked")
    static Map<String, Object> map(Object value) {
        return (Map<String, Object>) value;
    }
    @SuppressWarnings("unchecked")
    static List<Object> list(Object value) {
        return (List<Object>) value;
    }

    static boolean has(Object value, Object key) {
        return key instanceof String ? value instanceof Map && map(value).containsKey(key) : value instanceof List && (int) key >= 0 && (int) key < list(value).size();
    }

    static Object get(Object value, Object key) {
        return key instanceof String ? map(value).get(key) : list(value).get((int) key);
    }

    static void put(Object value, Object key, Object item) {
        if (key instanceof String s) map(value).put(s, item);
        else if ((int) key == list(value).size()) list(value).add(item);
        else list(value).set((int) key, item);
    }

    static Object copy(Object value) {
        if (value instanceof Map) {
            Map<String, Object> result = new TreeMap<>();
            map(value).forEach((key, item) -> result.put(key, copy(item)));
            return result;
        }
        if (value instanceof List) {
            List<Object> result = new ArrayList<>();
            for (Object item : list(value)) result.add(copy(item));
            return result;
        }
        return value;
    }

    static List<Part> keyParts(String key) {
        if (!key.matches(IDENT + "(?:\\." + IDENT + "|\\[" + INDEX + "\\])*")) throw new Failure("bad key '" + key + "'");
        List<Part> result = new ArrayList<>();
        Matcher matcher = Pattern.compile("(" + IDENT + ")|\\[(" + INDEX + ")\\]").matcher(key);
        while (matcher.find()) result.add(new Part(matcher.group(1) != null ? matcher.group(1) : Integer.parseInt(matcher.group(2)), key.substring(0, matcher.end())));
        return result;
    }

    static class ValueReader {
        final String text;
        int pos;
        ValueReader(String text) {
            this.text = text;
        }
        Object scalar() {
            if (pos < text.length() && text.charAt(pos) == '"') {
                pos++;
                StringBuilder out = new StringBuilder();
                while (pos < text.length()) {
                    char c = text.charAt(pos++);
                    if (c == '"') return out.toString();
                    if (c == '\\') {
                        if (pos == text.length()) throw new Failure("");
                        c = text.charAt(pos++);
                        if (c == 'n') c = '\n';
                        else if (c != '"' && c != '\\') throw new Failure("");
                    }
                    out.append(c);
                }
                throw new Failure("");
            }
            int start = pos;
            while (pos < text.length() && text.charAt(pos) != ',' && text.charAt(pos) != ']') pos++;
            String word = text.substring(start, pos);
            if (word.equals("true") || word.equals("false")) return Boolean.valueOf(word);
            if (!word.matches("0|-?[1-9][0-9]*")) throw new Failure("");
            return Integer.parseInt(word);
        }
        Object read() {
            if (text.equals("{}")) {
                pos = 2;
                return new TreeMap<String, Object>();
            }
            if (text.equals("[]")) {
                pos = 2;
                return new ArrayList<Object>();
            }
            if (!text.startsWith("[")) return scalar();
            pos = 1;
            List<Object> result = new ArrayList<>();
            while (true) {
                result.add(scalar());
                if (text.startsWith(", ", pos)) pos += 2;
                else if (text.substring(pos).equals("]")) {
                    pos++;
                    return result;
                } else throw new Failure("");
            }
        }
    }

    static Object value(String text) {
        try {
            ValueReader reader = new ValueReader(text);
            Object result = reader.read();
            if (reader.pos != text.length()) throw new Failure("");
            return result;
        } catch (Failure | NumberFormatException ex) {
            throw new Failure("bad value '" + text + "'");
        }
    }

    static void data(List<Line> lines) {
        int sets = 0, unsets = 0;
        List<String> errors = new ArrayList<>();
        for (Line line : lines) {
            String text = line.text();
            if (text.isEmpty() || text.startsWith("#")) continue;
            try {
                boolean remove = text.startsWith("UNSET ");
                int equal = text.indexOf(" = ");
                if (!remove && equal < 0) throw new Failure("bad line");
                String key = remove ? text.substring(6) : text.substring(0, equal);
                List<Part> parts = keyParts(key);
                Object item = remove ? null : value(text.substring(equal + 3));
                Map<String, Object> candidate = map(copy(root));
                Object container = candidate;
                for (int i = 0; i < parts.size(); i++) {
                    Part part = parts.get(i);
                    boolean found = has(container, part.key());
                    if (remove) {
                        if (!found) throw new Failure("no value at '" + key + "'");
                        if (i == parts.size() - 1) {
                            if (part.key() instanceof String) map(container).remove(part.key());
                            else list(container).remove((int) part.key());
                        } else container = get(container, part.key());
                    } else {
                        if (part.key() instanceof Integer n && n > list(container).size()) throw new Failure("index gap at '" + part.prefix() + "'");
                        if (i == parts.size() - 1) put(container, part.key(), item);
                        else {
                            boolean wantMap = parts.get(i + 1).key() instanceof String;
                            if (found) {
                                Object next = get(container, part.key());
                                if (wantMap ? !(next instanceof Map) : !(next instanceof List)) throw new Failure("type conflict at '" + part.prefix() + "'");
                                container = next;
                            } else {
                                Object next = wantMap ? new TreeMap<String, Object>() : new ArrayList<Object>();
                                put(container, part.key(), next);
                                container = next;
                            }
                        }
                    }
                }
                root = candidate;
                if (remove) unsets++;
                else sets++;
            } catch (Failure ex) {
                errors.add("ERROR line " + line.number() + ": " + ex.getMessage());
            }
        }
        System.out.println("DATA set=" + sets + " unset=" + unsets + " errors=" + errors.size());
        errors.forEach(System.out::println);
    }

    static List<String> split(String text, char separator) {
        List<String> result = new ArrayList<>();
        int start = 0;
        boolean quote = false;
        for (int i = 0; i < text.length(); i++) {
            if (text.charAt(i) == '\'') quote = !quote;
            else if (text.charAt(i) == separator && !quote) {
                result.add(text.substring(start, i));
                start = i + 1;
            }
        }
        result.add(text.substring(start));
        return result;
    }

    static boolean arguments(String name, List<Object> args) {
        int n = args.size();
        boolean integer = n > 0 && args.get(0) instanceof Integer;
        boolean string = n > 0 && args.get(0) instanceof String;
        return switch (name) {
            case "default", "eq" -> n == 1;
            case "pad", "lpad" -> (n == 1 || n == 2) && integer && (int) args.get(0) >= 0 && (n == 1 || args.get(1) instanceof String s && s.length() == 1);
            case "truncate" -> n == 1 && integer && (int) args.get(0) >= 0;
            case "replace" -> n == 2 && string && !((String) args.get(0)).isEmpty() && args.get(1) instanceof String;
            case "join", "pluck" -> n == 1 && string;
            case "sort" -> n == 0 || n == 1 && string;
            case "div", "mod" -> n == 1 && integer && (int) args.get(0) != 0;
            case "add", "sub", "mul", "gt", "lt" -> n == 1 && integer;
            default -> n == 0;
        };
    }

    static Expression expression(String text, int line) {
        List<String> pieces = split(text, '|');
        String name = strip(pieces.get(0));
        if (!name.matches(NAME)) throw new Failure(line, "invalid name '" + name + "'");
        List<Filter> filters = new ArrayList<>();
        for (String piece : pieces.subList(1, pieces.size())) {
            List<String> fields = split(strip(piece), ':');
            String filter = fields.get(0);
            if (!FILTERS.contains(filter)) throw new Failure(line, "unknown filter '" + filter + "'");
            List<Object> args = new ArrayList<>();
            boolean valid = true;
            for (String arg : fields.subList(1, fields.size())) {
                if (arg.matches("'[^']*'")) args.add(arg.substring(1, arg.length() - 1));
                else if (arg.matches("-?[0-9]{1,9}")) args.add(Integer.parseInt(arg));
                else valid = false;
            }
            if (!valid || !arguments(filter, args)) throw new Failure(line, "bad arguments for '" + filter + "'");
            filters.add(new Filter(filter, args));
        }
        return new Expression(name, filters);
    }

    static List<Node> analyze(List<Line> source, String indentation) {
        List<Node> result = new ArrayList<>();
        Deque<Node> open = new ArrayDeque<>();
        Deque<List<Node>> levels = new ArrayDeque<>();
        levels.push(result);
        String opening = "{{", closing = "}}";
        for (Line line : source) {
            String text = line.text().isEmpty() ? "" : indentation + line.text();
            List<Node> nodes = new ArrayList<>();
            int pos = 0, tags = 0;
            while (true) {
                int start = text.indexOf(opening, pos);
                if (start < 0) {
                    nodes.add(new Node('T', line.number(), text.substring(pos)));
                    break;
                }
                nodes.add(new Node('T', line.number(), text.substring(pos, start)));
                int begin = start + opening.length();
                boolean triple = begin < text.length() && text.charAt(begin) == '{';
                if (triple) begin++;
                String endText = (triple ? "}" : "") + closing;
                int end = text.indexOf(endText, begin);
                if (end < 0) throw new Failure(line.number(), "unclosed tag");
                String content = strip(text.substring(begin, end));
                char kind = triple ? 'R' : !content.isEmpty() && "#^/!>&=".indexOf(content.charAt(0)) >= 0 ? content.charAt(0) : 'V';
                String arg = kind == 'V' || triple ? content : strip(content.substring(1));
                if (kind == '&') kind = 'R';
                Node node = new Node(kind, line.number(), arg);
                tags++;
                if (kind == '=') {
                    if (content.length() < 2 || !content.endsWith("=")) throw new Failure(line.number(), "invalid delimiters");
                    String middle = strip(content.substring(1, content.length() - 1));
                    String[] pair = middle.split(" +", -1);
                    if (pair.length != 2 || pair[0].isEmpty() || pair[1].isEmpty() || pair[0].contains("=") || pair[1].contains("=")) throw new Failure(line.number(), "invalid delimiters");
                    opening = pair[0];
                    closing = pair[1];
                } else if (kind == 'V' || kind == 'R' || kind == '#' || kind == '^') {
                    node.expression = expression(arg, line.number());
                    if (kind == '#' || kind == '^') open.push(node);
                } else if (kind == '/') {
                    if (!arg.matches(NAME)) throw new Failure(line.number(), "invalid name '" + arg + "'");
                    if (open.isEmpty()) throw new Failure(line.number(), "unexpected closing '" + arg + "'");
                    String expected = open.peek().expression.name();
                    if (!arg.equals(expected)) throw new Failure(line.number(), "mismatched closing '" + arg + "', expected '" + expected + "'");
                    open.pop();
                } else if (kind == '>' && !arg.matches(IDENT)) throw new Failure(line.number(), "invalid name '" + arg + "'");
                nodes.add(node);
                pos = end + endText.length();
            }
            Node only = null;
            boolean spaces = true;
            for (Node node : nodes) {
                if (node.kind == 'T') spaces &= node.text.matches(" *");
                else only = node;
            }
            boolean standalone = tags == 1 && spaces && "#^/!>=".indexOf(only.kind) >= 0;
            if (standalone && only.kind == '>') only.indent = nodes.get(0).text;
            if (!standalone) nodes.add(new Node('T', line.number(), "\n"));
            for (Node node : nodes) {
                if (standalone && node.kind == 'T') continue;
                if (node.kind == '/') levels.pop();
                else {
                    levels.peek().add(node);
                    if (node.kind == '#' || node.kind == '^') levels.push(node.children);
                }
            }
        }
        if (!open.isEmpty()) throw new Failure(open.peek().line, "unclosed section '" + open.peek().expression.name() + "'");
        return result;
    }

    static boolean truth(Object value) {
        if (value == null) return false;
        if (value instanceof Boolean b) return b;
        if (value instanceof Integer n) return n != 0;
        if (value instanceof String s) return !s.isEmpty();
        if (value instanceof List) return !list(value).isEmpty();
        return !map(value).isEmpty();
    }

    static String string(Object value) {
        if (value == null) return "";
        if (value instanceof Map) throw new Failure("cannot render map");
        if (value instanceof List) {
            List<String> parts = new ArrayList<>();
            for (Object item : list(value)) parts.add(string(item));
            return String.join(", ", parts);
        }
        return value.toString();
    }

    static int number(Object value, String filter) {
        if (value == null) return 0;
        if (value instanceof Integer n) return n;
        if (value instanceof String s && s.matches("-?[0-9]{1,9}")) return Integer.parseInt(s);
        throw new Failure("not a number for '" + filter + "'");
    }

    static int rank(Object value) {
        return value == null ? 0 : value instanceof Integer ? 1 : value instanceof String ? 2 : value instanceof Boolean ? 3 : 4;
    }

    static Object sortKey(Object value, List<Object> args) {
        return args.isEmpty() ? value : value instanceof Map ? map(value).get(args.get(0)) : null;
    }

    static int compare(Object left, Object right) {
        int r = Integer.compare(rank(left), rank(right));
        if (r != 0) return r;
        return switch (rank(left)) {
            case 1 -> Integer.compare((int) left, (int) right);
            case 2 -> ((String) left).compareTo((String) right);
            case 3 -> Boolean.compare((boolean) left, (boolean) right);
            default -> 0;
        };
    }

    static Object apply(Object value, Filter filter) {
        String f = filter.name();
        List<Object> a = filter.args();
        switch (f) {
            case "default": return truth(value) ? value : a.get(0);
            case "eq": return string(value).equals(string(a.get(0)));
            case "length": return value instanceof Map ? map(value).size() : value instanceof List ? list(value).size() : string(value).length();
            case "first", "last": return value instanceof List ? list(value).isEmpty() ? null : list(value).get(f.equals("first") ? 0 : list(value).size() - 1) : value;
            case "reverse": if (value instanceof List) {
                List<Object> result = new ArrayList<>(list(value));
                Collections.reverse(result);
                return result;
            }
            return value instanceof String s ? new StringBuilder(s).reverse().toString() : value;
            case "items": if (value instanceof Map) {
                List<Object> result = new ArrayList<>();
                for (String key : new TreeSet<>(map(value).keySet())) {
                    Map<String, Object> item = new TreeMap<>();
                    item.put("key", key);
                    item.put("value", map(value).get(key));
                    result.add(item);
                }
                return result;
            }
            return value;
            case "sort", "pluck": if (!(value instanceof List)) return value;
            List<Object> result = new ArrayList<>();
            if (f.equals("pluck")) for (Object item : list(value)) result.add(sortKey(item, a));
            else {
                result.addAll(list(value));
                result.sort((x, y) -> compare(sortKey(x, a), sortKey(y, a)));
            }
            return result;
            case "sum", "min", "max": if (!(value instanceof List)) return number(value, f);
            Integer total = f.equals("sum") ? 0 : null;
            for (Object item : list(value)) {
                int n = number(item, f);
                total = total == null ? n : f.equals("sum") ? total + n : f.equals("min") ? Math.min(total, n) : Math.max(total, n);
            }
            return total;
            case "add", "sub", "mul", "div", "mod", "gt", "lt": int n = number(value, f), argument = (int) a.get(0);
            return switch (f) {
                case "add" -> n + argument;
                case "sub" -> n - argument;
                case "mul" -> n * argument;
                case "div" -> Math.floorDiv(n, argument);
                case "mod" -> Math.floorMod(n, argument);
                case "gt" -> n > argument;
                default -> n < argument;
            };
            case "comma": String digits = Integer.toString(number(value, f));
            String sign = digits.startsWith("-") ? "-" : "";
            if (!sign.isEmpty()) digits = digits.substring(1);
            StringBuilder comma = new StringBuilder(sign);
            for (int i = 0; i < digits.length(); i++) {
                if (i > 0 && (digits.length() - i) % 3 == 0) comma.append(',');
                comma.append(digits.charAt(i));
            }
            return comma.toString();
            case "join": if (value instanceof List) {
                List<String> parts = new ArrayList<>();
                for (Object item : list(value)) parts.add(string(item));
                return String.join((String) a.get(0), parts);
            }
            return string(value);
        }
        String text = string(value);
        return switch (f) {
            case "upper" -> text.toUpperCase(Locale.ROOT);
            case "lower" -> text.toLowerCase(Locale.ROOT);
            case "title" -> {
                StringBuilder out = new StringBuilder();
                for (int i = 0; i < text.length(); i++) out.append(i == 0 || text.charAt(i - 1) == ' ' ? Character.toUpperCase(text.charAt(i)) : Character.toLowerCase(text.charAt(i)));
                yield out.toString();
            }
            case "trim" -> strip(text);
            case "pad", "lpad" -> {
                int count = Math.max(0, (int) a.get(0) - text.length());
                String padding = (a.size() == 1 ? " " : (String) a.get(1)).repeat(count);
                yield f.equals("pad") ? text + padding : padding + text;
            }
            case "truncate" -> text.length() > (int) a.get(0) ? text.substring(0, (int) a.get(0)) + "..." : text;
            case "replace" -> text.replace((String) a.get(0), (String) a.get(1));
            default -> throw new IllegalStateException();
        };
    }

    static Object indexPart(String part) {
        if (!part.matches(INDEX)) return part;
        try {
            return Integer.valueOf(part);
        } catch (NumberFormatException ex) {
            return -1;
        }
    }
    record Resolved(boolean found, Object value) {} static Resolved resolve(String name, List<Object> contexts, List<int[]> loops) {
        if (name.equals(".")) return new Resolved(true, contexts.getLast());
        if (name.startsWith("@")) {
            if (loops.isEmpty()) return new Resolved(false, null);
            int[] loop = loops.getLast();
            Object value = switch (name) {
                case "@index" -> loop[0];
                case "@number" -> loop[0] + 1;
                case "@first" -> loop[0] == 0;
                default -> loop[0] == loop[1] - 1;
            };
            return new Resolved(true, value);
        }
        String[] parts = name.split("\\.");
        Object value = null;
        boolean found = false;
        for (int i = contexts.size() - 1; i >= 0; i--) if (has(contexts.get(i), indexPart(parts[0]))) {
            value = contexts.get(i);
            found = true;
            break;
        }
        if (!found) return new Resolved(false, null);
        for (String part : parts) {
            Object key = indexPart(part);
            if (!has(value, key)) return new Resolved(false, null);
            value = get(value, key);
        }
        return new Resolved(true, value);
    }

    static String html(String text) {
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;");
    }

    static void render(List<Node> nodes, List<Object> contexts, List<int[]> loops, int depth, StringBuilder out) {
        for (Node node : nodes) {
            try {
                if (node.kind == 'T') {
                    out.append(node.text);
                    continue;
                }
                if (node.kind == '>') {
                    if (!partials.containsKey(node.text)) throw new Failure("unknown partial '" + node.text + "'");
                    if (depth == 8) throw new Failure("partial depth exceeded at '" + node.text + "'");
                    render(analyze(partials.get(node.text), node.indent), contexts, loops, depth + 1, out);
                    continue;
                }
                if (node.expression == null) continue;
                Resolved resolved = resolve(node.expression.name(), contexts, loops);
                if (strict && (node.kind == 'V' || node.kind == 'R') && !resolved.found()) throw new Failure("missing '" + node.expression.name() + "'");
                Object value = resolved.value();
                for (Filter filter : node.expression.filters()) value = apply(value, filter);
                if (node.kind == 'V' || node.kind == 'R') {
                    String text = string(value);
                    out.append(node.kind == 'V' ? html(text) : text);
                } else if (node.kind == '^') {
                    if (!truth(value)) render(node.children, contexts, loops, depth, out);
                } else if (value instanceof List) {
                    List<Object> items = list(value);
                    for (int i = 0; i < items.size(); i++) {
                        contexts.add(items.get(i));
                        loops.add(new int[]{i, items.size()});
                        render(node.children, contexts, loops, depth, out);
                        contexts.removeLast();
                        loops.removeLast();
                    }
                } else if (truth(value)) {
                    contexts.add(value);
                    render(node.children, contexts, loops, depth, out);
                    contexts.removeLast();
                }
            } catch (Failure ex) {
                if (ex.line != 0) throw ex;
                throw new Failure(node.line, ex.getMessage());
            }
        }
    }

    static void renderTemplate(String name, int line) {
        try {
            if (!templates.containsKey(name)) throw new Failure(line, "unknown template '" + name + "'");
            StringBuilder out = new StringBuilder();
            List<Object> contexts = new ArrayList<>();
            contexts.add(root);
            render(analyze(templates.get(name), ""), contexts, new ArrayList<>(), 0, out);
            String result = out.toString();
            int count = result.isEmpty() ? 0 : (int) result.chars().filter(c -> c == '\n').count() + (result.endsWith("\n") ? 0 : 1);
            System.out.println("TEMPLATE " + name + " OK lines=" + count + " chars=" + result.length());
            System.out.print(result);
            if (!result.isEmpty() && !result.endsWith("\n")) System.out.println();
        } catch (Failure ex) {
            System.out.println("TEMPLATE " + name + " ERROR line " + ex.line + ": " + ex.getMessage());
        }
    }

    static void leaves(Object value, String path, List<String> out) {
        if (value instanceof Map && !map(value).isEmpty()) for (String key : new TreeSet<>(map(value).keySet())) leaves(map(value).get(key), path.isEmpty() ? key : path + "." + key, out);
        else if (value instanceof List && !list(value).isEmpty()) for (int i = 0; i < list(value).size(); i++) leaves(list(value).get(i), path + "[" + i + "]", out);
        else {
            String notation = value instanceof String s ? "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"" : value instanceof Map ? "{}" : value instanceof List ? "[]" : string(value);
            out.add(path + " = " + notation);
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int number = 0;
        String command;
        while ((command = input.readLine()) != null) {
            number++;
            if (command.equals("END")) break;
            if (command.equals("DATA") || command.startsWith("PARTIAL ") || command.startsWith("TEMPLATE ")) {
                String type = command.split(" ")[0];
                String name = type.equals("DATA") ? "" : command.substring(type.length() + 1);
                List<Line> body = new ArrayList<>();
                int start = number;
                String text;
                while ((text = input.readLine()) != null) {
                    number++;
                    if (text.equals("END" + type)) break;
                    body.add(new Line(number, text));
                }
                if (type.equals("DATA")) data(body);
                else if (type.equals("TEMPLATE")) {
                    templates.put(name, body);
                    renderTemplate(name, start);
                } else {
                    try {
                        analyze(body, "");
                        boolean existed = partials.containsKey(name);
                        partials.put(name, body);
                        System.out.println("PARTIAL " + name + (existed ? " REPLACED" : " DEFINED") + " lines=" + body.size());
                    } catch (Failure ex) {
                        System.out.println("PARTIAL " + name + " ERROR line " + ex.line + ": " + ex.getMessage());
                    }
                }
            } else if (command.startsWith("RENDER ")) renderTemplate(command.substring(7), number);
            else if (command.equals("DUMP")) {
                List<String> out = new ArrayList<>();
                for (String key : root.keySet()) leaves(root.get(key), key, out);
                System.out.println("DUMP leaves=" + out.size());
                out.forEach(System.out::println);
            } else if (command.equals("RESET")) {
                root = new TreeMap<>();
                partials.clear();
                templates.clear();
                System.out.println(command);
            } else {
                strict = command.equals("STRICT ON");
                System.out.println(command);
            }
        }
    }
}
