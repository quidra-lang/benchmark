import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class Report {
    static long gcd(long a, long b) {
        a = Math.abs(a);
        while (b != 0) {
            long old = b;
            b = a % b;
            a = old;
        }
        return a;
    }
    static String fraction(long numerator, long denominator) {
        long divisor = gcd(numerator, denominator);
        return numerator / divisor + "/" + denominator / divisor;
    }
    static String root(int value) {
        return value == Optics.INF ? "-" : String.format(Locale.ROOT, "%.3f", Math.sqrt(value));
    }
    static String ari(long numerator, long denominator) {
        String value = String.format(Locale.ROOT, "%.4f", (double)numerator / denominator);
        if (value.equals("-0.0000"))
            value = "0.0000";
        return fraction(numerator, denominator) + " " + value;
    }
    static List<String> framed(List<String> rows, int width) {
        String border = "+"
                        + "-".repeat(width) + "+";
        List<String> lines = new ArrayList<>();
        lines.add(border);
        for (String row : rows)
            lines.add("|" + row + "|");
        lines.add(border);
        return lines;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
