import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;

final class Plot {
    static String real(double value) {
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }
    static String reals(double[] values) {
        List<String> result = new ArrayList<>();
        for (double v : values)
            result.add(real(v));
        return String.join(" ", result);
    }
    static String fraction(Evaluation.Fraction f) {
        return f == null ? "-" : f.n() + "/" + f.d() + " " + real((double)f.n() / f.d());
    }
    static String ratio(long n, long d) {
        return fraction(Evaluation.fraction(n, d));
    }
    static List<String> frame(char[][] grid) {
        String border = "+"
                        + "-".repeat(grid[0].length) + "+";
        List<String> lines = new ArrayList<>();
        lines.add(border);
        for (char[] row : grid)
            lines.add("|" + new String(row) + "|");
        lines.add(border);
        return lines;
    }
    static char[][] grid(int width, int height) {
        char[][] result = new char[height][width];
        for (char[] row : result)
            Arrays.fill(row, ' ');
        return result;
    }
    static int cell(double value, double lo, double hi, int size) {
        return (int)Math.floor((value - lo) / (hi - lo) * (size - 1) + 0.5);
    }
    static void place(char[][] grid, int col, int row, char letter) {
        char previous = grid[row][col];
        grid[row][col] = previous == ' ' || previous == letter ? letter : '*';
    }
    static void section(List<String> output, List<String> part) {
        if (!output.isEmpty())
            output.add("");
        output.addAll(part);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
