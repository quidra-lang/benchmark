static class Primitives
{
    public static List<Point> Bresenham(Point start, Point end)
    {
        int x = start.X, y = start.Y, dx = Math.Abs(end.X - x), dy = -Math.Abs(end.Y - y), sx = x < end.X ? 1 : -1, sy = y < end.Y ? 1 : -1, error = dx + dy; List<Point> result = [];
        while (true) { result.Add(new(x,y)); if (x == end.X && y == end.Y) return result; int doubled = 2 * error; if (doubled >= dy) { error += dy; x += sx; } if (doubled <= dx) { error += dx; y += sy; } }
    }
    public static IEnumerable<Point> ExpandSquare(Point p, int width) { int low = -((width - 1) / 2); for (int j = low; j < low + width; j++) for (int i = low; i < low + width; i++) yield return new(p.X + i,p.Y + j); }
    public static HashSet<Point> Circle(int radius)
    {
        HashSet<Point> points = []; int a = radius, b = 0, error = 1 - radius;
        while (a >= b) { points.UnionWith([new(a,b),new(b,a),new(-b,a),new(-a,b),new(-a,-b),new(-b,-a),new(b,-a),new(a,-b)]); b++; if (error < 0) error += 2 * b + 1; else { a--; error += 2 * (b - a) + 1; } } return points;
    }
    static void Quadrants(HashSet<Point> points, int x, int y) => points.UnionWith([new(x,y),new(-x,y),new(x,-y),new(-x,-y)]);
    public static HashSet<Point> Ellipse(int rx, int ry)
    {
        int rx2 = rx * rx, ry2 = ry * ry, x = 0, y = ry; HashSet<Point> points = [new(0,ry),new(0,-ry)];
        while (ry2 * x < rx2 * y) { int decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2; x++; if (decision >= 0) y--; Quadrants(points,x,y); }
        while (y > 0) { int decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2; y--; if (decision <= 0) x++; Quadrants(points,x,y); } return points;
    }
    public static List<Point> Bezier(List<Point> controls, int segments)
    {
        bool cubic = controls.Count == 4; int scale = segments * segments * (cubic ? segments : 1); List<Point> points = [];
        for (int i = 0; i <= segments; i++) { int rest = segments - i; int[] weights = cubic ? [rest * rest * rest,3 * i * rest * rest,3 * i * i * rest,i * i * i] : [rest * rest,2 * i * rest,i * i]; int x = 0, y = 0; for (int j = 0; j < weights.Length; j++) { x += weights[j] * controls[j].X; y += weights[j] * controls[j].Y; } points.Add(new(CanvasMath.Round(x,scale),CanvasMath.Round(y,scale))); } return points;
    }
}
