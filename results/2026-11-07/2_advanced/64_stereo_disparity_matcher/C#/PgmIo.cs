using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class PgmIo {
    public record Image(int width, int height, int[] pixels) {}
    public sealed class Parameters {
        public Dictionary<string, List<string>> values = new();
        public List<int[]> samples = new();
        public int Integer(string name) { return int.Parse(values[name][0]); }
        public string Text(string name) { return values[name][0]; }
        public int[] Integers(string name) {
            List<string> row = values[name];
            int[] result = new int[row.Count];
            for (int i = 0; i < result.Length; i++)
                result[i] = int.Parse(row[i]);
            return result;
        }
    }
    public static Image Read(string name) {
        List<string> lines = File.ReadAllLines(Path.Combine("input", name)).ToList();
        string[] size = lines[1].Split(' ');
        int w = int.Parse(size[0]), h = int.Parse(size[1]);
        int[] pixels = new int[w * h];
        for (int y = 0; y < h; y++) {
            string[] row = lines[y + 3].Split(' ');
            for (int x = 0; x < w; x++)
                pixels[y * w + x] = int.Parse(row[x]);
        }
        return new Image(w, h, pixels);
    }
    public static Parameters ReadParameters() {
        Parameters p = new Parameters();
        foreach (string line in File.ReadAllLines(Path.Combine("input", "params.txt")).ToList()) {
            string[] w = line.Split(' ');
            if (w[0].Equals("sample"))
                p.samples.Add(new int[] { int.Parse(w[1]), int.Parse(w[2]) });
            else
                p.values[w[0]] = w.Skip(1).ToList();
        }
        return p;
    }
    public static void Write(string name, int w, int h, int[] pixels) {
        List<string> lines = new(new string[] { "P2", w + " " + h, "255" });
        for (int y = 0; y < h; y++) {
            List<string> row = new();
            for (int x = 0; x < w; x++)
                row.Add(Convert.ToString(pixels[y * w + x]));
            lines.Add(string.Join(" ", row));
        }
        Text(name, lines);
    }
    public static void Text(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
}
