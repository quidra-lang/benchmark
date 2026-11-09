import java.nio.file.*;
import java.util.*;

final class Evaluation {
    record Fold(List<Integer> train, List<Integer> test) {}
    record Counts(int tp, int fp, int tn, int fn) {
        int correct() {
            return tp + tn;
        }
    }
    static int sign(double value) {
        return value > 0 ? 1 : -1;
    }
    static List<Fold> folds(int size, int count) {
        List<Fold> folds = new ArrayList<>();
        for (int k = 0; k < count; k++) {
            List<Integer> train = new ArrayList<>(), test = new ArrayList<>();
            for (int i = 0; i < size; i++)
                (i % count == k ? test : train).add(i);
            folds.add(new Fold(train, test));
        }
        return folds;
    }
    static int correct(int[] labels, double[] values) {
        int count = 0;
        for (int i = 0; i < labels.length; i++)
            if (sign(values[i]) == labels[i])
                count++;
        return count;
    }
    static Counts counts(int[] labels, double[] values) {
        int tp = 0, fp = 0, tn = 0, fn = 0;
        for (int i = 0; i < labels.length; i++)
            if (labels[i] == 1) {
                if (sign(values[i]) == 1)
                    tp++;
                else
                    fn++;
            } else {
                if (sign(values[i]) == 1)
                    fp++;
                else
                    tn++;
            }
        return new Counts(tp, fp, tn, fn);
    }
    static double auc(int[] labels, double[] values) {
        int positives = 0, negatives = 0;
        for (int y : labels)
            if (y == 1)
                positives++;
            else
                negatives++;
        double sum = 0;
        for (int i = 0; i < labels.length; i++)
            if (labels[i] == 1)
                for (int j = 0; j < labels.length; j++)
                    if (labels[j] == -1) {
                        if (values[i] > values[j])
                            sum += 1;
                        else if (values[i] == values[j])
                            sum += 0.5;
                    }
        return sum / (positives * negatives);
    }
    static int[][] confusion(int[] classes, int[] predictions) {
        int[][] matrix = new int[3][3];
        for (int i = 0; i < classes.length; i++)
            matrix[classes[i] - 1][predictions[i] - 1]++;
        return matrix;
    }
    static List<String> confusionLines(int[][] matrix) {
        List<String> lines = new ArrayList<>();
        for (int[] row : matrix)
            lines.add(row[0] + " " + row[1] + " " + row[2]);
        for (int i = 0; i < 3; i++) {
            int column = 0, row = 0;
            for (int j = 0; j < 3; j++) {
                column += matrix[j][i];
                row += matrix[i][j];
            }
            lines.add("class " + (i + 1) + " precision " + ratio(matrix[i][i], column) + " recall " +
                      ratio(matrix[i][i], row));
        }
        return lines;
    }
    static String fixed(double value, int decimals) {
        String s = String.format(Locale.ROOT, "%." + decimals + "f", value);
        return s.startsWith("-") && Double.parseDouble(s) == 0 ? s.substring(1) : s;
    }
    static String ratio(int p, int q) {
        return q == 0 ? "-" : fixed((double)p / q, 4);
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
