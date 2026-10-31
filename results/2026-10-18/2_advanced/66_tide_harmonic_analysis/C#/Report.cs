using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Report {
    public static string F(double value, int places) {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text.StartsWith("-", StringComparison.Ordinal) &&
                       double.Parse(text, CultureInfo.InvariantCulture) == 0
                   ? text[1..]
                   : text;
    }
    public static string Optional(double? value,
                                  int places) => value.HasValue ? F(value.Value, places) : "none";
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static List<string> Plot(char[][] cells, string[] labels) {
        int width = labels.Max(x => x.Length);
        List<string> lines = new();
        for (int q = 0; q < cells.Length; q++)
            lines.Add(labels[q].PadLeft(width) + " |" + new string(cells[q]) + "|");
        StringBuilder axis = new(new string(' ', width) + " +");
        for (int c = 0; c < cells[0].Length; c++)
            axis.Append(c % 6 == 0 ? '+' : '-');
        axis.Append('+');
        lines.Add(axis.ToString());
        return lines;
    }
}
