using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Report
{
    public static string real(double value)
    {
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text == "-0.0000" ? "0.0000" : text;
    }
    public static string reals(double[] values) => string.Join(" ", values.Select(real));
    public static double fourDecimal(double value) => double.Parse(real(value), CultureInfo.InvariantCulture);
    public static string amount(long cents)
    {
        long absolute = Math.Abs(cents);
        return (cents < 0 ? "-" : "") + (absolute / 100).ToString(CultureInfo.InvariantCulture) + "." + (absolute % 100).ToString("D2", CultureInfo.InvariantCulture);
    }
    public static void writeFiles(Dictionary<string, List<string>> files)
    {
        Directory.CreateDirectory("output");
        foreach (var entry in files) File.WriteAllText(Path.Combine("output", entry.Key), string.Join("\n", entry.Value) + "\n", Encoding.ASCII);
    }
}
