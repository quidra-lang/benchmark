import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Dataset {
    record Row(String id, double[] x, int label) {}
    record Table(List<String> names, List<Row> rows) {}
    static final class Settings {
        Map<String, String[]> values = new HashMap<>();
        int integer(String key) {
            return Integer.parseInt(values.get(key)[0]);
        }
        double number(String key) {
            return Double.parseDouble(values.get(key)[0]);
        }
        int[] integers(String key) {
            String[] words = values.get(key);
            int[] result = new int[words.length];
            for (int i = 0; i < result.length; i++)
                result[i] = Integer.parseInt(words[i]);
            return result;
        }
        double[] numbers(String key) {
            String[] words = values.get(key);
            double[] result = new double[words.length];
            for (int i = 0; i < result.length; i++)
                result[i] = Double.parseDouble(words[i]);
            return result;
        }
        List<String> variants() {
            return Arrays.asList(values.get("VARIANTS"));
        }
    }
    record Data(Table train, Table test, Table multiTrain, Table multiTest, Settings settings) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Table table(List<String> lines, boolean multi, String role) {
        String[] header = lines.get(0).split(",");
        int count = header.length - (multi ? 3 : 2);
        List<String> names = new ArrayList<>(Arrays.asList(header).subList(1, count + 1));
        List<Row> rows = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++) {
            String[] words = lines.get(i).split(",");
            if (multi && !words[words.length - 1].equals(role))
                continue;
            double[] x = new double[count];
            for (int j = 0; j < count; j++)
                x[j] = Double.parseDouble(words[j + 1]);
            rows.add(new Row(words[0], x, Integer.parseInt(words[count + 1])));
        }
        return new Table(names, rows);
    }
    static Data read() throws IOException {
        Settings s = new Settings();
        for (String line : lines("params.txt")) {
            String[] words = line.split(" ");
            s.values.put(words[0], Arrays.copyOfRange(words, 1, words.length));
        }
        List<String> multi = lines("multiclass.csv");
        return new Data(table(lines("train.csv"), false, ""), table(lines("test.csv"), false, ""),
                        table(multi, true, "train"), table(multi, true, "test"), s);
    }
}
