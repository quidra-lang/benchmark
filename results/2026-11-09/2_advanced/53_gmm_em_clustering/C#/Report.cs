using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Report {
    public static string Decimal(double value, int digits) {
        if (double.IsNaN(value))
            return "-";
        double result = Math.Round(value, digits, MidpointRounding.AwayFromZero);
        if (result == 0)
            result = 0;
        return result.ToString("F" + digits, CultureInfo.InvariantCulture);
    }
    public static string F(double value) => Decimal(value, 4);
    public static double Rounded(double value) => Math.Round(value, 4, MidpointRounding.AwayFromZero);
    public static List<string> Frame(char[][] map) {
        string edge = "+" + new string('-', map[0].Length) + "+";
        List<string> output = new() { edge };
        foreach (char[] row in map)
            output.Add("|" + new string(row) + "|");
        output.Add(edge);
        return output;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
