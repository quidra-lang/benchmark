using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class ConfigIo {
    public record Scenario(string name, string protocol, string l1, string l2, int order);
    public record Region(string name, int start, int end);
    public sealed class Config {
        public int cores, line, l1Size, l1Ways, l1Sets, l2Size, l2Ways, l2Sets, t1, t2, tm, tb,
            interval, top, cap;
        public string primary;
        public List<Scenario> scenarios = new();
        public List<Region> regions = new();
        public List<int> watch = new();
    }
    public static bool DecimalInteger(string text, int maximum) {
        if (text.Length == 0 || maximum > 0 && text.Length > maximum ||
            text.Length > 1 && text[0] == '0')
            return false;
        foreach (char c in text)
            if (c < '0' || c > '9')
                return false;
        return true;
    }
    public static bool ValidHexAddress(string text) {
        if (text.Length != 8)
            return false;
        foreach (char c in text)
            if ("0123456789abcdef".IndexOf(c) < 0)
                return false;
        return true;
    }
    public static string HexAddress(int value) => value.ToString("x8",
                                                                 CultureInfo.InvariantCulture);
    public static Config ReadConfig() {
        Config c = new();
        foreach (string line in File.ReadAllLines("input/config.txt", Encoding.ASCII)) {
            string[] f = line.Split(' ');
            switch (f[0]) {
            case "CORES":
                c.cores = int.Parse(f[1]);
                break;
            case "LINE":
                c.line = int.Parse(f[1]);
                break;
            case "L1":
                c.l1Size = int.Parse(f[1]);
                c.l1Ways = int.Parse(f[2]);
                break;
            case "L2":
                c.l2Size = int.Parse(f[1]);
                c.l2Ways = int.Parse(f[2]);
                break;
            case "LATENCY":
                c.t1 = int.Parse(f[1]);
                c.t2 = int.Parse(f[2]);
                c.tm = int.Parse(f[3]);
                c.tb = int.Parse(f[4]);
                break;
            case "SCENARIO":
                c.scenarios.Add(new(f[1], f[2], f[3], f[4], c.scenarios.Count));
                break;
            case "PRIMARY":
                c.primary = f[1];
                break;
            case "INTERVAL":
                c.interval = int.Parse(f[1]);
                break;
            case "TOP":
                c.top = int.Parse(f[1]);
                break;
            case "REGION":
                c.regions.Add(new(f[1], int.Parse(f[2], NumberStyles.HexNumber),
                                  int.Parse(f[3], NumberStyles.HexNumber)));
                break;
            case "WATCH":
                c.watch.Add(int.Parse(f[1], NumberStyles.HexNumber) / c.line);
                break;
            }
        }
        c.l1Sets = c.l1Size / (c.line * c.l1Ways);
        c.l2Sets = c.l2Size / (c.line * c.l2Ways);
        c.cap = c.l1Sets * c.l1Ways;
        return c;
    }
    public static List<string>
    ReadTrace() => File.ReadAllLines("input/trace.txt", Encoding.ASCII).ToList();
    public static void WriteLines(string name, List<string> lines) {
        Directory.CreateDirectory("output");
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
