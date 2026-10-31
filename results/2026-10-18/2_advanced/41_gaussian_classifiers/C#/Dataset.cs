using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public sealed class Row {
        public int id, y;
        public double[] values;
        public string label;
        public Row(int id, double[] values, string label) {
            this.id = id;
            this.values = values;
            this.label = label;
        }
    }
    public record Subset(string name, int[] features) {
    }
    public sealed class Settings {
        public string prior;
        public double epsilon, gamma, theta;
        public double[] smoothing, gammas, edges, reject;
        public int folds, resamples, seed, width, height, plotWidth, plotHeight;
        public int[] curve;
        public List<Subset> subsets = new();
        public List<int[]> pairs = new();
    }
    public sealed class Data {
        public List<string> features, classes;
        public List<Row> train, test;
        public double[][] costs;
        public Settings settings;
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static List<Row> Rows(List<string> lines) {
        List<Row> result = new();
        for (int i = 1; i < lines.Count; i++) {
            string[] w = lines[i].Split(',');
            double[] x = new double[w.Length - 2];
            for (int j = 0; j < x.Length; j++)
                x[j] = double.Parse(w[j + 1]);
            result.Add(new Row(int.Parse(w[0]), x, w[w.Length - 1]));
        }
        return result;
    }
    public static double[] Decimals(string[] w, int start) {
        double[] result = new double[w.Length - start];
        for (int i = start; i < w.Length; i++)
            result[i - start] = double.Parse(w[i]);
        return result;
    }
    public static int[] Features(string[] w, int start, List<string> names) {
        int[] result = new int[w.Length - start];
        for (int i = start; i < w.Length; i++)
            result[i - start] = names.IndexOf(w[i]);
        return result;
    }
    public static Data Read() {
        Data d = new Data();
        List<string> training = Lines("train.csv");
        string[] header = training[0].Split(',');
        d.features = new(header.Skip(1).Take(header.Length - 2).ToList());
        d.train = Rows(training);
        d.test = Rows(Lines("test.csv"));
        SortedSet<string> names = new(StringComparer.Ordinal);
        foreach (Row row in d.train)
            names.Add(row.label);
        d.classes = new(names);
        foreach (Row row in d.train)
            row.y = d.classes.IndexOf(row.label);
        foreach (Row row in d.test)
            row.y = d.classes.IndexOf(row.label);
        d.costs = Linalg.Zeros(d.classes.Count);
        List<string> costs = Lines("costs.csv");
        string[] columns = costs[0].Split(',');
        for (int i = 1; i < costs.Count; i++) {
            string[] w = costs[i].Split(',');
            int actual = d.classes.IndexOf(w[0]);
            for (int j = 1; j < w.Length; j++)
                d.costs[actual][d.classes.IndexOf(columns[j])] = double.Parse(w[j]);
        }
        Settings s = new Settings();
        d.settings = s;
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "PRIOR":
                s.prior = w[1];
                break;
            case "VAR_SMOOTHING":
                s.epsilon = double.Parse(w[1]);
                break;
            case "SMOOTHING_GRID":
                s.smoothing = Decimals(w, 1);
                break;
            case "QDA_GAMMA":
                s.gamma = double.Parse(w[1]);
                break;
            case "GAMMA_GRID":
                s.gammas = Decimals(w, 1);
                break;
            case "CV_FOLDS":
                s.folds = int.Parse(w[1]);
                break;
            case "CALIBRATION_EDGES":
                s.edges = Decimals(w, 1);
                break;
            case "REJECT_THRESHOLDS":
                s.reject = Decimals(w, 1);
                break;
            case "CURVE": {
                s.curve = new int[w.Length - 1];
                for (int j = 1; j < w.Length; j++)
                    s.curve[j - 1] = int.Parse(w[j]);
                break;
            }
            case "OUTLIER_THRESHOLD":
                s.theta = double.Parse(w[1]);
                break;
            case "BOOTSTRAP": {
                s.resamples = int.Parse(w[1]);
                s.seed = int.Parse(w[2]);
                break;
            }
            case "MAP_SIZE": {
                s.width = int.Parse(w[1]);
                s.height = int.Parse(w[2]);
                break;
            }
            case "PLOT_SIZE": {
                s.plotWidth = int.Parse(w[1]);
                s.plotHeight = int.Parse(w[2]);
                break;
            }
            case "SUBSET":
                s.subsets.Add(new Subset(w[1], Features(w, 2, d.features)));
                break;
            case "PAIR":
                s.pairs.Add(Features(w, 1, d.features));
                break;
            }
        }
        return d;
    }
}
