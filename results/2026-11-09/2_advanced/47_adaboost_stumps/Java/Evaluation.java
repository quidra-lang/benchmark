import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class Evaluation {
    static String format(double value, int digits) {
        if (Double.isNaN(value))
            return "-";
        String text = String.format(Locale.ROOT, "%." + digits + "f", value);
        return Double.parseDouble(text) == 0 && text.startsWith("-") ? text.substring(1) : text;
    }
    static String real(double value) {
        return format(value, 4);
    }
    static String ratio(int a, int b) {
        return b > 0 ? real((double)a / b) : "-";
    }
    static int prediction(double score) {
        return score > 0 ? 1 : -1;
    }
    static double auc(List<Dataset.Row> rows, double[] scores) {
        int positives = 0, negatives = 0, wins = 0, ties = 0;
        for (int i = 0; i < rows.size(); i++)
            if (rows.get(i).label() == 1) {
                positives++;
                for (int j = 0; j < rows.size(); j++)
                    if (rows.get(j).label() == -1) {
                        if (scores[i] > scores[j])
                            wins++;
                        else if (scores[i] == scores[j])
                            ties++;
                    }
            } else
                negatives++;
        return positives * negatives == 0 ? Double.NaN
                                          : (double)(2 * wins + ties) / (2 * positives * negatives);
    }
    static int[][] confusion(List<Dataset.Row> rows, int[] predictions, int classes) {
        int[][] result = new int[classes][classes];
        for (int i = 0; i < rows.size(); i++)
            result[rows.get(i).label() - 1][predictions[i] - 1]++;
        return result;
    }
    static int le(double[] values, double threshold) {
        int count = 0;
        for (double value : values)
            if (value <= threshold)
                count++;
        return count;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
}
