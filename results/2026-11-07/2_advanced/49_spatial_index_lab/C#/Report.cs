using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Repeat(this string text, int count) => string.Concat(Enumerable.Repeat(text, count));
    public static string Fraction(long a, long b) {
        long x = a, y = b;
        while (y != 0) {
            long rest = x % y;
            x = y;
            y = rest;
        }
        return a / x + "/" + b / x;
    }
    public static string Ids(List<Dataset.Obj> objects) {
        if (objects.Count == 0)
            return "-";
        List<string> words = new();
        foreach (Dataset.Obj obj in objects)
            words.Add(Convert.ToString(obj.id));
        return string.Join(" ", words);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
