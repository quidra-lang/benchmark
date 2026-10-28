using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Report {
    public static long Gcd(long a, long b) {
        a = Math.Abs(a);
        while (b != 0) {
            long old = b;
            b = a % b;
            a = old;
        }
        return a;
    }
    public static string Fraction(long numerator, long denominator) {
        long divisor = Gcd(numerator, denominator);
        return numerator / divisor + "/" + denominator / divisor;
    }
    public static string Root(int value) {
        return value == Optics.INF ? "-" : Math.Sqrt(value).ToString("F3", CultureInfo.InvariantCulture);
    }
    public static string Ari(long numerator, long denominator) {
        string value = ((double)numerator / denominator).ToString("F4", CultureInfo.InvariantCulture);
        if (value.Equals("-0.0000"))
            value = "0.0000";
        return Fraction(numerator, denominator) + " " + value;
    }
    public static List<string> Framed(List<string> rows, int width) {
        string border = "+" + new string('-', width) + "+";
        List<string> lines = new();
        lines.Add(border);
        foreach (string row in rows)
            lines.Add("|" + row + "|");
        lines.Add(border);
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
