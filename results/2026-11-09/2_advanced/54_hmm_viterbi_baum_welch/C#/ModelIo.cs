using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class ModelIo {
    public static string Repeat(this string text, int count) => string.Concat(Enumerable.Repeat(text, count));
    public sealed class Model {
        public string name;
        public char[] states, symbols;
        public char missing;
        public double[] pi;
        public double[][] a, b;
        public Model(string name, char[] states, char[] symbols, char missing, double[] pi, double[][] a,
                     double[][] b) {
            this.name = name;
            this.states = states;
            this.symbols = symbols;
            this.missing = missing;
            this.pi = Normalize(pi);
            this.a = new double [a.Length][];
            this.b = new double [b.Length][];
            for (int i = 0; i < a.Length; i++)
                this.a[i] = Normalize(a[i]);
            for (int i = 0; i < b.Length; i++)
                this.b[i] = Normalize(b[i]);
        }
    }
    public record Data(Model model, List<string> sequences, List<string> labeled,
                       Dictionary<string, string[]> settings) {
    }
    public static double[] Normalize(double[] values) {
        double sum = 0;
        foreach (double value in values)
            sum += value;
        double[] result = new double[values.Length];
        for (int i = 0; i < values.Length; i++)
            result[i] = values[i] / sum;
        return result;
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static double[] Numbers(string[] words, int start) {
        double[] result = new double[words.Length - start];
        for (int i = start; i < words.Length; i++)
            result[i - start] = double.Parse(words[i]);
        return result;
    }
    public static char[] Letters(string line) {
        string[] w = line.Split(' ');
        char[] result = new char[w.Length - 1];
        for (int i = 1; i < w.Length; i++)
            result[i - 1] = w[i][0];
        return result;
    }
    public static Data Read() {
        List<string> input = Lines("model.txt");
        char[] states = Letters(input[0]), symbols = Letters(input[1]);
        char missing = input[2].Split(' ') [1][0];
        int k = states.Length;
        double[] pi = Numbers(input[3].Split(' '), 1);
        double[][] a = new double [k][], b = new double [k][];
        for (int i = 0; i < k; i++) {
            a[i] = Numbers(input[4 + i].Split(' '), 2);
            b[i] = Numbers(input[4 + k + i].Split(' '), 2);
        }
        Dictionary<string, string[]> settings = new();
        foreach (string line in Lines("params.txt")) {
            string[] words = line.Split(' ');
            settings[words[0]] = words.Skip(1).Take(words.Length - (1)).ToArray();
        }
        return new Data(new Model("INITIAL", states, symbols, missing, pi, a, b), Lines("sequences.txt"),
                        Lines("labeled.txt"), settings);
    }
    public static string Real(double value, int digits) {
        if (double.IsNaN(value))
            return "-";
        double result = Math.Round(value, digits, MidpointRounding.AwayFromZero);
        if (result == 0)
            result = 0;
        return result.ToString("F" + digits, CultureInfo.InvariantCulture);
    }
    public static string F(double value) {
        return Real(value, 4);
    }
    public static string Values(double[] values) {
        string text = "";
        foreach (double value in values)
            text += " " + F(value);
        return text;
    }
    public static string Names(char[] names) {
        string text = "";
        foreach (char name in names)
            text += " " + name;
        return text;
    }
    public static List<string> Format(Model model) {
        List<string> output = new([
            "MODEL " + model.name, "STATES" + Names(model.states), "SYMBOLS" + Names(model.symbols),
            "MISSING " + model.missing, "INITIAL" + Values(model.pi)
        ]);
        for (int i = 0; i < model.states.Length; i++)
            output.Add("TRANSITION " + model.states[i] + Values(model.a[i]));
        for (int i = 0; i < model.states.Length; i++)
            output.Add("EMISSION " + model.states[i] + Values(model.b[i]));
        return output;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
