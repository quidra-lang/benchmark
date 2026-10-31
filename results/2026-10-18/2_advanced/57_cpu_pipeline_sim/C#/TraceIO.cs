using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class TraceIO {
    public record Predictor(string name, string scheme, int[] parameters) {
    }
    public record Variant(string name, bool forwarding, string stage, int latency) {
    }
    public sealed class Config {
        public int btb, ras, first, last, top, interval;
        public string primaryVariant, primaryPredictor;
        public List<Predictor> predictors = new();
        public List<Variant> variants = new();
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name)).ToList();
    }
    public static int Hex(string value) {
        return System.Text.RegularExpressions.Regex.IsMatch(value, "^[0-9a-f]{8}$")
                   ? Convert.ToInt32(value, 16)
                   : -1;
    }
    public static int Register(string value) {
        return System.Text.RegularExpressions.Regex.IsMatch(value, "^r(?:[0-9]|[12][0-9]|3[01])$")
                   ? int.Parse(value.Substring(1))
                   : -1;
    }
    public static Config Read() {
        Config c = new Config();
        foreach (string line in Lines("config.txt")) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "BTB":
                c.btb = int.Parse(w[1]);
                break;
            case "RAS":
                c.ras = int.Parse(w[1]);
                break;
            case "TOP":
                c.top = int.Parse(w[1]);
                break;
            case "INTERVAL":
                c.interval = int.Parse(w[1]);
                break;
            case "PREDICTOR": {
                int[] p = new int[w.Length - 3];
                for (int i = 0; i < p.Length; i++)
                    p[i] = int.Parse(w[i + 3]);
                c.predictors.Add(new Predictor(w[1], w[2], p));
                break;
            }
            case "VARIANT":
                c.variants.Add(new Variant(w[1], w[2].Equals("ON"), w[3], int.Parse(w[4])));
                break;
            case "PRIMARY": {
                c.primaryVariant = w[1];
                c.primaryPredictor = w[2];
                break;
            }
            case "WINDOW": {
                c.first = int.Parse(w[1]);
                c.last = int.Parse(w[2]);
                break;
            }
            }
        }
        return c;
    }
}
