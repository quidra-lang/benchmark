using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Image(string id, int label, string pixels, double[] values) {
    }
    public record Run(string name, string network, string optimizer, double eta, double lambda,
                      double momentum, double beta1, double beta2, double epsilon) {
    }
    public sealed class Settings {
        public int seed, batch, epochs, patience, decayStep, stride, bins;
        public double gamma;
        public int[] prune, noise;
        public List<Run> runs = new();
    }
    public record Data(int width, int height, List<Image> train, List<Image> test, List<Network> networks,
                       Settings settings) {
    }
    public sealed class Generator {
        public long state;
        public Generator(int seed) {
            state = seed;
        }
        public int Draw() {
            state = 48271 * state % 2147483647;
            return (int)state;
        }
        public void Shuffle(int[] order) {
            for (int i = order.Length - 1; i > 0; i--) {
                int j = Draw() % (i + 1), temp = order[i];
                order[i] = order[j];
                order[j] = temp;
            }
        }
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name)).ToList();
    }
    public static Image CreateImage(string id, int label, string pixels) {
        double[] values = new double[pixels.Length];
        for (int i = 0; i < values.Length; i++)
            values[i] = pixels[i] == '1' ? 1 : 0;
        return new Image(id, label, pixels, values);
    }
    public static List<Image> Images(string name) {
        List<string> input = Lines(name);
        List<Image> images = new();
        for (int i = 1; i < input.Count; i++) {
            string[] w = input[i].Split(',');
            images.Add(CreateImage(w[0], int.Parse(w[1]), w[2]));
        }
        return images;
    }
    public static int[] Integers(string[] words) {
        int[] values = new int[words.Length - 1];
        for (int i = 0; i < values.Length; i++)
            values[i] = int.Parse(words[i + 1]);
        return values;
    }
    public static Data Read() {
        List<string> definitions = Lines("network.txt");
        string[] header = definitions[0].Split(' ');
        int width = int.Parse(header[1]), height = int.Parse(header[2]);
        List<Network> networks = new();
        string name = null;
        List<int> sizes = new();
        List<string> activations = new();
        for (int i = 1; i <= definitions.Count; i++) {
            string line = i == definitions.Count ? "" : definitions[i];
            if (line.Length == 0) {
                if (name != null) {
                    int[] units = new int[sizes.Count];
                    for (int j = 0; j < units.Length; j++)
                        units[j] = sizes[j];
                    networks.Add(new Network(name, width * height, units, activations.ToArray()));
                    name = null;
                    sizes.Clear();
                    activations.Clear();
                }
                continue;
            }
            string[] w = line.Split(' ');
            if (w[0].Equals("NETWORK"))
                name = w[1];
            else {
                sizes.Add(int.Parse(w[1]));
                activations.Add(w[2]);
            }
        }
        Network current = null;
        int parameter = 0;
        foreach (string line in Lines("weights.txt")) {
            if (line.Length == 0)
                continue;
            string[] w = line.Split(' ');
            if (w[0].Equals("NETWORK")) {
                foreach (Network net in networks)
                    if (net.name.Equals(w[1]))
                        current = net;
                parameter = 0;
            } else if (w[0].Equals("W") || w[0].Equals("B"))
                for (int j = 1; j < w.Length; j++)
                    current.initial[parameter++] = double.Parse(w[j]);
        }
        Settings s = new Settings();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "SEED":
                s.seed = int.Parse(w[1]);
                break;
            case "BATCH_SIZE":
                s.batch = int.Parse(w[1]);
                break;
            case "MAX_EPOCHS":
                s.epochs = int.Parse(w[1]);
                break;
            case "PATIENCE":
                s.patience = int.Parse(w[1]);
                break;
            case "LR_STEP": {
                s.decayStep = int.Parse(w[1]);
                s.gamma = double.Parse(w[2]);
                break;
            }
            case "GRADIENT_CHECK_STRIDE":
                s.stride = int.Parse(w[1]);
                break;
            case "CALIBRATION_BINS":
                s.bins = int.Parse(w[1]);
                break;
            case "PRUNE":
                s.prune = Integers(w);
                break;
            case "NOISE":
                s.noise = Integers(w);
                break;
            case "RUN": {
                string opt = w[3];
                s.runs.Add(new Run(w[1], w[2], opt, double.Parse(w[4]), double.Parse(w[5]),
                                   opt.Equals("MOMENTUM") ? double.Parse(w[6]) : 0,
                                   opt.Equals("ADAM") ? double.Parse(w[6]) : 0,
                                   opt.Equals("ADAM") ? double.Parse(w[7]) : 0,
                                   opt.Equals("ADAM") ? double.Parse(w[8]) : 0));
                break;
            }
            }
        }
        return new Data(width, height, Images("train.csv"), Images("test.csv"), networks, s);
    }
}
