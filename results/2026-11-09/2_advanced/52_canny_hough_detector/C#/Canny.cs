using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Canny {
    public sealed class Result {
        public int[][] direction, nms;
        public bool[][] edge;
        public List<List<PgmIo.Point>> components = new();
        public int strong, weak, weakKept;
    }
    public static bool Inside(int x, int y, int width, int height) {
        return x >= 0 && x < width && y >= 0 && y < height;
    }
    public static List<PgmIo.Point> Neighbors(PgmIo.Point p, int width, int height) {
        List<PgmIo.Point> result = new();
        for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
                if ((dx != 0 || dy != 0) && Inside(p.x + dx, p.y + dy, width, height))
                    result.Add(new PgmIo.Point(p.x + dx, p.y + dy));
        return result;
    }
    public static Result Process(Filters.Gradient gradient, int low, int high) {
        int[][] m = gradient.magnitude;
        int height = m.Length, width = m[0].Length;
        Result result = new Result();
        result.direction = Enumerable.Range(0, height)
                               .Select(
                                   _ => new int[width])
                               .ToArray();
        result.nms = Enumerable.Range(0, height)
                         .Select(
                             _ => new int[width])
                         .ToArray();
        result.edge = Enumerable.Range(0, height)
                          .Select(
                              _ => new bool[width])
                          .ToArray();
        Queue<PgmIo.Point> queue = new();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int gx = gradient.gx[y][x], gy = gradient.gy[y][x], ax = Math.Abs(gx), ay = Math.Abs(gy);
                int direction = 29 * ay <= 12 * ax ? 0 : 29 * ay >= 70 * ax ? 90 : gx * gy < 0 ? 45 : 135;
                result.direction[y][x] = direction;
                if (x == 0 || y == 0 || x == width - 1 || y == height - 1)
                    continue;
                int dx = direction == 90 ? 0 : direction == 45 ? 1 : -1, dy = direction == 0 ? 0 : -1;
                if (m[y][x] > m[y + dy][x + dx] && m[y][x] >= m[y - dy][x - dx])
                    result.nms[y][x] = m[y][x];
                if (result.nms[y][x] >= high) {
                    result.strong++;
                    result.edge[y][x] = true;
                    queue.Enqueue(new PgmIo.Point(x, y));
                } else if (result.nms[y][x] >= low)
                    result.weak++;
            }
        while (queue.Count != 0) {
            PgmIo.Point point = queue.Dequeue();
            foreach (PgmIo.Point next in Neighbors(point, width, height))
                if (!result.edge[next.y][next.x] && result.nms[next.y][next.x] >= low) {
                    result.edge[next.y][next.x] = true;
                    queue.Enqueue(next);
                }
        }
        bool[][] seen = Enumerable.Range(0, height)
                            .Select(
                                _ => new bool[width])
                            .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                if (result.edge[y][x] && result.nms[y][x] < high)
                    result.weakKept++;
                if (!result.edge[y][x] || seen[y][x])
                    continue;
                List<PgmIo.Point> component = new();
                queue.Enqueue(new PgmIo.Point(x, y));
                seen[y][x] = true;
                while (queue.Count != 0) {
                    PgmIo.Point point = queue.Dequeue();
                    component.Add(point);
                    foreach (PgmIo.Point next in Neighbors(point, width, height))
                        if (result.edge[next.y][next.x] && !seen[next.y][next.x]) {
                            seen[next.y][next.x] = true;
                            queue.Enqueue(next);
                        }
                }
                result.components.Add(component);
            }
        return result;
    }
}
