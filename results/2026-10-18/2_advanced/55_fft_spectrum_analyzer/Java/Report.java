import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.math.*;
import java.io.IOException;

final class Report {
    static String f(double value) {
        BigDecimal result = BigDecimal.valueOf(value).setScale(4, RoundingMode.HALF_UP);
        if (result.signum() == 0)
            result = BigDecimal.ZERO.setScale(4);
        return result.toPlainString();
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static List<String> shades(Spectral.Frames frames, int fs, int length, int band) {
        List<String> out = new ArrayList<>();
        String characters = " .:-=+*#%@";
        for (int k = length / 2; k >= 0; k--) {
            String frequency = f((double)k * fs / length),
                   line = " ".repeat(Math.max(0, 9 - frequency.length())) + frequency + " |";
            for (double[] frame : frames.magnitude()) {
                double db = 20 * Math.log10(frame[k] / frames.maximum());
                int level = Math.max(0, 9 - (int)Math.floor(-db / band));
                line += characters.charAt(level);
            }
            out.add(line + "|");
        }
        return out;
    }
}
