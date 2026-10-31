using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class SeriesData {
    public readonly string name;
    public readonly List<string> periods = new();
    public readonly List<int> raw = new();
    public readonly Dictionary<string, string> events = new();
    public int onHand, lead, review;
    public double service;
    public SeriesData(string name) {
        this.name = name;
    }
}
sealed class SeriesIo {
    public readonly List<SeriesData> series = new();
    public readonly Dictionary<string, string[]> settings = new();
    public SeriesIo() {
        Dictionary<string, SeriesData> named = new();
        List<string> lines = Read("series.csv");
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] fields = line.Split(",");
            named.TryGetValue(fields[0], out SeriesData data);
            if (data == null) {
                data = new SeriesData(fields[0]);
                named[fields[0]] = data;
                series.Add(data);
            }
            data.periods.Add(fields[1]);
            data.raw.Add(fields[2].Equals("NA") ? -1 : int.Parse(fields[2]));
        }
        lines = Read("events.csv");
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] fields = line.Split(",");
            named[fields[0]].events[fields[1]] = fields[2];
        }
        lines = Read("inventory.csv");
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] fields = line.Split(",");
            SeriesData data = named[fields[0]];
            data.onHand = int.Parse(fields[1]);
            data.lead = int.Parse(fields[2]);
            data.review = int.Parse(fields[3]);
            data.service = double.Parse(fields[4], CultureInfo.InvariantCulture);
        }
        foreach (string line in Read("params.txt")) {
            string[] fields = line.Split(" ");
            settings[fields[0]] = fields[1..fields.Length];
        }
    }
    public int Integer(string key) {
        return int.Parse(settings[key][0]);
    }
    public double Number(string key) {
        return double.Parse(settings[key][0], CultureInfo.InvariantCulture);
    }
    public double[] Candidates(string key) {
        string[] values = settings[key];
        double[] result = new double[values.Length];
        for (int i = 0; i < values.Length; i++)
            result[i] = double.Parse(values[i], CultureInfo.InvariantCulture);
        return result;
    }
    public static List<string> Read(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static string NextMonth(string period) {
        string[] fields = period.Split('-');
        int year = int.Parse(fields[0]), month = int.Parse(fields[1]);
        if (month == 12) {
            year++;
            month = 1;
        } else
            month++;
        return year.ToString("D4", CultureInfo.InvariantCulture) + "-" +
               month.ToString("D2", CultureInfo.InvariantCulture);
    }
    public static string Real(double value) {
        if (double.IsNaN(value))
            return "NA";
        string text = value.ToString("F4", CultureInfo.InvariantCulture);
        return text.Equals("-0.0000") ? "0.0000" : text;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
