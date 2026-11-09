using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Decimal(int p, int q) {
        int n = (2 * p * 10000 + q) / (2 * q);
        return n / 10000 + "." + (n % 10000).ToString("D4", CultureInfo.InvariantCulture);
    }
    public static string Percentage(int p, int q) {
        if (q == 0)
            return "-";
        int n = (2 * p * 10000 + q) / (2 * q);
        return n / 100 + "." + (n % 100).ToString("D2", CultureInfo.InvariantCulture);
    }
    public static string Fraction(int p, int q) {
        int a = p, b = q;
        while (b != 0) {
            int t = a % b;
            a = b;
            b = t;
        }
        return p / a + "/" + q / a;
    }
    public static string Hex(int value) => value.ToString("x8", CultureInfo.InvariantCulture);
    public static string Register(int value) => value < 0 ? "-" : "r" + value;
    public static string Heading(int first, int last) {
        StringBuilder s = new("cycle" + new string(' ', 18));
        for (int c = first; c <= last; c++)
            s.Append(c % 10);
        return s.ToString();
    }
    public static string Row(int number, int pc, string kind, string cells, string annotation) {
        string identifier = number < 0 ? "-" : number.ToString(CultureInfo.InvariantCulture);
        return identifier.PadLeft(6) + " " + Hex(pc) + " " + kind.PadRight(6) + " " + cells + annotation;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static TValue GetOrAdd<TKey, TValue>(this IDictionary<TKey, TValue> values, TKey key,
                                                Func<TValue> create) {
        if (values.TryGetValue(key, out TValue value))
            return value;
        value = create();
        values.Add(key, value);
        return value;
    }
}
