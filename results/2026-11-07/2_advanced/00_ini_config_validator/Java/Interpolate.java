import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class Interpolate {
    private final Map<String, Definition> configuration;
    private final Profile profile;
    private final Map<String, String> results = new HashMap<>();
    private final List<String> stack = new ArrayList<>();
    private final Set<String> cycleKeys = new HashSet<>();

    private Interpolate(Profile profile) { this.profile = profile; configuration = profile.configuration; }
    static Map<String, String> expandAll(Profile profile) {
        Interpolate expander = new Interpolate(profile);
        for (String key : Main.sortedKeys(profile.configuration)) expander.expand(key);
        return expander.results;
    }
    private String expand(String key) {
        if (results.containsKey(key)) return results.get(key);
        stack.add(key);
        String result = evaluate(key);
        stack.removeLast();
        results.put(key, result);
        return result;
    }
    private String evaluate(String key) {
        Definition definition = configuration.get(key);
        String text = definition.value();
        StringBuilder result = new StringBuilder();
        int position = 0;
        while (position < text.length()) {
            if (!text.startsWith("${", position)) {
                char c = text.charAt(position++);
                result.append(c == Lexer.LITERAL_DOLLAR ? '$' : c);
                continue;
            }
            int close = text.indexOf('}', position + 2);
            if (close < 0 || !IniParser.isSection(text.substring(position + 2, close))) {
                profile.report(definition.origin(), "E_BAD_REF", key + ": invalid reference");
                return null;
            }
            String target = text.substring(position + 2, close);
            if (!target.contains(".")) target = Main.sectionOf(key) + "." + target;
            if (!configuration.containsKey(target)) {
                profile.report(definition.origin(), "E_UNDEFINED", key + ": undefined reference " + target);
                return null;
            }
            String expanded = null;
            int cycle = stack.indexOf(target);
            if (cycle >= 0) {
                List<String> path = new ArrayList<>(stack.subList(cycle, stack.size()));
                path.add(target);
                profile.report(configuration.get(target).origin(), "E_CYCLE", "interpolation cycle " + String.join(" -> ", path));
                cycleKeys.addAll(path);
            } else expanded = expand(target);
            if (expanded == null) {
                if (!cycleKeys.contains(key)) profile.report(definition.origin(), "E_DEPENDENCY", key + ": depends on failed key " + target);
                return null;
            }
            result.append(expanded);
            position = close + 1;
        }
        return result.toString();
    }
}
