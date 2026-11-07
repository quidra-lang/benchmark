import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

record Row(String id, double[] values, String label, Double target) {}
record Settings(List<String> scalings, List<Integer> ks, List<String> metrics, List<String> weightings, int folds, int editK, List<Integer> curve, List<Double> bins, int top) {}
record Input(List<String> features, List<Row> train, List<Row> test, Settings settings) {}
final class Dataset {
    private record Table(List<String> features, List<Row> rows) {}
    private static Table readRows(String name) throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input", name)); List<String> header = Arrays.asList(lines.getFirst().split(","));
        List<Row> rows = new ArrayList<>();
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",", -1);
            double[] values = Arrays.stream(fields).skip(1).limit(fields.length - 3).mapToDouble(Double::parseDouble).toArray();
            rows.add(new Row(fields[0], values, fields[fields.length - 2].isEmpty() ? null : fields[fields.length - 2], fields[fields.length - 1].isEmpty() ? null : Double.parseDouble(fields[fields.length - 1])));
        }
        return new Table(header.subList(1, header.size() - 2), rows);
    }
    static Input read() throws IOException {
        Table train = readRows("train.csv"), test = readRows("test.csv"); Map<String, List<String>> values = new HashMap<>();
        for (String line : Files.readAllLines(Path.of("input/params.txt"))) { List<String> parts = Arrays.asList(line.split(" ")); values.put(parts.getFirst(), parts.subList(1, parts.size())); }
        Settings settings = new Settings(values.get("SCALINGS"), values.get("K_VALUES").stream().map(Integer::parseInt).toList(), values.get("METRICS"), values.get("WEIGHTINGS"), Integer.parseInt(values.get("FOLDS").getFirst()), Integer.parseInt(values.get("EDIT_K").getFirst()), values.get("CURVE").stream().map(Integer::parseInt).toList(), values.get("BINS").stream().map(Double::parseDouble).toList(), Integer.parseInt(values.get("TOP").getFirst()));
        return new Input(train.features, train.rows, test.rows, settings);
    }
}
