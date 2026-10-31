using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public static string Format(double value, int digits) {
        if (double.IsNaN(value))
            return "-";
        string text = value.ToString("F" + digits, CultureInfo.InvariantCulture);
        return double.Parse(text) == 0 && text.StartsWith("-") ? text.Substring(1) : text;
    }
    public static string Real(double value) {
        return Format(value, 4);
    }
    public static string Ratio(int a, int b) {
        return b > 0 ? Real((double)a / b) : "-";
    }
    public static int Prediction(double score) {
        return score > 0 ? 1 : -1;
    }
    public static double Auc(List<Dataset.Row> rows, double[] scores) {
        int positives = 0, negatives = 0, wins = 0, ties = 0;
        for (int i = 0; i < rows.Count; i++)
            if (rows[i].label == 1) {
                positives++;
                for (int j = 0; j < rows.Count; j++)
                    if (rows[j].label == -1) {
                        if (scores[i] > scores[j])
                            wins++;
                        else if (scores[i] == scores[j])
                            ties++;
                    }
            } else
                negatives++;
        return positives * negatives == 0 ? double.NaN
                                          : (double)(2 * wins + ties) / (2 * positives * negatives);
    }
    public static int[][] Confusion(List<Dataset.Row> rows, int[] predictions, int classes) {
        int[][] result = Enumerable.Range(0, classes)
                             .Select(
                                 _ => new int[classes])
                             .ToArray();
        for (int i = 0; i < rows.Count; i++)
            result[rows[i].label - 1][predictions[i] - 1]++;
        return result;
    }
    public static int Le(double[] values, double threshold) {
        int count = 0;
        foreach (double value in values)
            if (value <= threshold)
                count++;
        return count;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
