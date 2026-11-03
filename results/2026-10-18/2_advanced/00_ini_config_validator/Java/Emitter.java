import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

final class Emitter {
    static final String MASK = "********";

    static String stringNotation(String text) {
        return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t") + "\"";
    }
    static String valueNotation(Value value) {
        return switch (value.kind()) {
            case "string" -> stringNotation(value.text());
            case "int", "size", "duration" -> Long.toString(value.number());
            case "bool" -> Boolean.toString(value.flag());
            case "list" -> "[" + String.join(", ", value.items().stream().map(Emitter::valueNotation).toList()) + "]";
            default -> value.text();
        };
    }
    static String originText(Origin origin) { return origin.document() + ":" + origin.line(); }
    static String shownNotation(String notation, boolean secret) { return secret ? MASK : notation; }
    static String checkedText(String text, boolean secret) { return shownNotation(stringNotation(text), secret); }
    static String shown(OutputKey output) { return shownNotation(output.notation(), output.spec() != null && output.spec().has("secret")); }
    private static String normalized(Profile profile) {
        List<String> lines = new ArrayList<>(List.of("profile " + profile.name));
        String previous = "";
        for (String key : Main.sortedKeys(profile.outputs)) {
            String section = Main.sectionOf(key);
            if (!section.equals(previous)) { lines.add("[" + section + "]"); previous = section; }
            lines.add(Main.keyName(key) + " = " + shown(profile.outputs.get(key)));
        }
        return String.join("\n", lines);
    }
    private static String diagnostics(Profile profile) {
        List<String> lines = new ArrayList<>(List.of("profile " + profile.name + " errors " + profile.errors + " warnings " + profile.warnings));
        for (Diagnostic d : profile.diagnostics) lines.add(originText(d.origin()) + " " + d.code() + " " + d.message());
        return String.join("\n", lines);
    }
    private static String diff(ProfileDiff diff) {
        List<String> lines = new ArrayList<>(List.of("diff " + diff.first() + " -> " + diff.second() + ": " + diff.added()
                + " added, " + diff.removed() + " removed, " + diff.changed() + " changed"));
        for (DiffEntry entry : diff.entries()) {
            lines.add(switch (entry.sign()) {
                case "+" -> "+ " + entry.key() + " = " + shown(entry.after());
                case "-" -> "- " + entry.key() + " = " + shown(entry.before());
                default -> "~ " + entry.key() + ": " + shown(entry.before()) + " -> " + shown(entry.after());
            });
        }
        return String.join("\n", lines);
    }
    private static String report(Profile profile) {
        List<String> lines = new ArrayList<>(List.of("profile " + profile.name, "includes"));
        for (TreeEntry entry : profile.tree) lines.add(" ".repeat(2 + 2 * entry.depth()) + entry.text());
        lines.add("overridden");
        for (String key : profile.overridden) {
            List<String> history = profile.outputs.get(key).definition().history().stream().map(Emitter::originText).toList();
            lines.add("  " + key + ": " + String.join(" -> ", history));
        }
        if (profile.overridden.isEmpty()) lines.add("  (none)");
        lines.add("keys " + profile.outputs.size() + " documents " + profile.documentKeys + " manifest " + profile.manifestKeys + " defaults " + profile.defaultKeys);
        lines.add("dropped " + profile.dropped);
        lines.add("errors " + profile.errors + " warnings " + profile.warnings);
        return String.join("\n", lines);
    }
    private static void write(String name, List<String> blocks) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n\n", blocks) + "\n", StandardCharsets.US_ASCII);
    }
    static void writeOutputs(List<Profile> profiles, List<ProfileDiff> diffs) throws IOException {
        Files.createDirectories(Path.of("output"));
        write("normalized.txt", profiles.stream().map(Emitter::normalized).toList());
        write("diagnostics.txt", profiles.stream().map(Emitter::diagnostics).toList());
        write("report.txt", profiles.stream().map(Emitter::report).toList());
        write("diff.txt", diffs.stream().map(Emitter::diff).toList());
    }
}
