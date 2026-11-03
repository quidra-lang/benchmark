import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Dataset {
    record Row(String id, double[] values) {}
    record Table(List<String> names, List<Row> rows) {}
    static final class Settings {
        Map<String, String[]> values = new HashMap<>();
        String text(String key) {
            return values.get(key)[0];
        }
        int integer(String key) {
            return Integer.parseInt(text(key));
        }
        double number(String key) {
            return Double.parseDouble(text(key));
        }
        int second(String key) {
            return Integer.parseInt(values.get(key)[1]);
        }
    }
    record Data(Table data, Table supplementary, Settings settings) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Table table(String name) throws IOException {
        List<String> lines = lines(name);
        List<String> names = new ArrayList<>(Arrays.asList(lines.get(0).split(",")));
        names.remove(0);
        List<Row> rows = new ArrayList<>();
        for (int i = 1; i < lines.size(); i++) {
            String[] words = lines.get(i).split(",");
            double[] values = new double[names.size()];
            for (int j = 0; j < values.length; j++)
                values[j] = words[j + 1].equals("NA") ? Double.NaN : Double.parseDouble(words[j + 1]);
            rows.add(new Row(words[0], values));
        }
        return new Table(names, rows);
    }
    static Data read() throws IOException {
        Settings settings = new Settings();
        for (String line : lines("params.txt")) {
            String[] words = line.split(" ");
            settings.values.put(words[0], Arrays.copyOfRange(words, 1, words.length));
        }
        return new Data(table("data.csv"), table("supplementary.csv"), settings);
    }
}
