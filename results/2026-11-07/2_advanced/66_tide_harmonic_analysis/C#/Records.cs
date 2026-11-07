using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
public static class Records {
    public record Constituent(string name, double speed) {}
    public sealed class Station {
        public string code, name;
        public int rows;
        public SortedDictionary<int, int?> values = new();
        public Station(string code, string name) {
            this.code = code;
            this.name = name;
        }
    }
    public sealed class Settings {
        public DateTime epoch, start;
        public int ts;
        public Dictionary<string, List<string>> values = new();
        public int Integer(string key, int index) => int.Parse(values[key][index]);
        public double Real(string key, int index) => double.Parse(values[key][index],
                                                                  CultureInfo.InvariantCulture);
        public string Text(string key, int index) => values[key][index];
    }
    public record Data(Settings settings, List<Station> stations, List<Constituent> constituents) {}
    public static DateTime Parse(string text) => DateTime.ParseExact(text, "yyyy-MM-dd HH:mm",
                                                                     CultureInfo.InvariantCulture,
                                                                     DateTimeStyles.None);
    public static int Hours(DateTime epoch, DateTime value) => (int)(value - epoch).TotalHours;
    public static string Hour(Settings s,
                              int t) => s.epoch.AddHours(t).ToString("yyyy-MM-dd HH:mm",
                                                                     CultureInfo.InvariantCulture);
    public static string Minute(Settings s, int m) =>
        s.epoch.AddMinutes(m).ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
    public static DateOnly DateOf(DateTime value) => DateOnly.FromDateTime(value);
    public static DateOnly DateHour(Settings s, int t) => DateOf(s.epoch.AddHours(t));
    public static DateOnly DateMinute(Settings s, int m) => DateOf(s.epoch.AddMinutes(m));
    public static int Noon(Settings s,
                           DateOnly date) => Hours(s.epoch, date.ToDateTime(new TimeOnly(12, 0)));
    public static int Days(DateOnly first, DateOnly last) => last.DayNumber - first.DayNumber;
    public static string DateText(DateOnly date) => date.ToString("yyyy-MM-dd",
                                                                  CultureInfo.InvariantCulture);
    public static Data Read() {
        Settings s = new();
        List<Station> stations = new();
        string[] lines = File.ReadAllLines(Path.Combine("input", "params.txt"));
        s.epoch = Parse(lines[0][6..]);
        for (int i = 1; i < lines.Length; i++) {
            string line = lines[i];
            string[] w = line.Split(' ');
            if (w[0] == "station")
                stations.Add(new Station(w[1], line[12..]));
            else
                s.values[w[0]] = w.Skip(1).ToList();
        }
        s.start = Parse(s.Text("predict", 0) + " " + s.Text("predict", 1));
        s.ts = Hours(s.epoch, s.start);
        List<Constituent> constituents = new();
        lines = File.ReadAllLines(Path.Combine("input", "constituents.txt"));
        for (int i = 1; i < lines.Length; i++) {
            string[] w = lines[i].Split(' ');
            constituents.Add(
                new Constituent(w[0], double.Parse(w[1], CultureInfo.InvariantCulture)));
        }
        lines = File.ReadAllLines(Path.Combine("input", "observations.csv"));
        for (int i = 1; i < lines.Length; i++) {
            string[] w = lines[i].Split(',');
            Station station = stations.First(x => x.code == w[0]);
            int t = Hours(s.epoch, Parse(w[1]));
            station.values[t] = w[2] == "NA" ? null : int.Parse(w[2].Replace(".", ""));
            station.rows++;
        }
        return new Data(s, stations, constituents);
    }
}
