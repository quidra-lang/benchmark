using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Dataset {
    public record Box(long x1, long y1, long x2, long y2) {
    }
    public record Obj(int id, Box box) {
    }
    public record Command(string name, int[] values) {
    }
    public record Data(List<Obj> points, List<Obj> rectangles, int world, int bucket, int maximum,
                       int minimum, int grid, List<Command> commands) {
    }
    public static Obj Point(int id, int x, int y) {
        return new Obj(id, new Box(x, y, x, y));
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static Data Read() {
        List<Obj> points = new(), rectangles = new();
        List<string> pointLines = Lines("points.csv"), rectLines = Lines("rects.csv");
        for (int i = 1; i < pointLines.Count; i++) {
            string[] w = pointLines[i].Split(',');
            points.Add(Point(int.Parse(w[0]), int.Parse(w[1]), int.Parse(w[2])));
        }
        for (int i = 1; i < rectLines.Count; i++) {
            string[] w = rectLines[i].Split(',');
            rectangles.Add(new Obj(int.Parse(w[0]), new Box(long.Parse(w[1]), long.Parse(w[2]),
                                                            long.Parse(w[3]), long.Parse(w[4]))));
        }
        List<string> params = Lines("params.txt");
        int world = int.Parse(params[0].Split(' ')[1]), bucket = int.Parse(params[1].Split(' ')[1]),
            maximum = int.Parse(params[2].Split(' ')[1]), minimum = int.Parse(params[2].Split(' ')[2]),
            grid = int.Parse(params[3].Split(' ')[1]);
        List<Command> commands = new();
        foreach (string line in Lines("queries.txt")) {
            string[] w = line.Split(' ');
            int[] values = new int[w.Length - 1];
            for (int i = 1; i < w.Length; i++)
                values[i - 1] = int.Parse(w[i]);
            commands.Add(new Command(w[0], values));
        }
        return new Data(points, rectangles, world, bucket, maximum, minimum, grid, commands);
    }
}
