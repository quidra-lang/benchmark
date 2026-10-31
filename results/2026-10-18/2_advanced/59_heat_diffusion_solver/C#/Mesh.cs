using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Mesh {
    public record FaceRef(int point, int direction) {
    }
    public int width, height, count;
    public double dx, thickness;
    public char[] codes;
    public int[][] neighbors;
    public Mesh() {
        List<string> lines = File.ReadAllLines(Path.Combine("input/plate.txt")).ToList();
        string[] w = lines[0].Split(' ');
        width = int.Parse(w[0]);
        height = int.Parse(w[1]);
        dx = double.Parse(w[2]);
        thickness = double.Parse(w[3]);
        count = width * height;
        codes = new char[count];
        neighbors = Enumerable.Range(0, count)
                        .Select(
                            _ => new int[4])
                        .ToArray();
        for (int r = 0; r < height; r++)
            for (int c = 0; c < width; c++) {
                int p = Cell(r, c);
                codes[p] = lines[r + 1][c];
                neighbors[p] = new int[] { c > 0 ? p - 1 : -1, c + 1 < width ? p + 1 : -1,
                                           r > 0 ? p - width : -1, r + 1 < height ? p + width : -1 };
            }
    }
    public int Cell(int row, int column) {
        return row * width + column;
    }
    public string Coordinates(int p) {
        return p / width + " " + p % width;
    }
    public List<FaceRef> Segment(string edge, int start, int end) {
        List<FaceRef> faces = new();
        int direction = edge.Equals("left") ? 0 : edge.Equals("right") ? 1 : edge.Equals("top") ? 2 : 3;
        for (int i = start; i <= end; i++) {
            int p = direction == 0   ? Cell(i, 0)
                    : direction == 1 ? Cell(i, width - 1)
                    : direction == 2 ? Cell(0, i)
                                     : Cell(height - 1, i);
            faces.Add(new FaceRef(p, direction));
        }
        return faces;
    }
    public List<int> Source(int r1, int c1, int r2, int c2) {
        List<int> cells = new();
        for (int r = r1; r <= r2; r++)
            for (int c = c1; c <= c2; c++)
                cells.Add(Cell(r, c));
        return cells;
    }
}
