using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Evaluation {
    public static string Real(double value, int digits) {
        string result = value.ToString("F" + digits, CultureInfo.InvariantCulture);
        return result.StartsWith("-", StringComparison.Ordinal) &&
                       double.Parse(result, CultureInfo.InvariantCulture) == 0
                   ? result[1..]
                   : result;
    }
    public static string Ratio(int a, int b) {
        if (b == 0)
            return "-";
        int q = (20000 * a + b) / (2 * b);
        return q / 10000 + "." + (q % 10000).ToString("D4", CultureInfo.InvariantCulture);
    }
    public static int Prediction(double[] scores) {
        int selected = 0;
        for (int k = 1; k < scores.Length; k++)
            if (scores[k] > scores[selected])
                selected = k;
        return selected;
    }
    public static int Second(double[] scores, int first) {
        int selected = -1;
        for (int k = 0; k < scores.Length; k++)
            if (k != first && (selected < 0 || scores[k] > scores[selected]))
                selected = k;
        return selected;
    }
    public static int[][] Confusion(List<Dataset.Image> images, List<Network.Pass> passes, int classes) {
        int[][] counts = Enumerable.Range(0, classes)
                             .Select(
                                 _ => new int[classes])
                             .ToArray();
        for (int i = 0; i < images.Count; i++)
            counts[images[i].label][Prediction(passes[i].scores)]++;
        return counts;
    }
    public static List<string> ConfusionLines(int[][] counts) {
        List<string> lines = new();
        int classes = counts.Length;
        for (int k = 0; k < classes; k++) {
            List<string> values = new();
            foreach (int value in counts[k])
                values.Add(Convert.ToString(value));
            lines.Add(k + ": " + string.Join(" ", values));
        }
        for (int k = 0; k < classes; k++) {
            int support = 0, predicted = 0;
            for (int j = 0; j < classes; j++) {
                support += counts[k][j];
                predicted += counts[j][k];
            }
            lines.Add("class " + k + " support " + support + " predicted " + predicted + " precision " +
                      Ratio(counts[k][k], predicted) + " recall " + Ratio(counts[k][k], support) + " f1 " +
                      Ratio(2 * counts[k][k], support + predicted));
        }
        return lines;
    }
    public static List<string> Maps(int[][] levels, int width, int height) {
        List<string> lines = new();
        for (int r = 0; r < height; r++) {
            List<string> cells = new();
            foreach (int[] level in levels) {
                StringBuilder row = new StringBuilder();
                for (int c = 0; c < width; c++)
                    row.Append(level[r * width + c]);
                cells.Add(row.ToString());
            }
            lines.Add(string.Join(" ", cells));
        }
        return lines;
    }
    public static List<string> Image(Dataset.Image image, int width, int height) {
        List<string> lines = new();
        for (int r = 0; r < height; r++) {
            StringBuilder row = new StringBuilder();
            for (int c = 0; c < width; c++)
                row.Append(image.pixels[r * width + c] == '1' ? '#' : '.');
            lines.Add(row.ToString());
        }
        return lines;
    }
}
