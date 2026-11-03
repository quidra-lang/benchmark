using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Plot {
    public static string Repeat(this string text, int count) => string.Concat(Enumerable.Repeat(text, count));
    public record Cell(int col, int row) {
    }
    public static char[][] Canvas(int width, int height) {
        char[][] grid = Enumerable.Range(0, height)
                            .Select(
                                _ => new char[width])
                            .ToArray();
        foreach (char[] row in grid)
            Array.Fill(row, ' ');
        return grid;
    }
    public static Cell Map(Predicates.Point point, int width, int height) {
        return new Cell((int)((2 * point.x * (width - 1) + 1000) / 2000),
                        height - 1 - (int)((2 * point.y * (height - 1) + 1000) / 2000));
    }
    public static Cell Center(Predicates.Center point, int width, int height) {
        return new Cell((int)((2 * point.x * (width - 1) + 1000 * point.d) / (2000 * point.d)),
                        height - 1 - (int)((2 * point.y * (height - 1) + 1000 * point.d) / (2000 * point.d)));
    }
    public static void Line(char[][] grid, Cell from, Cell to, char ch) {
        int x = from.col, y = from.row, dx = Math.Abs(to.col - x), dy = -Math.Abs(to.row - y),
            sx = x < to.col ? 1 : -1, sy = y < to.row ? 1 : -1, e = dx + dy;
        while (true) {
            grid[y][x] = ch;
            if (x == to.col && y == to.row)
                break;
            int e2 = 2 * e;
            if (e2 >= dy) {
                e += dy;
                x += sx;
            }
            if (e2 <= dx) {
                e += dx;
                y += sy;
            }
        }
    }
    public static List<string> Frame(char[][] grid) {
        string border = "+" + "-".Repeat(grid[0].Length) + "+";
        List<string> result = new();
        result.Add(border);
        foreach (char[] row in grid)
            result.Add("|" + new string(row) + "|");
        result.Add(border);
        return result;
    }
    public static char[][] Voronoi(List<Predicates.Point> points, int width, int height) {
        char[][] grid = Canvas(width, height);
        int[][] owners = Enumerable.Range(0, height)
                             .Select(
                                 _ => new int[width])
                             .ToArray();
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++) {
                long best = long.MaxValue;
                int owner = 0;
                for (int site = 1; site < points.Count; site++) {
                    Predicates.Point p = points[site];
                    long x = (col * 1000 - p.x * (width - 1)) * (height - 1),
                         y = ((height - 1 - row) * 1000 - p.y * (height - 1)) * (width - 1),
                         delta = x * x + y * y;
                    if (delta < best) {
                        best = delta;
                        owner = site;
                    }
                }
                owners[row][col] = owner;
            }
        for (int row = 0; row < height; row++)
            for (int col = 0; col < width; col++)
                if (col + 1 < width && owners[row][col] != owners[row][col + 1] ||
                    row + 1 < height && owners[row][col] != owners[row + 1][col])
                    grid[row][col] = '#';
        for (int site = 1; site < points.Count; site++) {
            Cell cell = Map(points[site], width, height);
            grid[cell.row][cell.col] = 'o';
        }
        return grid;
    }
}
