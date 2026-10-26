import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.stream.Collectors;

final class Report {
    static String real(double value) {
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static String pValue(long numerator, long denominator) {
        long[] fraction = Tests.reducedFraction(numerator, denominator);
        return fraction[0] + "/" + fraction[1] + " " + real((double) fraction[0] / fraction[1]);
    }
    static String numberList(Collection<Integer> numbers) {
        return numbers.isEmpty() ? "none" : numbers.stream().sorted().map(Object::toString).collect(Collectors.joining(" "));
    }
    static int binNumber(double value, double low, double high, int bins) {
        return Math.min((int) Math.floor(bins * (value - low) / (high - low)), bins - 1) + 1;
    }
    static String bar(int count, int top) { return "#".repeat((40 * count + top - 1) / top); }
    static void writeFiles(Map<String, List<String>> files) throws IOException {
        Files.createDirectories(Path.of("output"));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
