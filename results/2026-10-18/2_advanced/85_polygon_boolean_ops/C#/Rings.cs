static class RingOps
{
    public static bool Inside(Point p, Ring ring)
    {
        bool odd = false;
        for (int i = 0; i < ring.Count; i++)
        {
            Point a = ring[i], b = ring[(i + 1) % ring.Count];
            if ((a.Y * p.D > p.Y * a.D) != (b.Y * p.D > p.Y * b.D))
            {
                Point lo = YCompare(a, b) < 0 ? a : b;
                Point hi = YCompare(a, b) < 0 ? b : a;
                if (Cross(lo, hi, p) > 0) odd = !odd;
            }
        }
        return odd;
    }
    public static bool Interior(Point p, Rings rings) => rings.Count(r => Inside(p, r)) % 2 == 1;
    public static bool Boundary(Point p, Ring ring) => Enumerable.Range(0, ring.Count).Any(i => Intersections.On(ring[i], ring[(i + 1) % ring.Count], p));
    public static Ring Rotate(Ring ring)
    {
        int i = ring.IndexOf(ring.Min()!);
        return ring.Skip(i).Concat(ring.Take(i)).ToList();
    }
    public static bool Ccw(Ring ring) => Cross(ring[^1], ring[0], ring[1]) > 0;
    public static Ring Reverse(Ring ring) => new[] { ring[0] }.Concat(ring.Skip(1).Reverse()).ToList();
    public static Rings Canonical(Rings input)
    {
        Rings rings = input.Select((r, i) => { Ring rotated = Rotate(r); return Ccw(rotated) == (i == 0) ? rotated : Reverse(rotated); }).ToList();
        return new[] { rings[0] }.Concat(rings.Skip(1).OrderBy(r => r[0])).ToList();
    }
    public static Region Assemble(Rings input)
    {
        Rings rings = input.Select(Rotate).ToList();
        int[] depth = Enumerable.Range(0, rings.Count).Select(i => Enumerable.Range(0, rings.Count).Count(j => i != j && Inside(rings[i][0], rings[j]))).ToArray();
        for (int i = 0; i < rings.Count; i++) if (Ccw(rings[i]) != (depth[i] % 2 == 0)) rings[i] = Reverse(rings[i]);
        return Enumerable.Range(0, rings.Count).Where(i => depth[i] % 2 == 0).OrderBy(i => rings[i][0]).Select(i =>
            new[] { rings[i] }.Concat(Enumerable.Range(0, rings.Count).Where(j => depth[j] == depth[i] + 1 && Inside(rings[j][0], rings[i])).OrderBy(j => rings[j][0]).Select(j => rings[j])).ToList()).ToList();
    }
    public static double Area(Ring ring)
    {
        double sum = 0;
        for (int i = 0; i < ring.Count; i++)
        {
            var (x, y) = ring[i].Real();
            var (u, v) = ring[(i + 1) % ring.Count].Real();
            sum += x * v - u * y;
        }
        return sum / 2;
    }
    public static double Perimeter(Ring ring)
    {
        double sum = 0;
        for (int i = 0; i < ring.Count; i++)
        {
            var (x, y) = ring[i].Real();
            var (u, v) = ring[(i + 1) % ring.Count].Real();
            double dx = u - x, dy = v - y;
            sum += Math.Sqrt(dx * dx + dy * dy);
        }
        return sum;
    }
    public static double TotalArea(Region region)
    {
        double sum = 0;
        foreach (Rings polygon in region) foreach (Ring ring in polygon) sum += Area(ring);
        return sum;
    }
}
