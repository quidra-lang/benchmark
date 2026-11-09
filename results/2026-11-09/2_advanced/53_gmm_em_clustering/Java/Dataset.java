import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;

final class Dataset {
    record Point(String id, double x, double y) {}
    static final class Params {
        Map<String, String[]> values = new HashMap<>();
        int integer(String key) {
            return Integer.parseInt(values.get(key)[0]);
        }
        double get(String key) {
            return Double.parseDouble(values.get(key)[0]);
        }
        String[] words(String key) {
            return values.get(key);
        }
        double[] row(String key) {
            String[] words = values.get(key);
            double[] result = new double[words.length];
            for (int i = 0; i < words.length; i++)
                result[i] = Double.parseDouble(words[i]);
            return result;
        }
    }
    record Data(List<Point> points, Map<Integer, Em.Model> initial, Params params) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Data read() throws IOException {
        List<Point> points = new ArrayList<>();
        List<String> input = lines("points.csv");
        for (int i = 1; i < input.size(); i++) {
            String[] w = input.get(i).split(",");
            points.add(new Point(w[0], Double.parseDouble(w[1]), Double.parseDouble(w[2])));
        }
        Map<Integer, Em.Model> initial = new HashMap<>();
        input = lines("init.txt");
        int cursor = 0;
        while (cursor < input.size()) {
            if (input.get(cursor).isEmpty()) {
                cursor++;
                continue;
            }
            int k = Integer.parseInt(input.get(cursor++).split(" ")[1]);
            Em.Model model = new Em.Model(k);
            String[] weights = input.get(cursor++).split(" ");
            for (int j = 0; j < k; j++)
                model.weights[j] = Double.parseDouble(weights[j + 1]);
            for (int j = 0; j < k; j++) {
                String[] w = input.get(cursor++).split(" ");
                model.means[j][0] = Double.parseDouble(w[2]);
                model.means[j][1] = Double.parseDouble(w[3]);
                for (int c = 0; c < 3; c++)
                    model.cov[j][c] = Double.parseDouble(w[c + 4]);
            }
            initial.put(k, model);
        }
        Params params = new Params();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            params.values.put(w[0], Arrays.copyOfRange(w, 1, w.length));
        }
        return new Data(points, initial, params);
    }
}
