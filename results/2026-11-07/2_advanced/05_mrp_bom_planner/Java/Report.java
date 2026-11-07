import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

final class Report {
    static String money(long cents) { String tail = Long.toString(cents % 100); return cents / 100 + "." + "0".repeat(2 - tail.length()) + tail; }
    static long percent(long part, long whole) { return (200 * part + whole) / (2 * whole); }
    static String table(String label, long[] values, int width) {
        StringBuilder row = new StringBuilder(label).append(" ".repeat(Math.max(0, 10 - label.length())));
        for (long value : values) { String text = Long.toString(value); row.append(" ".repeat(Math.max(0, width - text.length()))).append(text); } return row.toString();
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.createDirectories(Path.of("output")); StringBuilder text = new StringBuilder(); for (String line : lines) text.append(line).append('\n'); Files.writeString(Path.of("output", name), text, StandardCharsets.US_ASCII);
    }
}
