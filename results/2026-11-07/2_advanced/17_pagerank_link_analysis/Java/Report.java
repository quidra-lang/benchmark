import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class Report {
    static String fixed(double value) { return fixed(value, 6); }
    static String fixed(double value, int places) {
        String text = String.format(Locale.ROOT, "%." + places + "f", value);
        return text.startsWith("-") && Double.parseDouble(text) == 0 ? text.substring(1) : text;
    }
    static long scaled(double value) { return scaled(value, 6); }
    static long scaled(double value, int places) { return Math.round(value * (places == 4 ? 10000 : 1000000)); }
    static String fraction(long numerator, long denominator) {
        long first = Math.abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        numerator /= first; denominator /= first;
        return numerator + "/" + denominator + " " + fixed((double) numerator / denominator, 4);
    }
    static void write(Map<String, List<String>> files) throws IOException {
        Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
