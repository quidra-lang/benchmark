import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class Report {
    static String real(double value) {
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static String reals(double[] values) {
        List<String> text = new ArrayList<>();
        for (double value : values) text.add(real(value));
        return String.join(" ", text);
    }
    static double fourDecimal(double value) { return Double.parseDouble(real(value)); }
    static String amount(long cents) {
        long absolute = Math.abs(cents);
        return (cents < 0 ? "-" : "") + absolute / 100 + "." + String.format(Locale.ROOT, "%02d", absolute % 100);
    }
    static void writeFiles(Map<String, List<String>> files) throws IOException {
        Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
