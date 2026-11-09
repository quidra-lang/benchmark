using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

public static class Report {
    public static string F(double value, int places) {
        string s = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return s.StartsWith("-", StringComparison.Ordinal) &&
                       double.Parse(s, CultureInfo.InvariantCulture) == 0
                   ? s[1..]
                   : s;
    }
    public static List<string> Plot(int[] observed, double[] fitted) {
        int n = observed.Length, maximum = observed.Max(),
            width = maximum.ToString(CultureInfo.InvariantCulture).Length;
        char[][] grid = Enumerable.Range(0, 20)
                            .Select(
                                _ => Enumerable.Repeat('.', 70).ToArray())
                            .ToArray();
        for (int x = 0; x < 70; x++) {
            int day = x * (n - 1) / 69, oy = Math.Min(19, 20 * observed[day] / maximum),
                fy = Math.Min(19, (int)Math.Floor(20 * fitted[day] / maximum));
            grid[oy][x] = 'o';
            grid[fy][x] = oy == fy ? '#' : '*';
        }
        List<string> lines = new() { "plot observed o fitted * both # days 1 " + n + " max " + maximum };
        for (int y = 19; y >= 0; y--)
            lines.Add((maximum * y / 20).ToString(CultureInfo.InvariantCulture).PadLeft(width) + " |" +
                      new string(grid[y]));
        StringBuilder ticks = new();
        for (int x = 0; x < 70; x++)
            ticks.Append(x % 10 == 0 ? '+' : '-');
        lines.Add(new string(' ', width + 1) + "+" + ticks);
        char[] labels = Enumerable.Repeat(' ', 70).ToArray();
        for (int x = 0; x <= 60; x += 10) {
            string label = (1 + x * (n - 1) / 69).ToString(CultureInfo.InvariantCulture);
            for (int i = 0; i < label.Length; i++)
                labels[x + i] = label[i];
        }
        lines.Add((new string(' ', width + 2) + new string(labels)).TrimEnd(' '));
        return lines;
    }
}
