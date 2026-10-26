import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

final class Report {
    static String decimal(Rational value, int digits) {
        long scale = 1; for (int i = 0; i < digits; i++) scale *= 10;
        long scaled = (2 * scale * Math.abs(value.numerator()) + value.denominator()) / (2 * value.denominator());
        String fraction = Long.toString(scaled % scale);
        return (value.numerator() < 0 && scaled > 0 ? "-" : "") + scaled / scale + "." + "0".repeat(digits - fraction.length()) + fraction;
    }
    static String hullArea(long doubled) { return doubled / 2 + "." + (doubled % 2 == 0 ? "0" : "5"); }
    static void write(Map<String, List<String>> files) throws IOException {
        Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
