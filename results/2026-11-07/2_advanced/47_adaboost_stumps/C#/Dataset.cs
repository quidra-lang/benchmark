using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Row(string id, double[] x, int label) {
    }
    public record Table(List<string> names, List<Row> rows) {
    }
    public sealed class Settings {
        public Dictionary<string, string[]> values = new();
        public int Integer(string key) {
            return int.Parse(values[key][0]);
        }
        public double Number(string key) {
            return double.Parse(values[key][0]);
        }
        public int[] Integers(string key) {
            string[] words = values[key];
            int[] result = new int[words.Length];
            for (int i = 0; i < result.Length; i++)
                result[i] = int.Parse(words[i]);
            return result;
        }
        public double[] Numbers(string key) {
            string[] words = values[key];
            double[] result = new double[words.Length];
            for (int i = 0; i < result.Length; i++)
                result[i] = double.Parse(words[i]);
            return result;
        }
        public List<string> Variants() {
            return values["VARIANTS"].ToList();
        }
    }
    public record Data(Table train, Table test, Table multiTrain, Table multiTest, Settings settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Table Table(List<string> lines, bool multi, string role) {
        string[] header = lines[0].Split(',');
        int count = header.Length - (multi ? 3 : 2);
        List<string> names = new(header.ToList().GetRange(1, count + 1 - (1)));
        List<Row> rows = new();
        for (int i = 1; i < lines.Count; i++) {
            string[] words = lines[i].Split(',');
            if (multi && !words[words.Length - 1].Equals(role))
                continue;
            double[] x = new double[count];
            for (int j = 0; j < count; j++)
                x[j] = double.Parse(words[j + 1]);
            rows.Add(new Row(words[0], x, int.Parse(words[count + 1])));
        }
        return new Table(names, rows);
    }
    public static Data Read() {
        Settings s = new Settings();
        foreach (string line in Lines("params.txt")) {
            string[] words = line.Split(' ');
            s.values[words[0]] = words[1..words.Length];
        }
        List<string> multi = Lines("multiclass.csv");
        return new Data(Table(Lines("train.csv"), false, ""), Table(Lines("test.csv"), false, ""),
                        Table(multi, true, "train"), Table(multi, true, "test"), s);
    }
}
