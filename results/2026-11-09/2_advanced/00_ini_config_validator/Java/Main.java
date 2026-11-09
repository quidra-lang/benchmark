import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

record Origin(String document, int line) {}
record Diagnostic(Origin origin, String code, String message) {}
record Definition(String value, Origin origin, long number, List<Origin> history) {}
record Value(String kind, String text, long number, boolean flag, List<Value> items) {
    static Value text(String kind, String text) { return new Value(kind, text, 0, false, List.of()); }
    static Value number(String kind, long number) { return new Value(kind, "", number, false, List.of()); }
    static Value flag(boolean flag) { return new Value("bool", "", 0, flag, List.of()); }
    static Value list(List<Value> items) { return new Value("list", "", 0, false, items); }
}
record OutputKey(Definition definition, Spec spec, Value value, String notation) {}
record Parent(String section, Origin origin) {}
record TreeEntry(int depth, String text) {}
record DiffEntry(String sign, String key, OutputKey before, OutputKey after) {}
record ProfileDiff(String first, String second, int added, int removed, int changed, List<DiffEntry> entries) {}
final class CheckError extends Exception {
    final String code;
    CheckError(String code, String message) { super(message); this.code = code; }
}

public final class Main {
    static final Comparator<String> KEY_ORDER = Comparator.comparing(Main::sectionOf).thenComparing(Main::keyName);
    private static final Pattern INTEGER = Pattern.compile("([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))");
    private static final Pattern SIZE = Pattern.compile("([0-9]{1,6})(?:\\.([0-9]{1,3}))?([A-Za-z]*)");
    private static final Pattern SECONDS = Pattern.compile("[0-9]{1,6}");
    private static final Pattern DURATION = Pattern.compile("(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?");
    private static final Pattern IP_CHARACTERS = Pattern.compile("[0-9.]*");
    private static final Pattern IP_PART = Pattern.compile("0|[1-9][0-9]{0,2}");
    private static final Pattern HOST_LABEL = Pattern.compile("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?");
    private static final Pattern SCHEME = Pattern.compile("[A-Za-z][A-Za-z0-9+.-]*");
    private static final Pattern PORT = Pattern.compile("[1-9][0-9]{0,4}");
    private static final Pattern DATE = Pattern.compile("[0-9]{4}-[0-9]{2}-[0-9]{2}");
    private static final Map<String, Long> SIZE_FACTORS = Map.of("", 1L, "b", 1L, "kb", 1024L, "mb", 1048576L, "gb", 1073741824L);

    static List<String> readLines(Path path) throws IOException { return Files.readAllLines(path, StandardCharsets.US_ASCII); }
    static String sectionOf(String key) { return key.substring(0, key.lastIndexOf('.')); }
    static String keyName(String key) { return key.substring(key.lastIndexOf('.') + 1); }
    static List<String> sortedKeys(Map<String, ?> map) { return map.keySet().stream().sorted(KEY_ORDER).toList(); }
    private static long number(String digits) { return digits == null ? 0 : Long.parseLong(digits); }

    static Value scalar(String kind, String text, List<String> values) {
        switch (kind) {
            case "string": return Value.text(kind, text);
            case "int": {
                Matcher match = INTEGER.matcher(text);
                if (!match.matches()) return null;
                long value;
                if (match.group(2) != null) value = Long.parseLong(match.group(2), 16);
                else {
                    String digits = match.group(3).replace("_", "");
                    if (digits.length() > 12) return null;
                    value = number(digits);
                }
                return Value.number(kind, match.group(1).equals("-") ? -value : value);
            }
            case "bool":
                return switch (text.toLowerCase(java.util.Locale.ROOT)) {
                    case "true", "yes", "on", "1" -> Value.flag(true);
                    case "false", "no", "off", "0" -> Value.flag(false);
                    default -> null;
                };
            case "enum":
                for (String entry : values) if (text.equalsIgnoreCase(entry)) return Value.text(kind, entry);
                return null;
            case "size": {
                Matcher match = SIZE.matcher(text);
                if (!match.matches()) return null;
                Long factor = SIZE_FACTORS.get(match.group(3).toLowerCase(java.util.Locale.ROOT));
                if (factor == null) return null;
                long value = number(match.group(1)) * factor;
                String fraction = match.group(2);
                if (fraction != null) {
                    long divisor = 1;
                    for (int i = 0; i < fraction.length(); i++) divisor *= 10;
                    long scaled = number(fraction) * factor;
                    if (scaled % divisor != 0) return null;
                    value += scaled / divisor;
                }
                return Value.number(kind, value);
            }
            case "duration": {
                if (SECONDS.matcher(text).matches()) return Value.number(kind, number(text));
                Matcher match = DURATION.matcher(text);
                if (text.isEmpty() || !match.matches()) return null;
                return Value.number(kind, number(match.group(1)) * 3600 + number(match.group(2)) * 60 + number(match.group(3)));
            }
            case "host": {
                String[] parts = text.split("\\.", -1);
                if (IP_CHARACTERS.matcher(text).matches()) {
                    if (parts.length != 4) return null;
                    for (String part : parts) if (!IP_PART.matcher(part).matches() || number(part) > 255) return null;
                    return Value.text(kind, text);
                }
                if (text.length() > 253) return null;
                for (String part : parts) if (!HOST_LABEL.matcher(part).matches()) return null;
                return Value.text(kind, text.toLowerCase(java.util.Locale.ROOT));
            }
            case "path": {
                if (text.isEmpty() || text.indexOf(' ') >= 0 || text.indexOf('\n') >= 0 || text.indexOf('\t') >= 0) return null;
                boolean absolute = text.startsWith("/");
                List<String> parts = new ArrayList<>();
                for (String part : text.split("/", -1)) {
                    if (part.isEmpty() || part.equals(".")) continue;
                    if (!part.equals("..")) parts.add(part);
                    else if (!parts.isEmpty() && !parts.getLast().equals("..")) parts.removeLast();
                    else if (absolute) return null;
                    else parts.add(part);
                }
                String path = String.join("/", parts);
                return Value.text(kind, absolute ? "/" + path : path.isEmpty() ? "." : path);
            }
            case "url": {
                int delimiter = text.indexOf("://");
                if (delimiter < 0) return null;
                String scheme = text.substring(0, delimiter);
                String rest = text.substring(delimiter + 3);
                if (!SCHEME.matcher(scheme).matches() || rest.contains("?") || rest.contains("#")) return null;
                int slash = rest.indexOf('/');
                String authority = slash < 0 ? rest : rest.substring(0, slash);
                String path = slash < 0 ? "" : rest.substring(slash + 1);
                int colon = authority.indexOf(':');
                String host = colon < 0 ? authority : authority.substring(0, colon);
                String port = colon < 0 ? "" : authority.substring(colon + 1);
                Value hostValue = scalar("host", host, List.of()), pathValue = scalar("path", "/" + path, List.of());
                if (hostValue == null || pathValue == null) return null;
                scheme = scheme.toLowerCase(java.util.Locale.ROOT);
                String result = scheme + "://" + hostValue.text();
                if (colon >= 0) {
                    if (!PORT.matcher(port).matches() || number(port) > 65535) return null;
                    long defaultPort = scheme.equals("http") ? 80 : scheme.equals("https") ? 443 : -1;
                    if (number(port) != defaultPort) result += ":" + port;
                }
                return Value.text(kind, result + pathValue.text());
            }
            case "date": {
                if (!DATE.matcher(text).matches()) return null;
                int year = Integer.parseInt(text.substring(0, 4)), month = Integer.parseInt(text.substring(5, 7)), day = Integer.parseInt(text.substring(8));
                if (year < 1 || month < 1 || month > 12) return null;
                int[] days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
                if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) days[1] = 29;
                return day >= 1 && day <= days[month - 1] ? Value.text(kind, text) : null;
            }
            default: throw new IllegalArgumentException(kind);
        }
    }

    static ProfileDiff differences(Profile first, Profile second) {
        Set<String> keys = new HashSet<>(first.outputs.keySet());
        keys.addAll(second.outputs.keySet());
        List<DiffEntry> entries = new ArrayList<>();
        int added = 0, removed = 0, changed = 0;
        for (String key : keys.stream().sorted(KEY_ORDER).toList()) {
            OutputKey before = first.outputs.get(key), after = second.outputs.get(key);
            String sign = "";
            if (before == null) { sign = "+"; added++; }
            else if (after == null) { sign = "-"; removed++; }
            else if (!before.notation().equals(after.notation())) { sign = "~"; changed++; }
            if (!sign.isEmpty()) entries.add(new DiffEntry(sign, key, before, after));
        }
        return new ProfileDiff(first.name, second.name, added, removed, changed, entries);
    }

    public static void main(String[] args) throws IOException {
        Schema schema = new Schema(Path.of("input/schema.txt"));
        DocumentLibrary library = new DocumentLibrary();
        List<Profile> profiles = new ArrayList<>();
        List<String> manifest = readLines(Path.of("input/manifest.txt"));
        for (int i = 0; i < manifest.size(); i++) {
            String[] words = manifest.get(i).split(" ");
            Profile profile = new Profile(words[0], words[1]);
            profile.apply(library, profile.root, List.of(profile.root));
            for (int j = 2; j < words.length; j++) {
                int equals = words[j].indexOf('=');
                profile.define(words[j].substring(0, equals), words[j].substring(equals + 1), new Origin("manifest", i + 1));
            }
            profile.inheritSections();
            profile.resolveAliases(schema);
            Set<String> sections = profile.fillDefaults(schema);
            profile.validate(schema);
            profile.checkOrder();
            profile.checkRequired(schema, sections);
            profile.checkFixed(profiles);
            profile.finish();
            profiles.add(profile);
        }
        List<ProfileDiff> diffs = new ArrayList<>();
        for (int i = 1; i < profiles.size(); i++) diffs.add(differences(profiles.get(i - 1), profiles.get(i)));
        Emitter.writeOutputs(profiles, diffs);
    }
}

final class DocumentLibrary {
    private final Map<String, Document> cache = new HashMap<>();
    Document find(String name) throws IOException {
        if (!cache.containsKey(name)) {
            Path path = Path.of("input/conf", name + ".ini");
            cache.put(name, Files.exists(path) ? IniParser.parse(name, Main.readLines(path)) : null);
        }
        return cache.get(name);
    }
}

final class Profile {
    final String name, root;
    final Map<String, Definition> configuration = new HashMap<>();
    private final Map<String, Parent> parents = new LinkedHashMap<>();
    final List<TreeEntry> tree = new ArrayList<>();
    private final Set<Diagnostic> reported = new HashSet<>();
    final Map<String, OutputKey> outputs = new HashMap<>();
    private long definitionCount;
    List<Diagnostic> diagnostics;
    final List<String> overridden = new ArrayList<>();
    int errors, warnings, documentKeys, manifestKeys, defaultKeys, dropped;

    Profile(String name, String root) { this.name = name; this.root = root; }
    void report(Origin origin, String code, String message) { reported.add(new Diagnostic(origin, code, message)); }
    void define(String key, String value, Origin origin) {
        Definition previous = configuration.get(key);
        List<Origin> history = previous == null ? new ArrayList<>() : new ArrayList<>(previous.history());
        if (history.isEmpty() || !history.getLast().equals(origin)) history.add(origin);
        configuration.put(key, new Definition(value, origin, ++definitionCount, List.copyOf(history)));
    }
    void apply(DocumentLibrary library, String documentName, List<String> chain) throws IOException {
        Document document = library.find(documentName);
        tree.add(new TreeEntry(chain.size() - 1, documentName));
        reported.addAll(document.diagnostics());
        for (Statement statement : document.statements()) {
            Origin origin = new Origin(documentName, statement.line());
            String key = statement.target(), value = statement.value();
            switch (statement.kind()) {
                case "assign" -> define(key, value, origin);
                case "append" -> {
                    Definition previous = configuration.get(key);
                    define(key, previous != null && !previous.value().isEmpty() ? previous.value() + "," + value : value, origin);
                }
                case "unset" -> { if (configuration.remove(key) == null) report(origin, "W_UNSET", key + " is not set"); }
                case "inherit" -> parents.put(key, new Parent(value, origin));
                case "include" -> {
                    int index = chain.indexOf(key);
                    if (index >= 0) {
                        List<String> path = new ArrayList<>(chain.subList(index, chain.size()));
                        path.add(key);
                        report(origin, "E_INCLUDE_CYCLE", "include cycle " + String.join(" -> ", path));
                        tree.add(new TreeEntry(chain.size(), key + " (cycle)"));
                    } else if (library.find(key) == null) {
                        report(origin, "E_INCLUDE_MISSING", "missing document " + key);
                        tree.add(new TreeEntry(chain.size(), key + " (missing)"));
                    } else {
                        List<String> next = new ArrayList<>(chain);
                        next.add(key);
                        apply(library, key, next);
                    }
                }
            }
        }
    }
    void inheritSections() {
        Map<String, Map<String, Definition>> own = new HashMap<>();
        for (Map.Entry<String, Definition> entry : configuration.entrySet())
            own.computeIfAbsent(Main.sectionOf(entry.getKey()), ignored -> new HashMap<>()).put(Main.keyName(entry.getKey()), entry.getValue());
        for (Map.Entry<String, Parent> entry : parents.entrySet()) {
            String section = entry.getKey();
            Parent declaration = entry.getValue();
            List<String> chain = new ArrayList<>(List.of(section));
            while (parents.containsKey(chain.getLast())) {
                String parent = parents.get(chain.getLast()).section();
                if (chain.contains(parent)) break;
                chain.add(parent);
            }
            if (parents.containsKey(chain.getLast())) {
                chain.add(parents.get(chain.getLast()).section());
                report(declaration.origin(), "E_INHERIT_CYCLE", "inheritance cycle " + String.join(" -> ", chain));
                continue;
            }
            if (!parents.containsKey(declaration.section()) && !own.containsKey(declaration.section()))
                report(declaration.origin(), "W_PARENT_EMPTY", "section " + section + " inherits from empty section " + declaration.section());
            for (String ancestor : chain.subList(1, chain.size())) {
                for (Map.Entry<String, Definition> inherited : own.getOrDefault(ancestor, Map.of()).entrySet())
                    configuration.putIfAbsent(section + "." + inherited.getKey(), inherited.getValue());
            }
        }
    }
    void resolveAliases(Schema schema) {
        for (Spec spec : schema.specs) {
            if (!spec.has("alias")) continue;
            List<String> aliases = List.of(spec.get("alias").split(","));
            if (aliases.stream().noneMatch(configuration::containsKey)) continue;
            List<String> candidates = new ArrayList<>();
            if (configuration.containsKey(spec.pattern)) candidates.add(spec.pattern);
            for (String alias : aliases) if (configuration.containsKey(alias)) candidates.add(alias);
            String winner = candidates.getFirst();
            for (String key : candidates) if (configuration.get(key).number() > configuration.get(winner).number()) winner = key;
            Definition chosen = configuration.get(winner);
            for (String key : candidates) {
                Origin origin = configuration.get(key).origin();
                if (!key.equals(spec.pattern)) report(origin, "W_DEPRECATED", key + " is deprecated, use " + spec.pattern);
                if (!key.equals(winner)) report(origin, "W_SHADOWED", key + " is superseded by " + winner + " at " + Emitter.originText(chosen.origin()));
            }
            configuration.put(spec.pattern, chosen);
            for (String alias : aliases) configuration.remove(alias);
        }
    }
    Set<String> fillDefaults(Schema schema) {
        Set<String> sections = new HashSet<>();
        for (String key : configuration.keySet()) sections.add(Main.sectionOf(key));
        for (Spec spec : schema.specs) if (spec.has("default")) {
            for (String key : schema.targets(spec, sections)) if (!configuration.containsKey(key))
                define(key, spec.get("default"), new Origin("schema", spec.line));
        }
        return sections;
    }
    private CheckError typeError(String key, String kind, String text, Spec spec, boolean item) {
        String display = (item ? "item " : "") + Emitter.checkedText(text, spec.has("secret"));
        return kind.equals("enum") ? new CheckError("E_ENUM", key + ": " + display + " is not one of " + spec.get("values"))
                : new CheckError("E_TYPE", key + ": " + display + " is not a valid " + kind);
    }
    private Value normalize(String key, String text, Spec spec, Origin origin) throws CheckError {
        Value value;
        if (spec.kind.equals("list")) {
            List<Value> items = new ArrayList<>();
            if (!IniParser.trim(text).isEmpty()) {
                List<String> parts = java.util.Arrays.stream(text.split(",", -1)).map(IniParser::trim).toList();
                if (parts.contains("")) report(origin, "W_EMPTY_ITEM", key + ": empty list item ignored");
                for (String part : parts) {
                    if (part.isEmpty()) continue;
                    Value item = Main.scalar(spec.item(), part, spec.values());
                    if (item == null) throw typeError(key, spec.item(), part, spec, true);
                    items.add(item);
                }
            }
            if (spec.has("unique")) {
                Set<String> seen = new HashSet<>();
                List<Value> unique = new ArrayList<>();
                for (Value item : items) if (seen.add(Emitter.valueNotation(item))) unique.add(item);
                if (unique.size() < items.size()) report(origin, "W_DUPLICATE_ITEM", key + ": duplicate items removed");
                items = unique;
            }
            value = Value.list(items);
        } else {
            value = Main.scalar(spec.kind, text, spec.values());
            if (value == null) throw typeError(key, spec.kind, text, spec, false);
        }
        if (spec.has("range")) checkRange(key, value, spec);
        return value;
    }
    private void checkRange(String key, Value value, Spec spec) throws CheckError {
        String[] bounds = spec.get("range").split("\\.\\.", -1);
        boolean count = spec.kind.equals("string") || spec.kind.equals("list");
        long measure = spec.kind.equals("string") ? value.text().length() : spec.kind.equals("list") ? value.items().size() : value.number();
        String display = count ? (spec.kind.equals("string") ? "length " : "count ") + measure
                : Emitter.shownNotation(Emitter.valueNotation(value), spec.has("secret"));
        boolean outside = false;
        for (int i = 0; i < bounds.length; i++) {
            if (bounds[i].isEmpty()) continue;
            if (spec.kind.equals("date")) {
                int comparison = value.text().compareTo(bounds[i]);
                outside |= i == 0 ? comparison < 0 : comparison > 0;
            } else {
                long bound = count ? Long.parseLong(bounds[i]) : Main.scalar(spec.kind, bounds[i], List.of()).number();
                outside |= i == 0 ? measure < bound : measure > bound;
                bounds[i] = Long.toString(bound);
            }
        }
        if (outside) throw new CheckError("E_RANGE", key + ": " + display + " is out of range " + String.join("..", bounds));
    }
    void validate(Schema schema) {
        Map<String, String> expanded = Interpolate.expandAll(this);
        for (String key : Main.sortedKeys(configuration)) {
            String text = expanded.get(key);
            if (text == null) continue;
            Definition definition = configuration.get(key);
            Spec spec = schema.find(key);
            Value value;
            if (spec == null) {
                report(definition.origin(), "W_UNKNOWN", key + " is not in the schema");
                value = Value.text("string", text);
            } else {
                try { value = normalize(key, text, spec, definition.origin()); }
                catch (CheckError error) { report(definition.origin(), error.code, error.getMessage()); continue; }
            }
            outputs.put(key, new OutputKey(definition, spec, value, Emitter.valueNotation(value)));
        }
    }
    void checkOrder() {
        List<String> removed = new ArrayList<>();
        for (String key : Main.sortedKeys(outputs)) {
            OutputKey output = outputs.get(key);
            if (output.spec() == null || !output.spec().has("le")) continue;
            String limitKey = Main.sectionOf(key) + "." + output.spec().get("le");
            OutputKey limit = outputs.get(limitKey);
            if (limit != null && List.of("int", "size", "duration").contains(limit.value().kind()) && output.value().number() > limit.value().number()) {
                report(output.definition().origin(), "E_ORDER", key + ": " + Emitter.shown(output) + " is greater than " + limitKey + " (" + Emitter.shown(limit) + ")");
                removed.add(key);
            }
        }
        for (String key : removed) outputs.remove(key);
    }
    void checkRequired(Schema schema, Set<String> sections) {
        for (Spec spec : schema.specs) if (spec.has("required")) {
            for (String key : schema.targets(spec, sections)) {
                if (configuration.containsKey(key)) continue;
                String message = key + " is required";
                if (spec.has("when")) {
                    String conditionKey = Main.sectionOf(key) + "." + spec.get("when");
                    OutputKey condition = outputs.get(conditionKey);
                    if (condition == null || !condition.value().kind().equals("bool") || !condition.value().flag()) continue;
                    message += " when " + conditionKey + " is true";
                }
                report(new Origin(root, 0), "E_REQUIRED", message);
            }
        }
    }
    void checkFixed(List<Profile> earlier) {
        for (String key : Main.sortedKeys(outputs)) {
            OutputKey output = outputs.get(key);
            if (output.spec() == null || !output.spec().has("fixed")) continue;
            for (Profile reference : earlier) {
                OutputKey before = reference.outputs.get(key);
                if (before == null) continue;
                if (!before.notation().equals(output.notation())) {
                    report(output.definition().origin(), "E_FIXED", key + ": value differs from profile " + reference.name);
                    outputs.remove(key);
                }
                break;
            }
        }
    }
    void finish() {
        diagnostics = reported.stream().sorted(Comparator.comparing((Diagnostic d) -> d.origin().document())
                .thenComparingInt(d -> d.origin().line()).thenComparing(Diagnostic::code).thenComparing(Diagnostic::message)).toList();
        errors = (int) diagnostics.stream().filter(d -> d.code().startsWith("E_")).count();
        warnings = diagnostics.size() - errors;
        for (String key : Main.sortedKeys(outputs)) {
            Definition definition = outputs.get(key).definition();
            if (definition.history().size() >= 2) overridden.add(key);
            switch (definition.origin().document()) {
                case "manifest" -> manifestKeys++;
                case "schema" -> defaultKeys++;
                default -> documentKeys++;
            }
        }
        dropped = configuration.size() - outputs.size();
    }
}
