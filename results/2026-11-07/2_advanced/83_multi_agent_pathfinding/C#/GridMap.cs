using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Linq;
public sealed class GridMap {
    public record Cell(int x, int y) { public override string ToString() => Report.CellText(this); }
    public record Agent(int id, Cell start, Cell goal) { public char Name() => (char)('A' + id); }
    public static readonly int[][] Directions = { new[] { 0, 0 }, new[] { 0, -1 }, new[] { 1, 0 },
                                                  new[] { 0, 1 }, new[] { -1, 0 } };
    public int width, height;
    public List<string> rows;
    public HashSet<Cell> free = new();
    public GridMap() {
        string[] lines = File.ReadAllLines("input/map.txt", Encoding.ASCII),
                 f = lines[0].Split(' ');
        width = int.Parse(f[0]);
        height = int.Parse(f[1]);
        rows = lines.Skip(1).ToList();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++)
                if (rows[y][x] == '.')
                    free.Add(new(x, y));
    }
    public List<Cell> Destinations(Cell cell) {
        List<Cell> result = new();
        foreach (int[] delta in Directions) {
            Cell next = new(cell.x + delta[0], cell.y + delta[1]);
            if (free.Contains(next))
                result.Add(next);
        }
        return result;
    }
    public List<Cell>
    Neighbors(Cell cell) => Destinations(cell).Where(next => next != cell).ToList();
    public Dictionary<Cell, int> Distances(Cell goal) {
        Dictionary<Cell, int> distances = new() { { goal, 0 } };
        Queue<Cell> queue = new();
        queue.Enqueue(goal);
        while (queue.Count > 0) {
            Cell cell = queue.Dequeue();
            foreach (Cell next in Neighbors(cell))
                if (!distances.ContainsKey(next)) {
                    distances[next] = distances[cell] + 1;
                    queue.Enqueue(next);
                }
        }
        return distances;
    }
    public static List<Agent>
    Agents() => File.ReadAllLines("input/agents.csv", Encoding.ASCII)
                    .Skip(1)
                    .Select(line => {
                        string[] f = line.Split(',');
                        return new Agent(int.Parse(f[0]), new(int.Parse(f[1]), int.Parse(f[2])),
                                         new(int.Parse(f[3]), int.Parse(f[4])));
                    })
                    .ToList();
}
