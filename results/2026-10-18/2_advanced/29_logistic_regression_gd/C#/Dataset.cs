using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Example(string id, double[] values, int label);
sealed record Statistics(double[] means, double[] deviations);
sealed class Dataset {
    public readonly List<Example> train, test;
    public readonly string[] names;
    public readonly Dictionary<string, string[]> settings = new();
    public readonly List<int[]> tuples = new();
    public readonly List<string> features = new();
    public Dataset() {
        List<string> lines = Lines("train.csv");
        string[] header = lines[0].Split(",");
        names = header[1..header.Length - 1];
        train = Examples(lines);
        test = Examples(Lines("test.csv"));
        foreach (string line in Lines("params.txt")) {
            string[] fields = line.Split(" ");
            settings[fields[0]] = fields[1..fields.Length];
        }
        for (int degree = 1; degree <= Integer("DEGREE", 0); degree++)
            Expand(new int[degree], 0, 0);
        foreach (int[] tuple in tuples) {
            List<string> factors = new();
            foreach (int index in tuple)
                factors.Add(names[index]);
            features.Add(string.Join("*", factors));
        }
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static List<Example> Examples(List<string> lines) {
        List<Example> rows = new();
        foreach (string line in lines.GetRange(1, lines.Count - (1))) {
            string[] fields = line.Split(",");
            double[] values = new double[fields.Length - 2];
            for (int j = 0; j < values.Length; j++)
                values[j] = double.Parse(fields[j + 1], CultureInfo.InvariantCulture);
            rows.Add(new Example(fields[0], values, int.Parse(fields[fields.Length - 1])));
        }
        return rows;
    }
    public int Integer(string key, int index) {
        return int.Parse(settings[key][index]);
    }
    public double Number(string key, int index) {
        return double.Parse(settings[key][index], CultureInfo.InvariantCulture);
    }
    public void Expand(int[] tuple, int position, int minimum) {
        if (position == tuple.Length) {
            tuples.Add(tuple.ToArray());
            return;
        }
        for (int index = minimum; index < names.Length; index++) {
            tuple[position] = index;
            Expand(tuple, position + 1, index);
        }
    }
    public double[] Expanded(double[] values) {
        double[] result = new double[tuples.Count];
        for (int j = 0; j < result.Length; j++) {
            int[] tuple = tuples[j];
            double product = values[tuple[0]];
            for (int k = 1; k < tuple.Length; k++)
                product *= values[tuple[k]];
            result[j] = product;
        }
        return result;
    }
    public double[][] Expanded(List<Example> rows) {
        double[][] values = new double [rows.Count][];
        for (int i = 0; i < rows.Count; i++)
            values[i] = Expanded(rows[i].values);
        return values;
    }
    public static Statistics Statistics(double[][] rows, int count) {
        double[] means = new double[count], deviations = new double[count];
        for (int j = 0; j < count; j++) {
            double total = 0;
            foreach (double[] row in rows)
                total += row[j];
            double mean = total / rows.Length;
            means[j] = mean;
            double squares = 0;
            foreach (double[] row in rows) {
                double delta = row[j] - mean;
                squares += delta * delta;
            }
            deviations[j] = Math.Sqrt(squares / (rows.Length - 1));
        }
        return new Statistics(means, deviations);
    }
    public static double[] Standardize(double[] values, Statistics statistics, int count) {
        double[] vector = new double[count + 1];
        vector[0] = 1;
        for (int j = 0; j < count; j++)
            vector[j + 1] = (values[j] - statistics.means[j]) / statistics.deviations[j];
        return vector;
    }
    public static double[][] Standardize(double[][] rows, Statistics statistics, int count) {
        double[][] result = new double [rows.Length][];
        for (int i = 0; i < rows.Length; i++)
            result[i] = Standardize(rows[i], statistics, count);
        return result;
    }
}
