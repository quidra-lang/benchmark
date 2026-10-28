using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Plot {
    public static List<string> Draw(List<List<Dataset.Subject>> groups, List<List<Estimators.Row>> tables,
                                    int width, int height, int horizon) {
        int[][] occupied = Enumerable.Range(0, height)
                               .Select(
                                   _ => new int[width])
                               .ToArray();
        for (int g = 0; g < groups.Count; g++) {
            int maximum = 0;
            foreach (Dataset.Subject s in groups[g])
                maximum = Math.Max(maximum, s.time);
            int previous = -1;
            for (int col = 0; col < width; col++) {
                int time = col * (horizon / width);
                if (time > maximum)
                    break;
                double survival = Estimators.At(tables[g], time).survival;
                int band = Math.Min(height - 1, (int)Math.Floor(survival * height));
                occupied[height - 1 - band][col] |= 1 << g;
                if (previous - 1 > band)
                    for (int q = band + 1; q < previous; q++)
                        occupied[height - 1 - q][col] |= 1 << g;
                previous = band;
            }
        }
        string border = "   +" + "-".Repeat(width) + "+";
        List<string> output = new();
        output.Add(border);
        for (int row = 0; row < height; row++) {
            int q = height - 1 - row;
            StringBuilder line = new StringBuilder(Program.Pad(Convert.ToString(100 * q / height), 3) + "|");
            foreach (int value in occupied[row])
                line.Append(value == 0 ? ' '
                            : System.Numerics.BitOperations.PopCount((uint)value) == 1
                                ? (char)('A' + System.Numerics.BitOperations.TrailingZeroCount((uint)value))
                                : '*');
            output.Add(line + "|");
        }
        output.Add(border);
        return output;
    }
}
