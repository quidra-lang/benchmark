import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;
final class Dataset {
    record Point(int x, int y) {}
    record Test(String name, int position) {}
    static final class Series {
        final String name;
        final int[] positions, hundredths;
        final double[] x, y;
        final int n;
        Series(String name, int[] positions, int[] hundredths) {
            this.name = name;
            this.positions = positions;
            this.hundredths = hundredths;
            n = positions.length;
            x = new double[n];
            y = new double[n];
            for (int i = 0; i < n; i++) {
                x[i] = positions[i] / 100.0;
                y[i] = hundredths[i] / 100.0;
            }
        }
        Series subset(int group, int folds) {
            List<Integer> selected = new ArrayList<>();
            for (int i = 0; i < n; i++)
                if (folds == 0 ? i != group : i % folds != group)
                    selected.add(i);
            int[] xx = new int[selected.size()], yy = new int[selected.size()];
            for (int i = 0; i < selected.size(); i++) {
                xx[i] = positions[selected.get(i)];
                yy[i] = hundredths[selected.get(i)];
            }
            return new Series(name, xx, yy);
        }
    }
    final List<Series> series = new ArrayList<>();
    final List<Test> tests = new ArrayList<>();
    final Map<String, String[]> settings = new HashMap<>();
    static int hundredths(String value) {
        return Integer.parseInt(value.replace(".", ""));
    }
    Dataset() throws IOException {
        Map<String, List<Point>> groups = new LinkedHashMap<>();
        List<String> names = new ArrayList<>();
        List<String> lines = Files.readAllLines(Path.of("input/series.csv"), StandardCharsets.US_ASCII);
        for (String line : lines.subList(1, lines.size())) {
            String[] parts = line.split(",");
            if (!groups.containsKey(parts[0])) {
                groups.put(parts[0], new ArrayList<>());
                names.add(parts[0]);
            }
            groups.get(parts[0]).add(new Point(hundredths(parts[1]), hundredths(parts[2])));
        }
        for (String name : names) {
            List<Point> points = groups.get(name);
            points.sort(Comparator.comparingInt(Point::x));
            int[] xx = new int[points.size()], yy = new int[points.size()];
            for (int i = 0; i < points.size(); i++) {
                xx[i] = points.get(i).x;
                yy[i] = points.get(i).y;
            }
            series.add(new Series(name, xx, yy));
        }
        lines = Files.readAllLines(Path.of("input/test_points.csv"), StandardCharsets.US_ASCII);
        for (String line : lines.subList(1, lines.size())) {
            String[] parts = line.split(",");
            tests.add(new Test(parts[0], hundredths(parts[1])));
        }
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            String[] parts = line.split(" ");
            settings.put(parts[0], Arrays.copyOfRange(parts, 1, parts.length));
        }
    }
    int integer(String key) {
        return Integer.parseInt(settings.get(key)[0]);
    }
    double number(String key) {
        return Double.parseDouble(settings.get(key)[0]);
    }
    String[] values(String key) {
        return settings.get(key);
    }
}
