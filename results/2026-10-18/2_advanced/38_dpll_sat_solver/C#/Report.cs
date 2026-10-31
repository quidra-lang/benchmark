using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Numbers(List<int> values) {
        if (values.Count == 0)
            return "-";
        List<string> text = new();
        foreach (int value in values)
            text.Add(Convert.ToString(value));
        return string.Join(",", text);
    }
    public static string Numbers(int[] values) {
        List<int> list = new();
        foreach (int value in values)
            list.Add(value);
        return Numbers(list);
    }
    public static string Frequency(List<int> values) {
        SortedDictionary<int, int> counts = new();
        foreach (int value in values)
            counts[value] = counts.GetValueOrDefault(value) + 1;
        List<string> text = new();
        foreach (KeyValuePair<int, int> entry in counts)
            text.Add(entry.Key + ":" + entry.Value);
        return text.Count == 0 ? "-" : string.Join(",", text);
    }
    public static List<string> Board(int[] positions) {
        List<string> rows = new();
        foreach (int column in positions) {
            char[] row = new char[positions.Length];
            Array.Fill(row, '.');
            row[column - 1] = 'Q';
            rows.Add(new string(row));
        }
        return rows;
    }
    public static string Search(Dpll.Stats stats) {
        return "decisions=" + stats.decisions + " propagations=" + stats.propagations +
               " conflicts=" + stats.conflicts + " max_depth=" + stats.maxDepth;
    }
    public static void Paragraph(List<string> output, List<string> lines) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(lines);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
