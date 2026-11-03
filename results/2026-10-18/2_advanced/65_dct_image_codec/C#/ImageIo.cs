using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class ImageIo {
    public record Image(int width, int height, int[] pixels) {}
    public record Plane(int width, int height, int[] pixels) {}
    public record Tables(int[] transform, int[][] basic, Entropy.Table[][] huffman) {}
    public sealed class Parameters {
        public Dictionary<string, List<string>> values = new();
        public int Integer(string name) { return int.Parse(values[name][0]); }
        public string Text(string name) { return values[name][0]; }
        public int[] Integers(string name) { return Parse(string.Join(" ", values[name])); }
    }
    public static int[] Parse(string line) {
        string[] w = line.Split(' ');
        int[] values = new int[w.Length];
        for (int i = 0; i < values.Length; i++)
            values[i] = int.Parse(w[i]);
        return values;
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name)).ToList();
    }
    public static Image ReadImage() {
        List<string> lines = Lines("image.ppm");
        int[] size = Parse(lines[1]);
        int[] pixels = new int[3 * size[0] * size[1]];
        for (int y = 0; y < size[1]; y++) {
            int[] row = Parse(lines[y + 3]);
            Array.Copy(row, 0, pixels, 3 * y * size[0], row.Length);
        }
        return new Image(size[0], size[1], pixels);
    }
    public static Parameters ReadParameters() {
        Parameters p = new Parameters();
        foreach (string line in Lines("params.txt")) {
            string[] w = line.Split(' ');
            p.values[w[0]] = w.Skip(1).ToList();
        }
        return p;
    }
    public static Tables ReadTables() {
        List<string> lines = Lines("tables.txt");
        int[] c = new int[64];
        int[][] basic = Enumerable.Range(0, 2)
                            .Select(
                                _ => new int[64])
                            .ToArray();
        for (int y = 0; y < 8; y++) {
            Array.Copy(Parse(lines[y + 1]), 0, c, 8 * y, 8);
            for (int t = 0; t < 2; t++)
                Array.Copy(Parse(lines[10 + 9 * t + y]), 0, basic[t], 8 * y, 8);
        }
        Entropy.Table[][] tables = Enumerable.Range(0, 2)
                                       .Select(
                                           _ => new Entropy.Table[16])
                                       .ToArray();
        for (int i = 27; i < 39; i += 3) {
            string[] key = lines[i].Split(' ');
            tables[int.Parse(key[1])][int.Parse(key[2])] =
                new Entropy.Table(Parse(lines[i + 1]), Parse(lines[i + 2]));
        }
        return new Tables(c, basic, tables);
    }
    public static int[] ReadHex() {
        string s = string.Join("", Lines("stream.hex"));
        int[] data = new int[s.Length / 2];
        for (int i = 0; i < data.Length; i++)
            data[i] = int.Parse(s.Substring(2 * i, 2), NumberStyles.HexNumber,
                                CultureInfo.InvariantCulture);
        return data;
    }
    public static void Text(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static void WriteImage(string name, Image image) {
        List<string> lines = new(new string[] { "P3", image.width + " " + image.height, "255" });
        for (int y = 0; y < image.height; y++) {
            List<string> row = new();
            for (int x = 0; x < 3 * image.width; x++)
                row.Add(Convert.ToString(image.pixels[3 * y * image.width + x]));
            lines.Add(string.Join(" ", row));
        }
        Text(name, lines);
    }
    public static void WriteHex(string name, int[] data) {
        List<string> lines = new();
        for (int i = 0; i < data.Length; i += 32) {
            StringBuilder row = new StringBuilder();
            for (int j = i; j < Math.Min(i + 32, data.Length); j++)
                row.Append(data[j].ToString("x2", CultureInfo.InvariantCulture));
            lines.Add(row.ToString());
        }
        Text(name, lines);
    }
}
