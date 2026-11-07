import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

record Attribute(int index, String name, boolean integer, List<String> values) {
    int parse(String text) {
        return text.equals("?") ? -1 : integer ? Integer.parseInt(text) : values.indexOf(text);
    }
}

record Row(String id, int[] values, int label) {
    int value(Attribute attribute) { return values[attribute.index()]; }
    int missingCount() { return (int) Arrays.stream(values).filter(value -> value < 0).count(); }
    Row withValue(Attribute attribute, int value) {
        int[] changed = values.clone();
        changed[attribute.index()] = value;
        return new Row(id, changed, label);
    }
}

record Settings(int maxDepth, int minSplit, int minLeaf, int maxSurrogates, int folds,
                List<Integer> curve, int bagTrees, long bagSeed, int repeats, long permutationSeed) {}

record Dataset(List<Attribute> attributes, String target, List<String> classes, List<Row> train,
               List<Row> validation, List<Row> test, Settings settings) {
    static List<String> lines(String path) throws IOException {
        return Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
    }

    static List<Row> rows(String path, List<Attribute> attributes, List<String> classes) throws IOException {
        List<Row> rows = new ArrayList<>();
        for (String line : lines(path).stream().skip(1).toList()) {
            String[] fields = line.split(",");
            int[] values = new int[attributes.size()];
            for (Attribute attribute : attributes) values[attribute.index()] = attribute.parse(fields[attribute.index() + 1]);
            rows.add(new Row(fields[0], values, classes.indexOf(fields[fields.length - 1])));
        }
        return rows;
    }

    static Dataset load(String directory) throws IOException {
        List<Attribute> attributes = new ArrayList<>();
        List<String> schema = lines(directory + "/schema.txt");
        for (String line : schema.subList(0, schema.size() - 1)) {
            List<String> fields = List.of(line.split(" "));
            attributes.add(new Attribute(attributes.size(), fields.get(1), fields.get(2).equals("INT"),
                fields.subList(3, fields.size())));
        }
        List<String> last = List.of(schema.getLast().split(" "));
        String target = last.get(1);
        List<String> classes = last.subList(2, last.size());
        Map<String, List<String>> params = new HashMap<>();
        for (String line : lines(directory + "/params.txt")) {
            List<String> fields = List.of(line.split(" "));
            params.put(fields.getFirst(), fields.subList(1, fields.size()));
        }
        Settings settings = new Settings(setting(params, "MAX_DEPTH"), setting(params, "MIN_SAMPLES_SPLIT"),
            setting(params, "MIN_SAMPLES_LEAF"), setting(params, "MAX_SURROGATES"), setting(params, "FOLDS"),
            params.get("CURVE").stream().map(Integer::parseInt).toList(), setting(params, "BAG_TREES"),
            setting(params, "BAG_SEED"), setting(params, "PERMUTATION_REPEATS"), setting(params, "PERMUTATION_SEED"));
        return new Dataset(attributes, target, classes, rows(directory + "/train.csv", attributes, classes),
            rows(directory + "/validation.csv", attributes, classes), rows(directory + "/test.csv", attributes, classes), settings);
    }

    private static int setting(Map<String, List<String>> params, String key) {
        return Integer.parseInt(params.get(key).getFirst());
    }
}
