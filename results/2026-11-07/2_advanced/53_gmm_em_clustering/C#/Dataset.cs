using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Point(string id, double x, double y) {
    }
    public sealed class Params {
        public Dictionary<string, string[]> values = new();
        public int Integer(string key) {
            return int.Parse(values[key][0]);
        }
        public double Get(string key) {
            return double.Parse(values[key][0]);
        }
        public string[] Words(string key) {
            return values[key];
        }
        public double[] Row(string key) {
            string[] words = values[key];
            double[] result = new double[words.Length];
            for (int i = 0; i < words.Length; i++)
                result[i] = double.Parse(words[i]);
            return result;
        }
    }
    public record Data(List<Point> points, Dictionary<int, Em.Model> initial, Params settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Data Read() {
        List<Point> points = new();
        List<string> input = Lines("points.csv");
        for (int i = 1; i < input.Count; i++) {
            string[] w = input[i].Split(',');
            points.Add(new Point(w[0], double.Parse(w[1]), double.Parse(w[2])));
        }
        Dictionary<int, Em.Model> initial = new();
        input = Lines("init.txt");
        int cursor = 0;
        while (cursor < input.Count) {
            if (input[cursor].Length == 0) {
                cursor++;
                continue;
            }
            int k = int.Parse(input[cursor++].Split(' ')[1]);
            Em.Model model = new Em.Model(k);
            string[] weights = input[cursor++].Split(' ');
            for (int j = 0; j < k; j++)
                model.weights[j] = double.Parse(weights[j + 1]);
            for (int j = 0; j < k; j++) {
                string[] w = input[cursor++].Split(' ');
                model.means[j][0] = double.Parse(w[2]);
                model.means[j][1] = double.Parse(w[3]);
                for (int c = 0; c < 3; c++)
                    model.cov[j][c] = double.Parse(w[c + 4]);
            }
            initial[k] = model;
        }
        Params settings = new Params();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            settings.values[w[0]] = w.Skip(1).Take(w.Length - (1)).ToArray();
        }
        return new Data(points, initial, settings);
    }
}
