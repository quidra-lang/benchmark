using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Corners {
    public record Corner(int x, int y, long response) {
    }
    public record Result(int candidates, List<Corner> corners) {
    }
    public static Result Detect(Filters.Gradient gradient, int window, long threshold, int maximum) {
        int height = gradient.gx.Length, width = gradient.gx[0].Length, half = window / 2;
        long[][] response = Enumerable.Range(0, height)
                                .Select(
                                    _ => new long[width])
                                .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                long xx = 0, yy = 0, xy = 0;
                for (int j = -half; j <= half; j++)
                    for (int i = -half; i <= half; i++) {
                        long gx = Filters.Clamped(gradient.gx, x + i, y + j),
                             gy = Filters.Clamped(gradient.gy, x + i, y + j);
                        xx += gx * gx;
                        yy += gy * gy;
                        xy += gx * gy;
                    }
                response[y][x] = xx * yy - xy * xy - (xx + yy) * (xx + yy) / 25;
            }
        List<Corner> candidates = new();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                long value = response[y][x];
                if (value < threshold)
                    continue;
                bool peak = true;
                foreach (PgmIo.Point p in Canny.Neighbors(new PgmIo.Point(x, y), width, height)) {
                    long other = response[p.y][p.x];
                    if (other > value || other == value && (p.y < y || p.y == y && p.x < x))
                        peak = false;
                }
                if (peak)
                    candidates.Add(new Corner(x, y, value));
            }
        candidates.Sort(Comparer<Corner>.Create((a, b) => a.response != b.response
                                                              ? b.response.CompareTo(a.response)
                                                          : a.y != b.y ? a.y.CompareTo(b.y)
                                                                       : a.x.CompareTo(b.x)));
        return new Result(candidates.Count,
                          new(candidates.GetRange(0, Math.Min(maximum, candidates.Count) - (0))));
    }
}
