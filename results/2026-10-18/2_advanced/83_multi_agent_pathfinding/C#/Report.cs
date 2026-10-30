using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
public static class Report {
    public static string CellText(GridMap.Cell cell) => cell.x + "," + cell.y;
    public static char Name(int number) => (char)('A' + number);
    public static string Actions(List<GridMap.Cell> path) {
        StringBuilder result = new();
        for (int i = 1; i < path.Count; i++) {
            int dx = path[i].x - path[i - 1].x, dy = path[i].y - path[i - 1].y;
            result.Append(dx == 1 ? 'E' : dx == -1 ? 'W' : dy == 1 ? 'S' : dy == -1 ? 'N' : '.');
        }
        return result.ToString();
    }
    public static string Conflict(Cbs.Conflict c) {
        string start = c.kind + " t " + c.time + " " + Name(c.a) + " " + Name(c.b);
        return c.kind == "vertex" ? start + " at " + c.v : start + " from " + c.u + " to " + c.v;
    }
    public static string Fraction(int numerator, int denominator) {
        int a = numerator, b = denominator;
        while (b != 0) {
            int r = a % b;
            a = b;
            b = r;
        }
        return numerator / a + "/" + denominator / a;
    }
    public static string Csv(List<string> values) => string.Join(",", values);
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n",
                          Encoding.ASCII);
    }
}
