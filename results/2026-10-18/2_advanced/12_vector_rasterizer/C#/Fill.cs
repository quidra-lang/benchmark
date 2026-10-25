static class Fill
{
    public static HashSet<Point> Polygons(List<List<Point>> sequences, string rule, Rect clip)
    {
        List<Segment> edges = []; foreach (List<Point> vertices in sequences) for (int i = 0; i < vertices.Count; i++) { Point a = vertices[i], b = vertices[(i + 1) % vertices.Count]; if (a.Y != b.Y) edges.Add(new(a,b)); } HashSet<Point> result = [];
        for (int y = clip.Y0; y <= clip.Y1; y++)
        {
            List<(int X, int Direction)> crossings = [];
            foreach (Segment edge in edges) { Point a = edge.Start, b = edge.End; if (Math.Min(a.Y,b.Y) <= y && y < Math.Max(a.Y,b.Y)) { int d = b.Y - a.Y, n = 2 * a.X * d + (2 * y + 1 - 2 * a.Y) * (b.X - a.X); if (d < 0) { n = -n; d = -d; } crossings.Add((CanvasMath.FloorDiv(n - d,2 * d) + 1,b.Y > a.Y ? 1 : -1)); } }
            crossings.Sort(); int index = 0, count = 0, winding = 0;
            for (int x = clip.X0; x <= clip.X1; x++) { while (index < crossings.Count && crossings[index].X <= x) { count++; winding += crossings[index++].Direction; } if (rule == "evenodd" ? count % 2 != 0 : winding != 0) result.Add(new(x,y)); }
        }
        return result;
    }
    public static HashSet<Point> Shape(Point center, HashSet<Point> shape, Rect clip)
    {
        Dictionary<int, int> extents = []; foreach (Point p in shape) extents[p.Y] = Math.Max(extents.GetValueOrDefault(p.Y),Math.Abs(p.X)); HashSet<Point> result = [];
        foreach (var extent in extents) { int y = center.Y + extent.Key; if (y < clip.Y0 || y > clip.Y1) continue; for (int x = Math.Max(clip.X0,center.X - extent.Value); x <= Math.Min(clip.X1,center.X + extent.Value); x++) result.Add(new(x,y)); } return result;
    }
    public static HashSet<Point> Flood(Layer layer, Point seed, Rect clip)
    {
        Color? target = layer.ColorAt(seed); HashSet<Point> result = [seed]; Stack<Point> pending = new(); pending.Push(seed);
        while (pending.Count > 0) { Point p = pending.Pop(); foreach (Point next in new Point[] { new(p.X + 1,p.Y),new(p.X - 1,p.Y),new(p.X,p.Y + 1),new(p.X,p.Y - 1) }) if (clip.Contains(next) && !result.Contains(next) && layer.ColorAt(next) == target) { result.Add(next); pending.Push(next); } } return result;
    }
}
