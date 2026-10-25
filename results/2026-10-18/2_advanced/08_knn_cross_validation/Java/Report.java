import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;

final class Report {
    static String fixed(double value) { return fixed(value, 4); }
    static String fixed(double value, int places) {
        String text = String.format(Locale.ROOT, "%." + places + "f", value); return text.startsWith("-") && Double.parseDouble(text) == 0 ? text.substring(1) : text;
    }
    static double fourDecimal(double value) { return Double.parseDouble(fixed(value)); }
    static String ratio(int numerator, int denominator) { return numerator + "/" + denominator + " " + fixed((double)numerator / denominator); }
    static String fraction(int numerator, int denominator) {
        if (denominator == 0) return "- -";
        int a = numerator, b = denominator; while (b != 0) { int next = a % b; a = b; b = next; }
        return numerator / a + "/" + denominator / a + " " + fixed((double)numerator / denominator);
    }
    static void write(String name, List<String> lines) throws IOException { Files.createDirectories(Path.of("output")); Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n", StandardCharsets.US_ASCII); }
}
