using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Plot {
    public static string Real(double value) {
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text.Equals("-0.0000") ? "0.0000" : text;
    }
    public static string Reals(double[] values) {
        List<string> result = new();
        foreach (double v in values)
            result.Add(Real(v));
        return string.Join(" ", result);
    }
    public static string Fraction(Evaluation.Fraction f) {
        return f == null ? "-" : f.n + "/" + f.d + " " + Real((double)f.n / f.d);
    }
    public static string Ratio(long n, long d) {
        return Fraction(Evaluation.ReducedFraction(n, d));
    }
    public static List<string> Frame(char[][] grid) {
        string border = "+" + "-".Repeat(grid[0].Length) + "+";
        List<string> lines = new();
        lines.Add(border);
        foreach (char[] row in grid)
            lines.Add("|" + new string(row) + "|");
        lines.Add(border);
        return lines;
    }
    public static char[][] Grid(int width, int height) {
        char[][] result = Enumerable.Range(0, height)
                              .Select(
                                  _ => new char[width])
                              .ToArray();
        foreach (char[] row in result)
            Array.Fill(row, ' ');
        return result;
    }
    public static int Cell(double value, double lo, double hi, int size) {
        return (int)Math.Floor((value - lo) / (hi - lo) * (size - 1) + 0.5);
    }
    public static void Place(char[][] grid, int col, int row, char letter) {
        char previous = grid[row][col];
        grid[row][col] = previous == ' ' || previous == letter ? letter : '*';
    }
    public static void Section(List<string> output, List<string> part) {
        if (output.Count != 0)
            output.Add("");
        output.AddRange(part);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
