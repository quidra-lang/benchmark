import java.math.*;
import java.nio.file.*;
import java.util.*;
final class Report {
    static String decimal(double value, int digits) {
        return BigDecimal.valueOf(value).setScale(digits, RoundingMode.HALF_UP).toPlainString();
    }
    static String decimal(double value) { return decimal(value, 3); }
    static String signed(int value) { return value > 0 ? "+" + value : Integer.toString(value); }
    static List<String> chart(List<String> rows) {
        String border = "+"
                        + "-".repeat(rows.getFirst().length()) + "+";
        List<String> lines = new ArrayList<>();
        lines.add(border);
        for (String row : rows)
            lines.add("|" + row + "|");
        lines.add(border);
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"));
    }
}
