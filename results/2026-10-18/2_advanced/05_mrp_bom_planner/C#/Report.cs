using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

static class Report
{
    public static string Money(long cents) => cents / 100 + "." + (cents % 100).ToString().PadLeft(2, '0');
    public static long Percent(long part, long whole) => (200 * part + whole) / (2 * whole);
    public static string Table(string label, IEnumerable<long> values, int width)
    {
        StringBuilder row = new(label.PadRight(10)); foreach (long value in values) row.Append(value.ToString().PadLeft(width)); return row.ToString();
    }
    public static void Write(string name, IEnumerable<string> lines)
    {
        Directory.CreateDirectory("output"); File.WriteAllText(Path.Combine("output", name), string.Concat(lines.Select(line => line + "\n")), Encoding.ASCII);
    }
}
