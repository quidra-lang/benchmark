import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Dataframe {
    record Row(int number, Map<String, String> values) {
        double numeric(String name) {
            String value = values.get(name);
            return value == null ? Double.NaN : Double.parseDouble(value);
        }
    }
    static final class Frame {
        List<String> columns;
        List<Row> rows = new ArrayList<>();
    }
    static final class Settings {
        Map<String, String[]> values = new HashMap<>();
        double number(String key) {
            return Double.parseDouble(values.get(key)[0]);
        }
        int integer(String key) {
            return Integer.parseInt(values.get(key)[0]);
        }
        int width() {
            return Integer.parseInt(values.get("PLOT")[0]);
        }
        int height() {
            return Integer.parseInt(values.get("PLOT")[1]);
        }
        double limit() {
            return Double.parseDouble(values.get("PLOT")[2]);
        }
    }
    record Data(Frame frame, Frame predictions, Set<String> categorical, List<String> models,
                Settings settings) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Frame frame(String name) throws IOException {
        List<String> lines = lines(name);
        Frame f = new Frame();
        f.columns = new ArrayList<>(Arrays.asList(lines.get(0).split(",")));
        for (int i = 1; i < lines.size(); i++) {
            String[] words = lines.get(i).split(",");
            Map<String, String> values = new HashMap<>();
            for (int j = 0; j < words.length; j++)
                values.put(f.columns.get(j), words[j].equals("NA") ? null : words[j]);
            f.rows.add(new Row(i, values));
        }
        return f;
    }
    static Data read() throws IOException {
        Frame frame = frame("data.csv");
        Set<String> categorical = new HashSet<>();
        for (String column : frame.columns)
            for (Row row : frame.rows) {
                String value = row.values().get(column);
                if (value != null && value.charAt(0) >= 'A' && value.charAt(0) <= 'Z')
                    categorical.add(column);
            }
        Settings s = new Settings();
        for (String line : lines("params.txt")) {
            String[] words = line.split(" ");
            s.values.put(words[0], Arrays.copyOfRange(words, 1, words.length));
        }
        return new Data(frame, frame("predict.csv"), categorical, lines("model.txt"), s);
    }
}
