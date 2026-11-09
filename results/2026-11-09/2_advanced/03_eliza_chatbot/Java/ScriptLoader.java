import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

record Diagnostic(int line, String code, String message) {}
record Substitution(String source, List<String> replacement, int line) {}
record Group(String name, Set<String> members, int line) {}
record Item(String kind, String text, List<String> arguments, int line, int index) {}
final class Rule {
    final String kind;
    final List<String> pattern;
    final int line, index;
    final List<Item> items = new ArrayList<>();
    Rule(String kind, List<String> pattern, int line, int index) { this.kind = kind; this.pattern = pattern; this.line = line; this.index = index; }
}
final class Keyword {
    final String word;
    final int rank, line, index;
    final List<Rule> memories = new ArrayList<>(), decomps = new ArrayList<>();
    Keyword(String word, int rank, int line, int index) { this.word = word; this.rank = rank; this.line = line; this.index = index; }
}
final class Script {
    List<String> lines = new ArrayList<>();
    final Map<String, List<String>> texts = new LinkedHashMap<>();
    final Set<String> quit = new HashSet<>(), stop = new HashSet<>(), persist = new HashSet<>();
    int capacity = 3;
    final List<Substitution> pres = new ArrayList<>(), posts = new ArrayList<>();
    final Map<String, List<String>> pre = new LinkedHashMap<>(), post = new LinkedHashMap<>();
    final List<Group> groupList = new ArrayList<>();
    final Map<String, Set<String>> groups = new LinkedHashMap<>();
    final List<Keyword> keywords = new ArrayList<>();
    final Map<String, Keyword> keywordMap = new LinkedHashMap<>();
    final List<Rule> rules = new ArrayList<>();
    final List<Item> items = new ArrayList<>();
    final List<Diagnostic> diagnostics = new ArrayList<>();
}
final class ScriptLoader {
    private static final Set<String> GLOBALS = Set.of("INITIAL", "FINAL", "QUIT", "STOP", "DEFAULT", "QUESTION", "REPEAT", "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON");
    private static final Set<String> TEXTS = Set.of("INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT");
    private static final Set<String> ITEMS = Set.of("REASM", "GOTO", "NEWKEY", "RESTATE");
    static boolean word(String text) {
        return !text.isEmpty() && text.charAt(0) != '\'' && text.charAt(text.length() - 1) != '\'' && text.chars().allMatch(c -> c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '\'');
    }
    static boolean reference(String text) { return text.length() == 3 && text.charAt(0) == '(' && text.charAt(1) >= '0' && text.charAt(1) <= '9' && text.charAt(2) == ')'; }
    private static boolean number(String text) { return !text.isEmpty() && text.length() <= 2 && text.chars().allMatch(c -> c >= '0' && c <= '9'); }
    private static boolean element(String text) { return text.equals("*") || text.equals("#") || (text.charAt(0) == '@' ? word(text.substring(1)) : word(text)); }
    private static boolean formed(String name, List<String> a) {
        int n = a.size();
        return switch (name) {
            case "INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT", "REASM" -> n >= 1;
            case "QUIT", "STOP" -> n >= 1 && a.stream().allMatch(ScriptLoader::word);
            case "MEMSIZE" -> n == 1 && number(a.getFirst()) && Integer.parseInt(a.getFirst()) >= 1 && Integer.parseInt(a.getFirst()) <= 20;
            case "PERSIST" -> n == 1 && Set.of("cycles", "memory").contains(a.getFirst());
            case "PRE", "SYNON" -> n >= 2 && a.stream().allMatch(ScriptLoader::word);
            case "POST" -> n >= 2 && word(a.getFirst());
            case "KEY" -> n == 2 && word(a.getFirst()) && number(a.get(1));
            case "DECOMP", "MEMORY" -> n >= 1 && a.stream().allMatch(ScriptLoader::element);
            case "GOTO" -> n == 1 && word(a.getFirst());
            case "NEWKEY" -> n == 0;
            case "RESTATE" -> n >= 2 && word(a.getFirst()) && a.subList(1, n).stream().allMatch(s -> word(s) || reference(s));
            default -> false;
        };
    }
    static Script load(String path) throws IOException {
        Script s = new Script(); s.lines = Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
        for (String name : TEXTS) s.texts.put(name, new ArrayList<>());
        Map<String, Integer> first = new LinkedHashMap<>();
        Keyword keyword = null; Rule rule = null; boolean ignoring = false;
        for (int index = 0; index < s.lines.size(); index++) {
            String line = s.lines.get(index);
            if (line.isEmpty() || line.charAt(0) == '#') continue;
            int number = index + 1, space = line.indexOf(' ');
            String name = space < 0 ? line : line.substring(0, space), text = space < 0 ? "" : line.substring(space + 1);
            List<String> a = Helpers.words(text);
            boolean isRule = name.equals("DECOMP") || name.equals("MEMORY"), isItem = ITEMS.contains(name);
            if (GLOBALS.contains(name) || name.equals("KEY")) { keyword = null; rule = null; ignoring = false; }
            else if (isRule || isItem) { if (ignoring) continue; if (isRule) rule = null; }
            String definition = "";
            if (name.equals("MEMSIZE")) definition = name;
            else if (!a.isEmpty() && Set.of("KEY", "SYNON", "PRE", "POST", "PERSIST").contains(name)) definition = name + " " + a.getFirst();
            String code = "", message = "";
            if (!GLOBALS.contains(name) && !name.equals("KEY") && !isRule && !isItem) { code = "SYNTAX"; message = "unknown directive " + name; }
            else if (!formed(name, a)) { code = "SYNTAX"; message = "bad arguments for " + name; }
            else if (isRule && keyword == null) { code = "ORPHAN"; message = name + " without KEY"; }
            else if (name.equals("REASM") && rule == null) { code = "ORPHAN"; message = "REASM without DECOMP or MEMORY"; }
            else if (isItem && !name.equals("REASM") && (rule == null || rule.kind.equals("MEMORY"))) { code = "ORPHAN"; message = name + " without DECOMP"; }
            else if (!definition.isEmpty() && first.containsKey(definition)) { code = "DUPLICATE"; message = definition + " first defined at line " + first.get(definition); }
            if (!code.isEmpty()) { s.diagnostics.add(new Diagnostic(number, code, message)); if (code.equals("DUPLICATE") && name.equals("KEY")) ignoring = true; continue; }
            if (!definition.isEmpty()) first.put(definition, number);
            if (TEXTS.contains(name)) s.texts.get(name).add(text);
            else if (name.equals("QUIT") || name.equals("STOP")) (name.equals("QUIT") ? s.quit : s.stop).addAll(a);
            else if (name.equals("MEMSIZE")) s.capacity = Integer.parseInt(a.getFirst());
            else if (name.equals("PERSIST")) s.persist.add(a.getFirst());
            else if (name.equals("PRE") || name.equals("POST")) {
                List<String> replacement = new ArrayList<>(a.subList(1, a.size()));
                (name.equals("PRE") ? s.pres : s.posts).add(new Substitution(a.getFirst(), replacement, number));
                (name.equals("PRE") ? s.pre : s.post).put(a.getFirst(), replacement);
            } else if (name.equals("SYNON")) {
                Set<String> members = new HashSet<>(a); s.groupList.add(new Group(a.getFirst(), members, number)); s.groups.put(a.getFirst(), members);
            } else if (name.equals("KEY")) {
                keyword = new Keyword(a.getFirst(), Integer.parseInt(a.get(1)), number, s.keywords.size()); s.keywords.add(keyword); s.keywordMap.put(keyword.word, keyword);
            } else if (isRule) {
                rule = new Rule(name, a, number, s.rules.size()); s.rules.add(rule); (name.equals("MEMORY") ? keyword.memories : keyword.decomps).add(rule);
            } else {
                Item item = new Item(name, text, a, number, s.items.size()); s.items.add(item); rule.items.add(item);
            }
        }
        return s;
    }
}
