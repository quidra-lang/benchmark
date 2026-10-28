using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public record Fold(List<int> train, List<int> test) {
    }
    public record Counts(int tp, int fp, int tn, int fn) {
        public int CorrectCount() {
            return tp + tn;
        }
    }
    public static int Sign(double value) {
        return value > 0 ? 1 : -1;
    }
    public static List<Fold> Folds(int size, int count) {
        List<Fold> folds = new();
        for (int k = 0; k < count; k++) {
            List<int> train = new(), test = new();
            for (int i = 0; i < size; i++)
                (i % count == k ? test : train).Add(i);
            folds.Add(new Fold(train, test));
        }
        return folds;
    }
    public static int Correct(int[] labels, double[] values) {
        int count = 0;
        for (int i = 0; i < labels.Length; i++)
            if (Sign(values[i]) == labels[i])
                count++;
        return count;
    }
    public static Counts BinaryCounts(int[] labels, double[] values) {
        int tp = 0, fp = 0, tn = 0, fn = 0;
        for (int i = 0; i < labels.Length; i++)
            if (labels[i] == 1) {
                if (Sign(values[i]) == 1)
                    tp++;
                else
                    fn++;
            } else {
                if (Sign(values[i]) == 1)
                    fp++;
                else
                    tn++;
            }
        return new Counts(tp, fp, tn, fn);
    }
    public static double Auc(int[] labels, double[] values) {
        int positives = 0, negatives = 0;
        foreach (int y in labels)
            if (y == 1)
                positives++;
            else
                negatives++;
        double sum = 0;
        for (int i = 0; i < labels.Length; i++)
            if (labels[i] == 1)
                for (int j = 0; j < labels.Length; j++)
                    if (labels[j] == -1) {
                        if (values[i] > values[j])
                            sum += 1;
                        else if (values[i] == values[j])
                            sum += 0.5;
                    }
        return sum / (positives * negatives);
    }
    public static int[][] Confusion(int[] classes, int[] predictions) {
        int[][] matrix = Enumerable.Range(0, 3)
                             .Select(
                                 _ => new int[3])
                             .ToArray();
        for (int i = 0; i < classes.Length; i++)
            matrix[classes[i] - 1][predictions[i] - 1]++;
        return matrix;
    }
    public static List<string> ConfusionLines(int[][] matrix) {
        List<string> lines = new();
        foreach (int[] row in matrix)
            lines.Add(row[0] + " " + row[1] + " " + row[2]);
        for (int i = 0; i < 3; i++) {
            int column = 0, row = 0;
            for (int j = 0; j < 3; j++) {
                column += matrix[j][i];
                row += matrix[i][j];
            }
            lines.Add("class " + (i + 1) + " precision " + Ratio(matrix[i][i], column) + " recall " +
                      Ratio(matrix[i][i], row));
        }
        return lines;
    }
    public static string Fixed(double value, int decimals) {
        string result = value.ToString("F" + decimals, CultureInfo.InvariantCulture);
        return result.StartsWith("-", StringComparison.Ordinal) &&
                       double.Parse(result, CultureInfo.InvariantCulture) == 0
                   ? result[1..]
                   : result;
    }
    public static string Ratio(int p, int q) {
        return q == 0 ? "-" : Fixed((double)p / q, 4);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
}
