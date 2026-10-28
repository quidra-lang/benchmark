import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.math.*;
import java.io.IOException;

final class Report {
    static String decimal(double value, int digits) {
        if (Double.isNaN(value))
            return "-";
        BigDecimal result = BigDecimal.valueOf(value).setScale(digits, RoundingMode.HALF_UP);
        if (result.signum() == 0)
            result = BigDecimal.ZERO.setScale(digits);
        return result.toPlainString();
    }
    static String f(double value) {
        return decimal(value, 4);
    }
    static BigDecimal rounded(double value) {
        return BigDecimal.valueOf(value).setScale(4, RoundingMode.HALF_UP);
    }
    static List<String> frame(char[][] map) {
        String edge = "+"
                      + "-".repeat(map[0].length) + "+";
        List<String> out = new ArrayList<>();
        out.add(edge);
        for (char[] row : map)
            out.add("|" + new String(row) + "|");
        out.add(edge);
        return out;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
