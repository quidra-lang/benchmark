using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Report {
    public static string Repeat(this string text, int count) => string.Concat(Enumerable.Repeat(text, count));
    public static string F(double value) {
        double result = Math.Round(value, 4, MidpointRounding.AwayFromZero);
        if (result == 0)
            result = 0;
        return result.ToString("F4", CultureInfo.InvariantCulture);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static List<string> Shades(Spectral.Frames frames, int fs, int length, int band) {
        List<string> output = new();
        string characters = " .:-=+*#%@";
        for (int k = length / 2; k >= 0; k--) {
            string frequency = F((double)k * fs / length),
                   line = " ".Repeat(Math.Max(0, 9 - frequency.Length)) + frequency + " |";
            foreach (double[] frame in frames.magnitude) {
                double db = 20 * Math.Log10(frame[k] / frames.maximum);
                int level = Math.Max(0, 9 - (int)Math.Floor(-db / band));
                line += characters[level];
            }
            output.Add(line + "|");
        }
        return output;
    }
}
