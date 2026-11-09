import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record Example(String id, double[] values, int label) {}
record Statistics(double[] means, double[] deviations) {}
final class Dataset {
    final List<Example> train, test;
    final String[] names;
    final Map<String, String[]> settings = new HashMap<>();
    final List<int[]> tuples = new ArrayList<>();
    final List<String> features = new ArrayList<>();
    Dataset() throws IOException {
        List<String> lines = lines("train.csv");
        String[] header = lines.getFirst().split(",");
        names = Arrays.copyOfRange(header, 1, header.length - 1);
        train = examples(lines);
        test = examples(lines("test.csv"));
        for (String line : lines("params.txt")) {
            String[] fields = line.split(" ");
            settings.put(fields[0], Arrays.copyOfRange(fields, 1, fields.length));
        }
        for (int degree = 1; degree <= integer("DEGREE", 0); degree++)
            expand(new int[degree], 0, 0);
        for (int[] tuple : tuples) {
            List<String> factors = new ArrayList<>();
            for (int index : tuple)
                factors.add(names[index]);
            features.add(String.join("*", factors));
        }
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static List<Example> examples(List<String> lines) {
        List<Example> rows = new ArrayList<>();
        for (String line : lines.subList(1, lines.size())) {
            String[] fields = line.split(",");
            double[] values = new double[fields.length - 2];
            for (int j = 0; j < values.length; j++)
                values[j] = Double.parseDouble(fields[j + 1]);
            rows.add(new Example(fields[0], values, Integer.parseInt(fields[fields.length - 1])));
        }
        return rows;
    }
    int integer(String key, int index) {
        return Integer.parseInt(settings.get(key)[index]);
    }
    double number(String key, int index) {
        return Double.parseDouble(settings.get(key)[index]);
    }
    void expand(int[] tuple, int position, int minimum) {
        if (position == tuple.length) {
            tuples.add(tuple.clone());
            return;
        }
        for (int index = minimum; index < names.length; index++) {
            tuple[position] = index;
            expand(tuple, position + 1, index);
        }
    }
    double[] expanded(double[] values) {
        double[] result = new double[tuples.size()];
        for (int j = 0; j < result.length; j++) {
            int[] tuple = tuples.get(j);
            double product = values[tuple[0]];
            for (int k = 1; k < tuple.length; k++)
                product *= values[tuple[k]];
            result[j] = product;
        }
        return result;
    }
    double[][] expanded(List<Example> rows) {
        double[][] values = new double[rows.size()][];
        for (int i = 0; i < rows.size(); i++)
            values[i] = expanded(rows.get(i).values());
        return values;
    }
    static Statistics statistics(double[][] rows, int count) {
        double[] means = new double[count], deviations = new double[count];
        for (int j = 0; j < count; j++) {
            double total = 0;
            for (double[] row : rows)
                total += row[j];
            double mean = total / rows.length;
            means[j] = mean;
            double squares = 0;
            for (double[] row : rows) {
                double delta = row[j] - mean;
                squares += delta * delta;
            }
            deviations[j] = Math.sqrt(squares / (rows.length - 1));
        }
        return new Statistics(means, deviations);
    }
    static double[] standardize(double[] values, Statistics statistics, int count) {
        double[] vector = new double[count + 1];
        vector[0] = 1;
        for (int j = 0; j < count; j++)
            vector[j + 1] = (values[j] - statistics.means()[j]) / statistics.deviations()[j];
        return vector;
    }
    static double[][] standardize(double[][] rows, Statistics statistics, int count) {
        double[][] result = new double[rows.length][];
        for (int i = 0; i < rows.length; i++)
            result[i] = standardize(rows[i], statistics, count);
        return result;
    }
}
