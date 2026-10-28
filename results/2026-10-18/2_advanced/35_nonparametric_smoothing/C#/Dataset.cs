using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Dataset {
    public sealed record Point(int x, int y);
    public sealed record Test(string name, int position);
    public sealed class Series {
        public readonly string name;
        public readonly int[] positions, hundredths;
        public readonly double[] x, y;
        public readonly int n;
        public Series(string name, int[] positions, int[] hundredths) {
            this.name = name;
            this.positions = positions;
            this.hundredths = hundredths;
            n = positions.Length;
            x = new double[n];
            y = new double[n];
            for (int i = 0; i < n; i++) {
                x[i] = positions[i] / 100.0;
                y[i] = hundredths[i] / 100.0;
            }
        }
        public Series Subset(int group, int folds) {
            List<int> selected = new();
            for (int i = 0; i < n; i++)
                if (folds == 0 ? i != group : i % folds != group)
                    selected.Add(i);
            int[] xx = new int[selected.Count], yy = new int[selected.Count];
            for (int i = 0; i < selected.Count; i++) {
                xx[i] = positions[selected[i]];
                yy[i] = hundredths[selected[i]];
            }
            return new Series(name, xx, yy);
        }
    }
    public readonly List<Series> series = new();
    public readonly List<Test> tests = new();
    public readonly Dictionary<string, string[]> settings = new();
    public static int Hundredths(string value) {
        return int.Parse(value.Replace(".", ""));
    }
    public Dataset() {
        Dictionary<string, List<Point>> groups = new();
        List<string> names = new();
        List<string> lines = File.ReadAllLines(Path.Combine("input/series.csv"), Encoding.ASCII).ToList();
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] parts = line.Split(",");
            if (!groups.ContainsKey(parts[0])) {
                groups[parts[0]] = new();
                names.Add(parts[0]);
            }
            groups[parts[0]].Add(new Point(Hundredths(parts[1]), Hundredths(parts[2])));
        }
        foreach (string name in names) {
            List<Point> points = groups[name];
            points.Sort((a, b) => a.x.CompareTo(b.x));
            int[] xx = new int[points.Count], yy = new int[points.Count];
            for (int i = 0; i < points.Count; i++) {
                xx[i] = points[i].x;
                yy[i] = points[i].y;
            }
            series.Add(new Series(name, xx, yy));
        }
        lines = File.ReadAllLines(Path.Combine("input/test_points.csv"), Encoding.ASCII).ToList();
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] parts = line.Split(",");
            tests.Add(new Test(parts[0], Hundredths(parts[1])));
        }
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)) {
            string[] parts = line.Split(" ");
            settings[parts[0]] = parts[1..parts.Length];
        }
    }
    public int Integer(string key) {
        return int.Parse(settings[key][0]);
    }
    public double Number(string key) {
        return double.Parse(settings[key][0], CultureInfo.InvariantCulture);
    }
    public string[] Values(string key) {
        return settings[key];
    }
}
