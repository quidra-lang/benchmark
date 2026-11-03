import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

record Statement(String kind, int line, String target, String value) {}
record Document(List<Statement> statements, List<Diagnostic> diagnostics) {}

final class IniParser {
    private static final Pattern NAME = Pattern.compile("[a-z][a-z0-9_]*");
    private static final Pattern SECTION = Pattern.compile("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*");
    private final String name;
    private String section = "", base = "";
    private final List<Statement> statements = new ArrayList<>();
    private final List<Diagnostic> diagnostics = new ArrayList<>();
    private final Map<String, Integer> assigned = new HashMap<>();

    private IniParser(String name) { this.name = name; }
    static boolean isSection(String text) { return SECTION.matcher(text).matches(); }
    static String trim(String text) { return text.replaceFirst("^ +", "").replaceFirst(" +\\z", ""); }
    private static List<String> trimmed(List<String> source) {
        List<String> segments = new ArrayList<>(source);
        segments.set(0, segments.getFirst().replaceFirst("^ +", ""));
        int last = segments.size() - 1;
        segments.set(last, segments.get(last).replaceFirst(" +\\z", ""));
        return segments;
    }
    private void report(int line, String code, String message) {
        diagnostics.add(new Diagnostic(new Origin(name, line), code, message));
    }
    private void add(String kind, int line, String target, String value) {
        statements.add(new Statement(kind, line, target, value));
    }
    static Document parse(String name, List<String> physical) {
        IniParser parser = new IniParser(name);
        for (LogicalLine line : Lexer.lines(physical)) parser.interpret(line);
        return new Document(parser.statements, parser.diagnostics);
    }
    private void interpret(LogicalLine line) {
        if (!line.code().isEmpty()) { report(line.number(), line.code(), line.message()); return; }
        List<String> segments = trimmed(line.segments());
        String first = segments.getFirst();
        if (segments.size() == 1 && first.isEmpty()) return;
        if (first.startsWith("[")) header(line.number(), segments);
        else if (first.startsWith("@")) directive(line.number(), segments);
        else assignment(line.number(), segments);
    }
    private void header(int line, List<String> segments) {
        String text = segments.getFirst();
        String inside = text.length() >= 2 ? text.substring(1, text.length() - 1) : "";
        int colon = inside.indexOf(':');
        String child = trim(colon < 0 ? inside : inside.substring(0, colon));
        String parent = colon < 0 ? "" : trim(inside.substring(colon + 1));
        boolean relative = child.startsWith(".") && isSection(child.substring(1));
        String error = "";
        if (segments.size() != 1 || !text.endsWith("]") || (colon >= 0 && !isSection(parent))
                || (!relative && !isSection(child))) error = "invalid section header";
        else if (relative && base.isEmpty()) error = "relative section without base";
        if (!error.isEmpty()) {
            report(line, "E_SECTION", error);
            section = "";
            return;
        }
        if (relative) section = base + child;
        else { section = child; base = child; }
        if (colon >= 0) add("inherit", line, section, parent);
    }
    private void directive(int line, List<String> segments) {
        String[] words = segments.getFirst().split(" +");
        if (segments.size() != 1 || words.length != 2 || (!words[0].equals("@include") && !words[0].equals("@unset"))
                || !NAME.matcher(words[1]).matches()) report(line, "E_SYNTAX", "invalid directive");
        else if (words[0].equals("@include")) add("include", line, words[1], "");
        else if (section.isEmpty()) report(line, "E_NO_SECTION", "no current section");
        else add("unset", line, section + "." + words[1], "");
    }
    private void assignment(int line, List<String> segments) {
        boolean hasEquals = false;
        for (int i = 0; i < segments.size(); i += 2) hasEquals |= segments.get(i).contains("=");
        if (!hasEquals) { report(line, "E_SYNTAX", "invalid line"); return; }
        int equals = segments.getFirst().indexOf('=');
        if (equals < 0) { report(line, "E_SYNTAX", "invalid key"); return; }
        String key = trim(segments.getFirst().substring(0, equals));
        boolean append = key.endsWith("+");
        if (append) key = trim(key.substring(0, key.length() - 1));
        if (!NAME.matcher(key).matches()) { report(line, "E_SYNTAX", "invalid key"); return; }
        segments.set(0, segments.getFirst().substring(equals + 1));
        segments = trimmed(segments);
        String value;
        if (segments.size() == 1) value = segments.getFirst();
        else if (segments.size() == 3 && segments.getFirst().isEmpty() && segments.getLast().isEmpty()) value = segments.get(1);
        else { report(line, "E_SYNTAX", "invalid value"); return; }
        if (section.isEmpty()) { report(line, "E_NO_SECTION", "no current section"); return; }
        String fullKey = section + "." + key;
        if (!append) {
            Integer previous = assigned.put(fullKey, line);
            if (previous != null) report(line, "W_DUPLICATE", fullKey + " already set at line " + previous);
        }
        add(append ? "append" : "assign", line, fullKey, value);
    }
}
