import java.nio.file.*;
import java.util.*;

final class Report {
    static String decimal(int p, int q) {
        int n = (2 * p * 10000 + q) / (2 * q);
        return n / 10000 + "." + String.format(Locale.ROOT, "%04d", n % 10000);
    }
    static String percentage(int p, int q) {
        if (q == 0)
            return "-";
        int n = (2 * p * 10000 + q) / (2 * q);
        return n / 100 + "." + String.format(Locale.ROOT, "%02d", n % 100);
    }
    static String fraction(int p, int q) {
        int a = p, b = q;
        while (b != 0) {
            int t = a % b;
            a = b;
            b = t;
        }
        return p / a + "/" + q / a;
    }
    static String hex(int value) {
        return String.format(Locale.ROOT, "%08x", value);
    }
    static String register(int value) {
        return value < 0 ? "-" : "r" + value;
    }
    static String heading(int first, int last) {
        StringBuilder s = new StringBuilder("cycle"
                                            + " ".repeat(18));
        for (int c = first; c <= last; c++)
            s.append(c % 10);
        return s.toString();
    }
    static String row(int number, int pc, String kind, String cells, String annotation) {
        return String.format(Locale.ROOT, "%6s %s %-6s %s%s", number < 0 ? "-" : Integer.toString(number),
                             hex(pc), kind, cells, annotation);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
