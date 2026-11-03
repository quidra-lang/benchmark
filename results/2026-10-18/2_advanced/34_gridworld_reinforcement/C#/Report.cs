using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Fixed(long value) {
        long n = Math.Abs(value);
        return (value < 0 ? "-" : "") + (n / 10000) + "." +
               (n % 10000).ToString("D4", CultureInfo.InvariantCulture);
    }
    public static string Average(long total, long count) {
        return Fixed(DynamicProgramming.Floor(total * 10000, count));
    }
    public static string Cell(Environment world, int x) {
        return (x / world.width) + "," + (x % world.width);
    }
    public static List<string> Grid(Environment world, bool separated, Func<int, string> content) {
        List<string> output = new();
        for (int r = 0; r < world.height; r++) {
            List<string> row = new();
            for (int c = 0; c < world.width; c++) {
                int x = r * world.width + c;
                row.Add(world.cells[x] == '#' || world.Terminal(x) ? Convert.ToString(world.cells[x])
                                                                   : content(x));
            }
            output.Add(string.Join(separated ? " " : "", row));
        }
        return output;
    }
    public static void QRows(List<string> output, string method, Environment world, long[][] values,
                             long[][] visits) {
        foreach (int x in world.states)
            for (int a = 0; a < 4; a++)
                output.Add(method + "," + Cell(world, x) + "," + "NESW"[a] + "," + Fixed(values[x][a]) + "," +
                           (visits == null ? "-" : visits[x][a].ToString(CultureInfo.InvariantCulture)));
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
