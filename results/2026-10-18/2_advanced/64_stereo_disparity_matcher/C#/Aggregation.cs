using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Aggregation {
    public static readonly int[][] DIRECTIONS =
        new int[][] { new int[] { 1, 0 },  new int[] { -1, 0 }, new int[] { 0, 1 },
                      new int[] { 0, -1 }, new int[] { 1, 1 },  new int[] { -1, -1 },
                      new int[] { -1, 1 }, new int[] { 1, -1 } };
    public static long[][] Path(long[][] baseCosts, int[] left, int w, int h, int direction,
                                long p1, long p2, long gamma) {
        int rx = DIRECTIONS[direction][0], ry = DIRECTIONS[direction][1], n = baseCosts[0].Length;
        long[][] result = Enumerable.Range(0, baseCosts.Length)
                              .Select(
                                  _ => new long[n])
                              .ToArray();
        for (int yi = 0; yi < h; yi++) {
            int y = ry < 0 ? h - 1 - yi : yi;
            for (int xi = 0; xi < w; xi++) {
                int x = rx < 0 ? w - 1 - xi : xi, p = y * w + x, qx = x - rx, qy = y - ry;
                if (qx < 0 || qx >= w || qy < 0 || qy >= h) {
                    result[p] = baseCosts[p].ToArray();
                    continue;
                }
                int q = qy * w + qx;
                long[] previous = result[q];
                long minimum = previous[0];
                foreach (long value in previous)
                    minimum = Math.Min(minimum, value);
                long penalty = Math.Max(p1, p2 * gamma / (gamma + Math.Abs(left[p] - left[q])));
                for (int d = 0; d < n; d++) {
                    long best = Math.Min(previous[d], minimum + penalty);
                    if (d > 0)
                        best = Math.Min(best, previous[d - 1] + p1);
                    if (d + 1 < n)
                        best = Math.Min(best, previous[d + 1] + p1);
                    result[p][d] = baseCosts[p][d] + best - minimum;
                }
            }
        }
        return result;
    }
    public static void Accumulate(long[][] total, long[][] path) {
        for (int p = 0; p < total.Length; p++)
            for (int d = 0; d < total[p].Length; d++)
                total[p][d] += path[p][d];
    }
}
