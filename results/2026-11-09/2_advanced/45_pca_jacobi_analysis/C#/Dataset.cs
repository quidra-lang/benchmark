using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Row(string id, double[] values) {
    }
    public record Table(List<string> names, List<Row> rows) {
    }
    public sealed class Settings {
        public Dictionary<string, string[]> values = new();
        public string Text(string key) {
            return values[key][0];
        }
        public int Integer(string key) {
            return int.Parse(Text(key));
        }
        public double Number(string key) {
            return double.Parse(Text(key));
        }
        public int Second(string key) {
            return int.Parse(values[key][1]);
        }
    }
    public record Data(Table data, Table supplementary, Settings settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Table ReadTable(string name) {
        List<string> lines = Lines(name);
        List<string> names = new(lines[0].Split(',').ToList());
        names.RemoveAt(0);
        List<Row> rows = new();
        for (int i = 1; i < lines.Count; i++) {
            string[] words = lines[i].Split(',');
            double[] values = new double[names.Count];
            for (int j = 0; j < values.Length; j++)
                values[j] = words[j + 1].Equals("NA") ? double.NaN : double.Parse(words[j + 1]);
            rows.Add(new Row(words[0], values));
        }
        return new Table(names, rows);
    }
    public static Data Read() {
        Settings settings = new Settings();
        foreach (string line in Lines("params.txt")) {
            string[] words = line.Split(' ');
            settings.values[words[0]] = words[1..words.Length];
        }
        return new Data(ReadTable("data.csv"), ReadTable("supplementary.csv"), settings);
    }
}
