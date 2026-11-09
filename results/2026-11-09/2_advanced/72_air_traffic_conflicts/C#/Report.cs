using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
public static class Report {
    public static string Decimal(double value, int digits = 3) {
        double rounded = Math.Round(value, digits, MidpointRounding.AwayFromZero);
        if (rounded == 0)
            rounded = 0;
        return rounded.ToString("F" + digits, CultureInfo.InvariantCulture);
    }
    public static string Signed(int value) => value > 0? "+" + value
        : value.ToString(CultureInfo.InvariantCulture);
    public static List<string> Chart(List<string> rows) {
        string border = "+" + new string('-', rows[0].Length) + "+";
        List<string> lines = new() { border };
        foreach (string row in rows)
            lines.Add("|" + row + "|");
        lines.Add(border);
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name),
                          string.Join("\n", lines) + (lines.Count == 0 ? "" : "\n"));
    }
}
public static class CollectionHelpers {
    public static V GetOrAdd<K, V>(this IDictionary<K, V> map, K key, Func<K, V> factory) {
        if (!map.TryGetValue(key, out V value)) {
            value = factory(key);
            map[key] = value;
        }
        return value;
    }
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int value);
        map[key] = value + amount;
    }
}
