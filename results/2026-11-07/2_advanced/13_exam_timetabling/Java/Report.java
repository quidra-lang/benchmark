import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

final class Report {
    static String fixedWidthLine(String label, List<String> cells, int labelWidth, int cellWidth) {
        StringBuilder line = new StringBuilder(label);
        line.append(" ".repeat(Math.max(0, labelWidth - label.length())));
        for (String cell : cells)
            line.append(" ".repeat(Math.max(0, cellWidth - cell.length()))).append(cell);
        return line.toString().stripTrailing();
    }

    static int roundedPercent(int part, int whole) {
        return (200 * part + whole) / (2 * whole);
    }

    static void writeFiles(String directory, Map<String, List<String>> files) throws IOException {
        Files.createDirectories(Path.of(directory));
        for (var file : files.entrySet())
            Files.writeString(Path.of(directory, file.getKey()), String.join("\n", file.getValue()) + "\n",
                StandardCharsets.US_ASCII);
    }
}
