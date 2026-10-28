using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Cell(int x, int y);
sealed record Neighborhood(int[] points, int candidates);
sealed class GridIndex {
    void AddPoint(Cell cell, int index) {
        if (!cells.TryGetValue(cell, out List<int> members)) {
            members = new();
            cells[cell] = members;
        }
        members.Add(index);
    }
    public readonly List<Point> points;
    public readonly int radius;
    public readonly Dictionary<Cell, List<int>> cells = new();
    public GridIndex(List<Point> points, int radius) {
        this.points = points;
        this.radius = radius;
        for (int i = 0; i < points.Count; i++) {
            Point point = points[i];
            Cell cell = new Cell(point.x / radius, point.y / radius);
            AddPoint(cell, i);
        }
    }
    public static int Distance(Point a, Point b) {
        int x = a.x - b.x, y = a.y - b.y;
        return x * x + y * y;
    }
    public Neighborhood Neighborhood(int index) {
        Point point = points[index];
        int x = point.x / radius, y = point.y / radius, candidates = 0;
        List<int> neighbors = new();
        for (int row = y - 1; row <= y + 1; row++)
            for (int column = x - 1; column <= x + 1; column++)
                foreach (int other in cells.GetValueOrDefault(new Cell(column, row), [])) {
                    candidates++;
                    if (Distance(point, points[other]) <= radius * radius)
                        neighbors.Add(other);
                }
        return new Neighborhood(neighbors.ToArray(), candidates);
    }
    public Cell Busiest() {
        Cell best = null;
        foreach (KeyValuePair<Cell, List<int>> entry in cells) {
            Cell cell = entry.Key;
            if (best == null || entry.Value.Count > cells[best].Count ||
                entry.Value.Count == cells[best].Count &&
                    (cell.y < best.y || cell.y == best.y && cell.x < best.x))
                best = cell;
        }
        return best;
    }
    public int[] BruteCounts() {
        int[] counts = new int[points.Count];
        for (int i = 0; i < points.Count; i++)
            foreach (Point point in points)
                if (Distance(points[i], point) <= radius * radius)
                    counts[i]++;
        return counts;
    }
}
