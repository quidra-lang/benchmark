using System;
using System.Collections.Generic;

static class Pathing
{
    public static readonly (int X, int Y)[] Directions = { (0, -1), (1, 0), (0, 1), (-1, 0) };
    public static Cell Neighbor(Cell cell, int direction) => new(cell.X + Directions[direction].X, cell.Y + Directions[direction].Y);
}

sealed class DistanceField
{
    public GridMap Grid { get; }
    readonly int[][] distances;

    public DistanceField(GridMap grid, HashSet<Cell> towers)
    {
        Grid = grid;
        distances = new int[grid.Height][];
        for (int y = 0; y < grid.Height; y++) { distances[y] = new int[grid.Width]; Array.Fill(distances[y], -1); }
        distances[grid.Exit.Y][grid.Exit.X] = 0;
        var queue = new Queue<Cell>();
        queue.Enqueue(grid.Exit);
        while (queue.Count > 0)
        {
            Cell cell = queue.Dequeue();
            for (int direction = 0; direction < 4; direction++)
            {
                Cell next = Pathing.Neighbor(cell, direction);
                if (grid.Inside(next) && !grid.Rock(next) && !towers.Contains(next) && At(next) < 0)
                {
                    distances[next.Y][next.X] = At(cell) + 1;
                    queue.Enqueue(next);
                }
            }
        }
    }

    public int At(Cell cell) => distances[cell.Y][cell.X];
    public int Direction(Cell cell)
    {
        int best = -1, distance = 0;
        for (int direction = 0; direction < 4; direction++)
        {
            Cell next = Pathing.Neighbor(cell, direction);
            if (!Grid.Inside(next) || At(next) < 0) continue;
            if (best < 0 || At(next) < distance) { best = direction; distance = At(next); }
        }
        return best;
    }
    public Cell Next(Cell cell) => Pathing.Neighbor(cell, Direction(cell));
    public List<Cell> Path(Cell start)
    {
        var path = new List<Cell> { start };
        while (path[^1] != Grid.Exit) path.Add(Next(path[^1]));
        return path;
    }
}
