using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Plot {
    public static string Repeat(this string s, int count) => string.Concat(Enumerable.Repeat(s, count));
    public record Cell(int row, int col) {
    }
    public static char[][] Grid(int rows, int cols) {
        char[][] grid = Enumerable.Range(0, rows)
                            .Select(
                                _ => new char[cols])
                            .ToArray();
        foreach (char[] row in grid)
            Array.Fill(row, ' ');
        return grid;
    }
    public static List<string> Framed(char[][] grid) {
        string border = "+" + "-".Repeat(grid[0].Length) + "+";
        List<string> output = new();
        output.Add(border);
        foreach (char[] row in grid)
            output.Add("|" + new string(row) + "|");
        output.Add(border);
        return output;
    }
    public static int Index(double fraction, int size) {
        return Math.Min((int)Math.Floor(fraction * size), size - 1);
    }
    public static int Rounded(double fraction, int size) {
        return (int)Math.Floor(fraction * size + 0.5);
    }
    public static Cell Biplot(double x, double y, double mx, double my, int width, int height) {
        return new Cell(Index((my - y) / (2 * my), height), Index((x + mx) / (2 * mx), width));
    }
    public static Cell Circle(double first, double second, int radius) {
        return new Cell(radius / 2 + 1 - Rounded(second, radius / 2), radius + 1 + Rounded(first, radius));
    }
    public static Cell Diagnostic(double t2, double spe, double xmax, double ymax, int width, int height) {
        return new Cell(height - 1 - Index(spe / ymax, height), Index(t2 / xmax, width));
    }
    public static List<Cell> Shaft(Cell origin, Cell tip) {
        int dr = tip.row - origin.row, dc = tip.col - origin.col,
            steps = Math.Max(Math.Abs(dc), Math.Abs(dr));
        List<Cell> result = new();
        for (int s = 1; s < steps; s++)
            result.Add(new Cell(origin.row + Math.Sign(dr) * ((2 * s * Math.Abs(dr) + steps) / (2 * steps)),
                                origin.col + Math.Sign(dc) * ((2 * s * Math.Abs(dc) + steps) / (2 * steps))));
        return result;
    }
    public static char ShaftCharacter(Cell origin, Cell tip) {
        int dr = tip.row - origin.row, dc = tip.col - origin.col;
        return 2 * Math.Abs(dr) <= Math.Abs(dc)   ? '-'
               : 2 * Math.Abs(dc) <= Math.Abs(dr) ? '|'
               : dc * dr < 0                      ? '/'
                                                  : '\\';
    }
    public static string Scree(int length, int kaiser, int broken, int width) {
        string line = "|";
        for (int p = 1; p <= width; p++)
            line += p == broken ? 'o' : p == kaiser ? ':' : p <= length ? '#' : ' ';
        return line + "|";
    }
}
