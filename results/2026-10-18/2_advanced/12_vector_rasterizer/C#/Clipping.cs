static class Clipping
{
    static int Region(Point p, Rect clip) => (p.X < clip.X0 ? 1 : 0) | (p.X > clip.X1 ? 2 : 0) | (p.Y < clip.Y0 ? 4 : 0) | (p.Y > clip.Y1 ? 8 : 0);
    public static Segment? ClipSegment(Point start, Point end, Rect clip)
    {
        while (true)
        {
            int first = Region(start,clip), second = Region(end,clip); if (first == 0 && second == 0) return new(start,end); if ((first & second) != 0) return null;
            int code = first != 0 ? first : second; Point a = first != 0 ? start : end, b = first != 0 ? end : start;
            Point point = (code & 4) != 0 ? new(a.X + CanvasMath.Round((b.X - a.X) * (clip.Y0 - a.Y),b.Y - a.Y),clip.Y0) : (code & 8) != 0 ? new(a.X + CanvasMath.Round((b.X - a.X) * (clip.Y1 - a.Y),b.Y - a.Y),clip.Y1) : (code & 2) != 0 ? new(clip.X1,a.Y + CanvasMath.Round((b.Y - a.Y) * (clip.X1 - a.X),b.X - a.X)) : new(clip.X0,a.Y + CanvasMath.Round((b.Y - a.Y) * (clip.X0 - a.X),b.X - a.X));
            if (first != 0) start = point; else end = point;
        }
    }
    public static List<Point> ClipPolygon(List<Point> vertices, Rect clip)
    {
        foreach (var boundary in new[] { (Axis: 0,Limit: clip.X0,Minimum: true),(Axis: 0,Limit: clip.X1 + 1,Minimum: false),(Axis: 1,Limit: clip.Y0,Minimum: true),(Axis: 1,Limit: clip.Y1 + 1,Minimum: false) })
        {
            bool Inside(Point p) { int value = boundary.Axis == 0 ? p.X : p.Y; return boundary.Minimum ? value >= boundary.Limit : value <= boundary.Limit; }
            Point Intersection(Point a, Point b) => boundary.Axis == 0 ? new(boundary.Limit,a.Y + CanvasMath.Round((boundary.Limit - a.X) * (b.Y - a.Y),b.X - a.X)) : new(a.X + CanvasMath.Round((boundary.Limit - a.Y) * (b.X - a.X),b.Y - a.Y),boundary.Limit);
            List<Point> output = []; for (int i = 0; i < vertices.Count; i++) { Point start = vertices[i == 0 ? vertices.Count - 1 : i - 1], end = vertices[i]; if (Inside(end)) { if (!Inside(start)) output.Add(Intersection(start,end)); output.Add(end); } else if (Inside(start)) output.Add(Intersection(start,end)); } vertices = output;
        }
        return vertices;
    }
}
