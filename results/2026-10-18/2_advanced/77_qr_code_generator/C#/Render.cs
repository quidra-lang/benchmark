using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class Render {
    public static List<string> SymbolLines(int[][] symbol) {
        List<string> lines = new();
        foreach (int[] row in symbol) {
            StringBuilder line = new StringBuilder();
            foreach (int value in row)
                line.Append(value == 1 ? '#' : '.');
            lines.Add(line.ToString());
        }
        return lines;
    }
    public static string PbmText(int[][] symbol, int quiet, int scale) {
        int size = symbol.Length, width = (size + 2 * quiet) * scale;
        StringBuilder result = new StringBuilder("P1\n" + width + " " + width + "\n");
        for (int y = 0; y < width; y++) {
            for (int x = 0; x < width; x++) {
                int mx = x / scale - quiet, my = y / scale - quiet;
                result.Append(mx >= 0 && mx < size && my >= 0 && my < size ? symbol[my][mx] : 0);
            }
            result.Append('\n');
        }
        return result.ToString();
    }
}
