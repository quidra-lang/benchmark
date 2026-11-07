using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Real(double value) {
        if (double.IsNaN(value))
            return "-";
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text.Equals("-0.0000") ? "0.0000" : text;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
