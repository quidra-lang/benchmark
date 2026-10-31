using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class SignalIo {
    public sealed class Annotation {
        public int sample;
        public string label;
        public Program.Beat beat;
        public Annotation(int sample, string label) {
            this.sample = sample;
            this.label = label;
        }
    }
    public static long[] Ecg() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/ecg.csv"), Encoding.ASCII).ToList();
        long[] result = new long[lines.Count - 1];
        for (int i = 1; i < lines.Count; i++)
            result[i - 1] = long.Parse(lines[i].Split(',')[1]);
        return result;
    }
    public static List<Annotation> Annotations() {
        List<string> lines =
            File.ReadAllLines(Path.Combine("input/annotations.csv"), Encoding.ASCII).ToList();
        List<Annotation> result = new();
        for (int i = 1; i < lines.Count; i++) {
            string[] w = lines[i].Split(',');
            result.Add(new Annotation(int.Parse(w[0]), w[1]));
        }
        return result;
    }
    public static Dictionary<string, int> Parameters() {
        Dictionary<string, int> result = new();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)
                     .ToList()) {
            string[] w = line.Split(' ');
            result[w[0]] = int.Parse(w[1]);
        }
        return result;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
}
