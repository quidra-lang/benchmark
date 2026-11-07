import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record Point(int id, int x, int y) {}
final class Dataset {
    final List<Point> points = new ArrayList<>();
    final Map<String, String[]> settings = new HashMap<>();
    Dataset() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/points.csv"), StandardCharsets.US_ASCII);
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",");
            points.add(new Point(Integer.parseInt(fields[0]), Integer.parseInt(fields[1]),
                                 Integer.parseInt(fields[2])));
        }
        points.sort(Comparator.comparingInt(Point::id));
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            String[] fields = line.split(" ");
            settings.put(fields[0], Arrays.copyOfRange(fields, 1, fields.length));
        }
    }
    int value(String key) {
        return Integer.parseInt(settings.get(key)[0]);
    }
    int value(String key, int index) {
        return Integer.parseInt(settings.get(key)[index]);
    }
    int[] values(String key) {
        String[] fields = settings.get(key);
        int[] values = new int[fields.length];
        for (int i = 0; i < values.length; i++)
            values[i] = Integer.parseInt(fields[i]);
        return values;
    }
}
