using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

public static class Report {
    public record MapImage(int[] counts, List<string> lines);
    public static string Real(double value, int places) {
        string s = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return s == "-0." + new string('0', places) ? s[1..] : s;
    }
    public static string Time(int ms) => ms / 1000 + "." +
                                         (ms % 1000).ToString("D3", CultureInfo.InvariantCulture);
    public static List<string> Field(Mesh m, double[] x) {
        List<string> lines = new();
        for (int r = 0; r < m.height; r++) {
            List<string> values = new();
            for (int c = 0; c < m.width; c++)
                values.Add(Real(x[m.Cell(r, c)], 2));
            lines.Add(string.Join(" ", values));
        }
        return lines;
    }
    public static MapImage Isotherm(Mesh m, double[] x, double[] bands) {
        int hottest = 0;
        for (int p = 1; p < x.Length; p++)
            if (x[p] > x[hottest])
                hottest = p;
        int[] counts = new int[bands.Length + 1];
        char[] cells = new char[x.Length];
        for (int p = 0; p < x.Length; p++) {
            int digit = 0;
            foreach (double band in bands)
                if (band <= x[p])
                    digit++;
            counts[digit]++;
            cells[p] = p == hottest ? '*' : (char)('0' + digit);
        }
        List<string> lines = new();
        for (int r = 0; r < m.height; r++)
            lines.Add(new string(cells, r * m.width, m.width));
        return new MapImage(counts, lines);
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
}
