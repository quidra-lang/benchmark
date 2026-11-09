using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataframe {
    public record Row(int number, Dictionary<string, string> values) {
        public double Numeric(string name) {
            string value = values[name];
            return value == null ? double.NaN : double.Parse(value);
        }
    }
    public sealed class Frame {
        public List<string> columns;
        public List<Row> rows = new();
    }
    public sealed class Settings {
        public Dictionary<string, string[]> values = new();
        public double Number(string key) {
            return double.Parse(values[key][0]);
        }
        public int Integer(string key) {
            return int.Parse(values[key][0]);
        }
        public int Width() {
            return int.Parse(values["PLOT"][0]);
        }
        public int Height() {
            return int.Parse(values["PLOT"][1]);
        }
        public double Limit() {
            return double.Parse(values["PLOT"][2]);
        }
    }
    public record Data(Frame frame, Frame predictions, HashSet<string> categorical, List<string> models,
                       Settings settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Frame ReadFrame(string name) {
        List<string> lines = Lines(name);
        Frame f = new Frame();
        f.columns = new(lines[0].Split(',').ToList());
        for (int i = 1; i < lines.Count; i++) {
            string[] words = lines[i].Split(',');
            Dictionary<string, string> values = new();
            for (int j = 0; j < words.Length; j++)
                values[f.columns[j]] = words[j].Equals("NA") ? null : words[j];
            f.rows.Add(new Row(i, values));
        }
        return f;
    }
    public static Data Read() {
        Frame frame = ReadFrame("data.csv");
        HashSet<string> categorical = new();
        foreach (string column in frame.columns)
            foreach (Row row in frame.rows) {
                string value = row.values[column];
                if (value != null && value[0] >= 'A' && value[0] <= 'Z')
                    categorical.Add(column);
            }
        Settings s = new Settings();
        foreach (string line in Lines("params.txt")) {
            string[] words = line.Split(' ');
            s.values[words[0]] = words[1..words.Length];
        }
        return new Data(frame, ReadFrame("predict.csv"), categorical, Lines("model.txt"), s);
    }
}
