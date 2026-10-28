import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;

final class SignalIo {
    static final class Params {
        Map<String, String[]> values = new HashMap<>();
        int integer(String key, int i) {
            return Integer.parseInt(values.get(key)[i]);
        }
        int integer(String key) {
            return integer(key, 0);
        }
        double get(String key, int i) {
            return Double.parseDouble(values.get(key)[i]);
        }
        double get(String key) {
            return get(key, 0);
        }
        String word(String key, int i) {
            return values.get(key)[i];
        }
        String word(String key) {
            return word(key, 0);
        }
        double[] row(String key) {
            String[] w = values.get(key);
            double[] result = new double[w.length];
            for (int i = 0; i < w.length; i++)
                result[i] = Double.parseDouble(w[i]);
            return result;
        }
    }
    record Data(int fs, double[] first, double[] second, Params params) {}
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static Data read() throws IOException {
        List<String> input = lines("signal.csv");
        String[] header = input.get(0).split(",");
        int fs = Integer.parseInt(header[0]), n = Integer.parseInt(header[1]);
        double[] first = new double[n], second = new double[n];
        for (int i = 0; i < n; i++) {
            String[] w = input.get(i + 1).split(",");
            first[i] = Double.parseDouble(w[0]);
            second[i] = Double.parseDouble(w[1]);
        }
        Params params = new Params();
        for (String line : lines("params.txt")) {
            String[] w = line.split(" ");
            params.values.put(w[0], Arrays.copyOfRange(w, 1, w.length));
        }
        return new Data(fs, first, second, params);
    }
}
