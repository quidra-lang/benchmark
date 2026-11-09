import java.nio.file.*;
import java.util.*;
final class Report {
    static String f(double value, int places) {
        String result = String.format(Locale.ROOT, "%." + places + "f", value);
        return result.startsWith("-") && Double.parseDouble(result) == 0 ? result.substring(1)
                                                                         : result;
    }
    static String optional(Double value, int places) {
        return value == null ? "none" : f(value, places);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
    static List<String> plot(char[][] cells, String[] labels) {
        int width = 0;
        for (String label : labels)
            width = Math.max(width, label.length());
        List<String> lines = new ArrayList<>();
        for (int q = 0; q < cells.length; q++)
            lines.add(" ".repeat(width - labels[q].length()) + labels[q] + " |" +
                      new String(cells[q]) + "|");
        StringBuilder axis = new StringBuilder(" ".repeat(width) + " +");
        for (int c = 0; c < cells[0].length; c++)
            axis.append(c % 6 == 0 ? '+' : '-');
        axis.append('+');
        lines.add(axis.toString());
        return lines;
    }
}
