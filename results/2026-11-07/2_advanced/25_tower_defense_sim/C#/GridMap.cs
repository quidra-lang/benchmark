using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

readonly record struct Cell(int X, int Y) { public Point Center() => new(100 * X, 100 * Y); }
readonly record struct Point(int X, int Y);

sealed class GridMap
{
    public int Width { get; }
    public int Height { get; }
    public List<string> Rows { get; }
    public List<Cell> Spawns { get; }
    public Cell Exit { get; }

    GridMap(int width, int height, List<string> rows)
    {
        Width = width;
        Height = height;
        Rows = rows;
        var found = new SortedDictionary<int, Cell>();
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        {
            char terrain = rows[y][x];
            if (terrain >= '1' && terrain <= '9') found[terrain - '0'] = new Cell(x, y);
            else if (terrain == 'E') Exit = new Cell(x, y);
        }
        Spawns = found.Values.ToList();
    }

    public bool Inside(Cell cell) => cell.X >= 0 && cell.X < Width && cell.Y >= 0 && cell.Y < Height;
    public char Terrain(Cell cell) => Rows[cell.Y][cell.X];
    public bool Rock(Cell cell) => Terrain(cell) == '#';
    public bool Water(Cell cell) => Terrain(cell) == '~';
    public bool Buildable(Cell cell) => Terrain(cell) == '.';

    public static GridMap Read()
    {
        string[] lines = File.ReadAllLines(Path.Combine("input", "map.txt"), Encoding.ASCII);
        int[] dimensions = lines[0].Split(' ').Select(int.Parse).ToArray();
        return new GridMap(dimensions[0], dimensions[1], lines.Skip(1).Take(dimensions[1]).ToList());
    }
}
