using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Example(string id, Kernels.Point point, int label) {
    }
    public sealed class Settings {
        public double[] coefficients, plotX, plotY;
        public int[] learning;
        public double tolerance, eps, multiC, lambda;
        public int maximum, folds, newton, pegasos, seed, width, height;
        public string multiKernel;
        public List<Kernels.Kernel> kernels = new();
    }
    public record Data(List<Example> train, List<Example> test, List<Example> multiTrain,
                       List<Example> multiTest, Settings settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name)).ToList();
    }
    public static double[] Reals(string[] w, int first) {
        double[] a = new double[w.Length - first];
        for (int i = 0; i < a.Length; i++)
            a[i] = double.Parse(w[i + first]);
        return a;
    }
    public static Example ParseExample(string[] w) {
        return new Example(w[0], new Kernels.Point(double.Parse(w[1]), double.Parse(w[2])), int.Parse(w[3]));
    }
    public static List<Example> Binary(string name) {
        List<string> lines = Lines(name);
        List<Example> result = new();
        for (int i = 1; i < lines.Count; i++)
            result.Add(ParseExample(lines[i].Split(',')));
        return result;
    }
    public static Data Read() {
        List<Example> train = Binary("train.csv"), test = Binary("test.csv"), multiTrain = new(),
                      multiTest = new();
        List<string> multi = Lines("multiclass.csv");
        for (int i = 1; i < multi.Count; i++) {
            string[] w = multi[i].Split(',');
            (w[4].Equals("train") ? multiTrain : multiTest).Add(ParseExample(w));
        }
        Settings s = new Settings();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "C_GRID":
                s.coefficients = Reals(w, 1);
                break;
            case "KERNEL": {
                string kind = w[2];
                int degree = kind.Equals("poly") ? int.Parse(w[3]) : 0;
                double gamma = kind.Equals("poly")  ? double.Parse(w[4])
                               : kind.Equals("rbf") ? double.Parse(w[3])
                                                    : 0,
                       offset = kind.Equals("poly") ? double.Parse(w[5]) : 0;
                s.kernels.Add(new Kernels.Kernel(w[1], kind, degree, gamma, offset));
                break;
            }
            case "TOLERANCE":
                s.tolerance = double.Parse(w[1]);
                break;
            case "EPS":
                s.eps = double.Parse(w[1]);
                break;
            case "MAX_PASSES":
                s.maximum = int.Parse(w[1]);
                break;
            case "FOLDS":
                s.folds = int.Parse(w[1]);
                break;
            case "LEARNING_CURVE": {
                s.learning = new int[w.Length - 1];
                for (int i = 0; i < s.learning.Length; i++)
                    s.learning[i] = int.Parse(w[i + 1]);
                break;
            }
            case "NEWTON_ITERATIONS":
                s.newton = int.Parse(w[1]);
                break;
            case "MULTICLASS": {
                s.multiKernel = w[1];
                s.multiC = double.Parse(w[2]);
                break;
            }
            case "PEGASOS": {
                s.lambda = double.Parse(w[1]);
                s.pegasos = int.Parse(w[2]);
                s.seed = int.Parse(w[3]);
                break;
            }
            case "PLOT_X":
                s.plotX = Reals(w, 1);
                break;
            case "PLOT_Y":
                s.plotY = Reals(w, 1);
                break;
            case "PLOT_SIZE": {
                s.width = int.Parse(w[1]);
                s.height = int.Parse(w[2]);
                break;
            }
            }
        }
        return new Data(train, test, multiTrain, multiTest, s);
    }
    public static List<Kernels.Point> Points(List<Example> examples) {
        List<Kernels.Point> points = new();
        foreach (Example example in examples)
            points.Add(example.point);
        return points;
    }
    public static int[] Labels(List<Example> examples) {
        int[] labels = new int[examples.Count];
        for (int i = 0; i < labels.Length; i++)
            labels[i] = examples[i].label;
        return labels;
    }
}
