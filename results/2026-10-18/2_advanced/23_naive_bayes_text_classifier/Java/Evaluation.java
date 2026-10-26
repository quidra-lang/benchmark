import java.util.*;

final class Evaluation {
    final int[][] matrix;
    final int total;
    final int correct;
    final double microF1;
    final double macroF1;

    Evaluation(int classes, int[] truths, int[] predictions) {
        matrix = new int[classes][classes];
        for (int i = 0; i < truths.length; i++) matrix[truths[i]][predictions[i]]++;
        total = truths.length;
        int hits = 0;
        double sum = 0.0;
        int scored = 0;
        for (int c = 0; c < classes; c++) {
            hits += matrix[c][c];
            int denominator = predictedCount(c) + support(c);
            if (denominator > 0) { sum += (double) (2 * matrix[c][c]) / denominator; scored++; }
        }
        correct = hits;
        microF1 = (double) correct / total;
        macroF1 = sum / scored;
    }

    int support(int label) { return Arrays.stream(matrix[label]).sum(); }

    int predictedCount(int label) {
        int sum = 0;
        for (int[] row : matrix) sum += row[label];
        return sum;
    }

    static String real(double value) {
        String text = String.format(Locale.ROOT, "%.4f", value);
        return text.equals("-0.0000") ? "0.0000" : text;
    }

    static long rounded(double value) { return Math.round(value * 10000); }

    static String proportion(long numerator, long denominator) {
        return numerator + "/" + denominator + " " + real((double) numerator / denominator);
    }

    static String fraction(long numerator, long denominator) {
        if (denominator == 0) return "- -";
        long a = Math.abs(numerator), b = denominator;
        while (b != 0) { long remainder = a % b; a = b; b = remainder; }
        return proportion(numerator / a, denominator / a);
    }

    List<String> lines(String[] names) {
        List<String> lines = new ArrayList<>();
        lines.add("true\\predicted " + String.join(" ", names));
        for (int c = 0; c < names.length; c++) {
            StringJoiner row = new StringJoiner(" ");
            row.add(names[c]);
            for (int count : matrix[c]) row.add(Integer.toString(count));
            lines.add(row.toString());
        }
        for (int c = 0; c < names.length; c++) {
            int hits = matrix[c][c], predicted = predictedCount(c), support = support(c);
            lines.add("class " + names[c] + " precision " + fraction(hits, predicted) + " recall " + fraction(hits, support)
                + " f1 " + fraction(2L * hits, predicted + support) + " support " + support);
        }
        lines.add("micro_f1 " + real(microF1) + " macro_f1 " + real(macroF1));
        return lines;
    }
}
