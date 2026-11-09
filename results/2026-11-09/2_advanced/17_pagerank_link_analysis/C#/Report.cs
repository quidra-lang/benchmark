using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Report
{
    public static string fixedValue(double value, int places = 6)
    {
        string text = value.ToString("F" + places, CultureInfo.InvariantCulture);
        return text.StartsWith('-') && double.Parse(text, CultureInfo.InvariantCulture) == 0 ? text[1..] : text;
    }
    public static long scaled(double value, int places = 6) => (long) Math.Round(value * (places == 4 ? 10000 : 1000000));
    public static string fraction(long numerator, long denominator)
    {
        long first = Math.Abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        numerator /= first; denominator /= first;
        return numerator + "/" + denominator + " " + fixedValue((double) numerator / denominator, 4);
    }
    public static void write(Dictionary<string, List<string>> files)
    {
        Directory.CreateDirectory("output");
        foreach (var entry in files) File.WriteAllText(Path.Combine("output", entry.Key), string.Join("\n", entry.Value) + "\n", Encoding.ASCII);
    }
}
