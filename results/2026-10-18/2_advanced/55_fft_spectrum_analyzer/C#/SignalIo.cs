using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class SignalIo {
    public sealed class Params {
        public Dictionary<string, string[]> values = new();
        public int Integer(string key, int i) {
            return int.Parse(values[key][i]);
        }
        public int Integer(string key) {
            return Integer(key, 0);
        }
        public double Get(string key, int i) {
            return double.Parse(values[key][i]);
        }
        public double Get(string key) {
            return Get(key, 0);
        }
        public string Word(string key, int i) {
            return values[key][i];
        }
        public string Word(string key) {
            return Word(key, 0);
        }
        public double[] Row(string key) {
            string[] w = values[key];
            double[] result = new double[w.Length];
            for (int i = 0; i < w.Length; i++)
                result[i] = double.Parse(w[i]);
            return result;
        }
    }
    public record Data(int fs, double[] first, double[] second, Params settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Data Read() {
        List<string> input = Lines("signal.csv");
        string[] header = input[0].Split(',');
        int fs = int.Parse(header[0]), n = int.Parse(header[1]);
        double[] first = new double[n], second = new double[n];
        for (int i = 0; i < n; i++) {
            string[] w = input[i + 1].Split(',');
            first[i] = double.Parse(w[0]);
            second[i] = double.Parse(w[1]);
        }
        Params settings = new Params();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            settings.values[w[0]] = w.Skip(1).Take(w.Length - (1)).ToArray();
        }
        return new Data(fs, first, second, settings);
    }
}
