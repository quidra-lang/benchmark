using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Globalization;
using System.Collections.Generic;

static class Report
{
    public static string Real(double value)
    {
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text == "-0.0000" ? "0.0000" : text;
    }
    public static string PValue(long numerator, long denominator)
    {
        var fraction = Tests.ReducedFraction(numerator, denominator);
        return $"{fraction.Numerator}/{fraction.Denominator} {Real((double)fraction.Numerator / fraction.Denominator)}";
    }
    public static string NumberList(List<int> numbers) => numbers.Count == 0 ? "none" : string.Join(" ", numbers.OrderBy(value => value));
    public static int BinNumber(double value, double low, double high, int bins) => Math.Min((int)Math.Floor(bins * (value - low) / (high - low)), bins - 1) + 1;
    public static string Bar(int count, int top) => new('#', (40 * count + top - 1) / top);
    public static void WriteFiles(Dictionary<string, List<string>> files)
    {
        Directory.CreateDirectory("output");
        foreach (var file in files) File.WriteAllText(Path.Combine("output", file.Key), string.Join("\n", file.Value) + "\n", new UTF8Encoding(false));
    }
}
