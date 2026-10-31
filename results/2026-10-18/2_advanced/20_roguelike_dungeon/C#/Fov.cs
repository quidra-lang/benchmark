using System;
using System.Collections.Generic;
using System.Linq;

static class Fov {
    public static readonly string[] Names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    public static readonly int[][] Directions = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]];
    public static bool Passable(Level level, int x, int y) => ".#+<>".Contains(level.Terrain[y][x]);
    public static bool CanMove(Level level, int x, int y, int dx, int dy) => Passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || level.Terrain[y][x] != '+' && level.Terrain[y + dy][x + dx] != '+');
    public static List<Position> Line(int x0, int y0, int x1, int y1) {
        int dx = Math.Abs(x1 - x0), dy = Math.Abs(y1 - y0), sx = x1 > x0 ? 1 : -1, sy = y1 > y0 ? 1 : -1;
        int error = dx - dy, x = x0, y = y0;
        List<Position> cells = new();
        while (x != x1 || y != y1) {
            int twice = 2 * error;
            if (twice > -dy) { error -= dy; x += sx; }
            if (twice < dx) { error += dx; y += sy; }
            cells.Add(new Position(x, y));
        }
        return cells;
    }
    public static bool[][] FieldOfView(Level level, int px, int py, int radius) {
        bool[][] visible = Enumerable.Range(0, level.Height).Select(_ => new bool[level.Width]).ToArray();
        for (int y = Math.Max(0, py - radius); y < Math.Min(level.Height, py + radius + 1); y++) for (int x = Math.Max(0, px - radius); x < Math.Min(level.Width, px + radius + 1); x++) {
            if ((x - px) * (x - px) + (y - py) * (y - py) > radius * radius) continue;
            List<Position> cells = Line(px, py, x, y);
            bool clear = true;
            for (int i = 0; i + 1 < cells.Count; i++) if (!Passable(level, cells[i].X, cells[i].Y)) { clear = false; break; }
            visible[y][x] = clear;
        }
        return visible;
    }
    public static int[][] Distances(Level level, int px, int py) {
        int[][] distance = Enumerable.Range(0, level.Height).Select(_ => Enumerable.Repeat(-1, level.Width).ToArray()).ToArray();
        distance[py][px] = 0;
        Queue<Position> queue = new(); queue.Enqueue(new Position(px, py));
        while (queue.Count > 0) {
            Position point = queue.Dequeue();
            foreach (int[] direction in Directions) {
                int x = point.X + direction[0], y = point.Y + direction[1];
                if (CanMove(level, point.X, point.Y, direction[0], direction[1]) && distance[y][x] < 0) { distance[y][x] = distance[point.Y][point.X] + 1; queue.Enqueue(new Position(x, y)); }
            }
        }
        return distance;
    }
}
