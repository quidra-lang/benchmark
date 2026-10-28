using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Point(int id, int x, int y);
sealed class Dataset {
    public readonly List<Point> points = new();
    public readonly Dictionary<string, string[]> settings = new();
    public Dataset() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/points.csv"), Encoding.ASCII).ToList();
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] fields = line.Split(",");
            points.Add(new Point(int.Parse(fields[0]), int.Parse(fields[1]), int.Parse(fields[2])));
        }
        points.Sort((a, b) => a.id.CompareTo(b.id));
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)
                     .ToList()) {
            string[] fields = line.Split(" ");
            settings[fields[0]] = fields[1..fields.Length];
        }
    }
    public int Value(string key) {
        return int.Parse(settings[key][0]);
    }
    public int Value(string key, int index) {
        return int.Parse(settings[key][index]);
    }
    public int[] Values(string key) {
        string[] fields = settings[key];
        int[] values = new int[fields.Length];
        for (int i = 0; i < values.Length; i++)
            values[i] = int.Parse(fields[i]);
        return values;
    }
}
