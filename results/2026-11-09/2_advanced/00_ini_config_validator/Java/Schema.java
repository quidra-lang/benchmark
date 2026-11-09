import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class Spec {
    final int line;
    final String pattern, key, kind;
    final String[] parts;
    final boolean wildcard;
    final Map<String, String> attributes = new HashMap<>();

    Spec(int line, String[] words) {
        this.line = line;
        pattern = words[0];
        kind = words[1];
        key = Main.keyName(pattern);
        parts = Main.sectionOf(pattern).split("\\.");
        wildcard = List.of(parts).contains("*");
        for (int i = 2; i < words.length; i++) {
            int equals = words[i].indexOf('=');
            attributes.put(equals < 0 ? words[i] : words[i].substring(0, equals), equals < 0 ? "" : words[i].substring(equals + 1));
        }
    }
    boolean has(String name) { return attributes.containsKey(name); }
    String get(String name) { return attributes.get(name); }
    String item() { return attributes.getOrDefault("item", "string"); }
    List<String> values() { return has("values") ? List.of(get("values").split(",", -1)) : List.of(); }
    boolean matches(String section) {
        String[] actual = section.split("\\.");
        if (parts.length != actual.length) return false;
        for (int i = 0; i < parts.length; i++) if (!parts[i].equals("*") && !parts[i].equals(actual[i])) return false;
        return true;
    }
}

final class Schema {
    final List<Spec> specs = new ArrayList<>();
    private final Map<String, Spec> exact = new HashMap<>();

    Schema(Path path) throws IOException {
        List<String> lines = Main.readLines(path);
        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            if (IniParser.trim(line).isEmpty() || line.startsWith("#")) continue;
            Spec spec = new Spec(i + 1, line.split(" "));
            specs.add(spec);
            if (!spec.wildcard) exact.put(spec.pattern, spec);
        }
    }
    Spec find(String key) {
        if (exact.containsKey(key)) return exact.get(key);
        String section = Main.sectionOf(key), name = Main.keyName(key);
        for (Spec spec : specs) if (spec.wildcard && spec.key.equals(name) && spec.matches(section)) return spec;
        return null;
    }
    List<String> targets(Spec spec, Set<String> sections) {
        if (!spec.wildcard) return List.of(spec.pattern);
        List<String> keys = new ArrayList<>();
        for (String section : sections) {
            String key = section + "." + spec.key;
            if (spec.matches(section) && find(key) == spec) keys.add(key);
        }
        keys.sort(Main.KEY_ORDER);
        return keys;
    }
}
