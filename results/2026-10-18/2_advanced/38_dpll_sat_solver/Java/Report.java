import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class Report {
    static String numbers(List<Integer> values) {
        if (values.isEmpty())
            return "-";
        List<String> text = new ArrayList<>();
        for (int value : values)
            text.add(Integer.toString(value));
        return String.join(",", text);
    }
    static String numbers(int[] values) {
        List<Integer> list = new ArrayList<>();
        for (int value : values)
            list.add(value);
        return numbers(list);
    }
    static String frequency(List<Integer> values) {
        SortedMap<Integer, Integer> counts = new TreeMap<>();
        for (int value : values)
            counts.merge(value, 1, Integer::sum);
        List<String> text = new ArrayList<>();
        for (Map.Entry<Integer, Integer> entry : counts.entrySet())
            text.add(entry.getKey() + ":" + entry.getValue());
        return text.isEmpty() ? "-" : String.join(",", text);
    }
    static List<String> board(int[] positions) {
        List<String> rows = new ArrayList<>();
        for (int column : positions) {
            char[] row = new char[positions.length];
            Arrays.fill(row, '.');
            row[column - 1] = 'Q';
            rows.add(new String(row));
        }
        return rows;
    }
    static String search(Dpll.Stats stats) {
        return "decisions=" + stats.decisions + " propagations=" + stats.propagations +
            " conflicts=" + stats.conflicts + " max_depth=" + stats.maxDepth;
    }
    static void paragraph(List<String> output, List<String> lines) {
        if (!output.isEmpty())
            output.add("");
        output.addAll(lines);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
