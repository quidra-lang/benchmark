using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

static class Report
{
    public static string DecimalText(Rational value, int digits)
    {
        long scale = 1;
        for (int i = 0; i < digits; i++) scale *= 10;
        long scaled = (2 * scale * Math.Abs(value.numerator) + value.denominator) / (2 * value.denominator);
        string fraction = (scaled % scale).ToString(CultureInfo.InvariantCulture).PadLeft(digits, '0');
        return (value.numerator < 0 && scaled > 0 ? "-" : "") + (scaled / scale).ToString(CultureInfo.InvariantCulture) + "." + fraction;
    }
    public static string hullArea(long doubled) => doubled / 2 + "." + (doubled % 2 == 0 ? "0" : "5");
    public static void write(Dictionary<string, List<string>> files)
    {
        Directory.CreateDirectory("output");
        foreach (var entry in files) File.WriteAllText(Path.Combine("output", entry.Key), string.Join("\n", entry.Value) + "\n", Encoding.ASCII);
    }
}
