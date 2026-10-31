using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

readonly record struct Pixel(int x, int y);
sealed record Image(string name, int width, int height, int maxval, int[][] pixels);
static class PgmReader
{
    public static List<string> lines(string path) => File.ReadAllLines(path, Encoding.ASCII).ToList();
    public static List<Image> read(string path)
    {
        var words = new List<string>();
        foreach (string line in lines(path))
        {
            string text = line.Split('#', 2)[0].Trim();
            if (text.Length > 0) words.AddRange(text.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        }
        var images = new List<Image>();
        int position = 0;
        while (position < words.Count)
        {
            string name = words[position + 1];
            int width = int.Parse(words[position + 3]), height = int.Parse(words[position + 4]), maxval = int.Parse(words[position + 5]);
            position += 6;
            int[][] pixels = Enumerable.Range(0, height).Select(_ => new int[width]).ToArray();
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) pixels[y][x] = int.Parse(words[position++]);
            images.Add(new Image(name, width, height, maxval, pixels));
        }
        return images;
    }
}
