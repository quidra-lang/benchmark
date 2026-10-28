using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class PgmIo {
    public record Point(int x, int y) {
    }
    public sealed class Params {
        public Dictionary<string, long[]> values = new();
        public int Get(string key) {
            return (int)values[key][0];
        }
        public long Value(string key) {
            return values[key][0];
        }
        public long[] Row(string key) {
            return values[key];
        }
    }
    public record Data(int[][] image, int[][] trig, Params settings) {
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Data Read() {
        List<string> input = Lines("image.pgm");
        string[] size = input[1].Split(' ');
        int width = int.Parse(size[0]), height = int.Parse(size[1]);
        int[][] image = Enumerable.Range(0, height)
                            .Select(
                                _ => new int[width])
                            .ToArray(),
                trig = Enumerable.Range(0, 180)
                           .Select(
                               _ => new int[2])
                           .ToArray();
        for (int y = 0; y < height; y++) {
            string[] words = input[y + 3].Split(' ');
            for (int x = 0; x < width; x++)
                image[y][x] = int.Parse(words[x]);
        }
        List<string> table = Lines("trig.txt");
        for (int t = 0; t < 180; t++) {
            string[] w = table[t].Split(' ');
            trig[t][0] = int.Parse(w[1]);
            trig[t][1] = int.Parse(w[2]);
        }
        Params settings = new Params();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            long[] values = new long[w.Length - 1];
            for (int i = 1; i < w.Length; i++)
                values[i - 1] = long.Parse(w[i]);
            settings.values[w[0]] = values;
        }
        return new Data(image, trig, settings);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Pgm(string name, int[][] image) {
        List<string> output = new(["P2", image[0].Length + " " + image.Length, "255"]);
        foreach (int[] row in image) {
            List<string> words = new();
            foreach (int value in row)
                words.Add(Convert.ToString(value));
            output.Add(string.Join(" ", words));
        }
        Write(name, output);
    }
}
