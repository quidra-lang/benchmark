using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Hough {
    public static int FloorDivision(int a, int b) {
        int q = a / b;
        return a % b < 0 ? q - 1 : q;
    }
    public record CircleCell(int r, int x, int y, int votes, int total) {
    }
    public record LineCell(int t, int r, int votes) {
    }
    public sealed class CircleVotes {
        public Dictionary<int, List<PgmIo.Point>> outlines = new();
        public Dictionary<int, int[][]> votes = new();
        public List<CircleCell> peaks = new();
        public int candidates;
    }
    public sealed class LineVotes {
        public int low, high, maximum;
        public int[][] votes;
        public List<LineCell> peaks = new();
        public int Count(int t, int r) {
            return t < 0 || t >= 180 || r < low || r > high ? 0 : votes[t][r - low];
        }
    }
    public static int Rho(PgmIo.Point p, int t, int[][] trig, int step) {
        return Hough.FloorDivision(p.x * trig[t][0] + p.y * trig[t][1], 16384 * step);
    }
    public static List<PgmIo.Point> CirclePoints(int radius) {
        HashSet<PgmIo.Point> points = new();
        int a = radius, b = 0, e = 1 - radius;
        while (a >= b) {
            points.Add(new PgmIo.Point(a, b));
            points.Add(new PgmIo.Point(b, a));
            points.Add(new PgmIo.Point(-b, a));
            points.Add(new PgmIo.Point(-a, b));
            points.Add(new PgmIo.Point(-a, -b));
            points.Add(new PgmIo.Point(-b, -a));
            points.Add(new PgmIo.Point(b, -a));
            points.Add(new PgmIo.Point(a, -b));
            b++;
            if (e < 0)
                e += 2 * b + 1;
            else {
                a--;
                e += 2 * (b - a) + 1;
            }
        }
        return new(points);
    }
    public static int Compare(CircleCell a, CircleCell b) {
        int c = (b.votes * a.total).CompareTo(a.votes * b.total);
        if (c == 0)
            c = a.r.CompareTo(b.r);
        if (c == 0)
            c = a.y.CompareTo(b.y);
        if (c == 0)
            c = a.x.CompareTo(b.x);
        return c;
    }
    public static CircleVotes Circles(List<PgmIo.Point> edges, int width, int height, PgmIo.Params settings) {
        CircleVotes result = new CircleVotes();
        int minimum = settings.Get("circle_min_radius"), maximum = settings.Get("circle_max_radius");
        for (int r = minimum; r <= maximum; r++) {
            List<PgmIo.Point> offsets = CirclePoints(r);
            result.outlines[r] = offsets;
            int[][] votes = Enumerable.Range(0, height)
                                .Select(
                                    _ => new int[width])
                                .ToArray();
            foreach (PgmIo.Point p in edges)
                foreach (PgmIo.Point o in offsets) {
                    int x = p.x + o.x, y = p.y + o.y;
                    if (Canny.Inside(x, y, width, height))
                        votes[y][x]++;
                }
            result.votes[r] = votes;
        }
        for (int r = minimum; r <= maximum; r++)
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++) {
                    int votes = result.votes[r][y][x], total = result.outlines[r].Count;
                    if (100 * votes < settings.Get("circle_min_percent") * total)
                        continue;
                    result.candidates++;
                    bool peak = true;
                    for (int rr = Math.Max(minimum, r - 2); rr <= Math.Min(maximum, r + 2); rr++)
                        for (int yy = Math.Max(0, y - 2); yy <= Math.Min(height - 1, y + 2); yy++)
                            for (int xx = Math.Max(0, x - 2); xx <= Math.Min(width - 1, x + 2); xx++) {
                                if (rr == r && xx == x && yy == y)
                                    continue;
                                int left = votes * result.outlines[rr].Count,
                                    right = result.votes[rr][yy][xx] * total;
                                bool before = rr < r || rr == r && (yy < y || yy == y && xx < x);
                                if (left < right || left == right && before)
                                    peak = false;
                            }
                    if (peak)
                        result.peaks.Add(new CircleCell(r, x, y, votes, total));
                }
        result.peaks.Sort(Comparer<CircleCell>.Create(Compare));
        return result;
    }
    public static LineVotes Lines(List<PgmIo.Point> edges, int width, int height, int[][] trig, int step,
                                  int threshold) {
        LineVotes result = new LineVotes();
        result.low = int.MaxValue;
        result.high = int.MinValue;
        List<PgmIo.Point> corners = [
            new PgmIo.Point(0, 0), new PgmIo.Point(width - 1, 0), new PgmIo.Point(0, height - 1),
            new PgmIo.Point(width - 1, height - 1)
        ];
        for (int t = 0; t < 180; t++)
            foreach (PgmIo.Point p in corners) {
                int r = Rho(p, t, trig, step);
                result.low = Math.Min(result.low, r);
                result.high = Math.Max(result.high, r);
            }
        result.votes = Enumerable.Range(0, 180)
                           .Select(
                               _ => new int[result.high - result.low + 1])
                           .ToArray();
        foreach (PgmIo.Point p in edges)
            for (int t = 0; t < 180; t++) {
                int r = Rho(p, t, trig, step);
                result.maximum = Math.Max(result.maximum, ++result.votes[t][r - result.low]);
            }
        for (int t = 0; t < 180; t++)
            for (int r = result.low; r <= result.high; r++) {
                int count = result.Count(t, r);
                if (count < threshold)
                    continue;
                bool peak = true;
                for (int tt = t - 2; tt <= t + 2; tt++)
                    for (int rr = r - 2; rr <= r + 2; rr++) {
                        if (tt == t && rr == r)
                            continue;
                        int other = result.Count(tt, rr);
                        if (other > count || other == count && (tt < t || tt == t && rr < r))
                            peak = false;
                    }
                if (peak)
                    result.peaks.Add(new LineCell(t, r, count));
            }
        result.peaks.Sort(Comparer<LineCell>.Create((a, b) => a.votes != b.votes ? b.votes.CompareTo(a.votes)
                                                              : a.t != b.t       ? a.t.CompareTo(b.t)
                                                                                 : a.r.CompareTo(b.r)));
        return result;
    }
}
