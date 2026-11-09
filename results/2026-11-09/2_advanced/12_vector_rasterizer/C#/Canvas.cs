readonly record struct Point(int X, int Y);
readonly record struct Segment(Point Start, Point End);
readonly record struct Rect(int X0, int Y0, int X1, int Y1)
{
    public bool Empty => X0 > X1 || Y0 > Y1;
    public bool Contains(Point p) => X0 <= p.X && p.X <= X1 && Y0 <= p.Y && p.Y <= Y1;
    public Rect Intersect(Rect other) => new(Math.Max(X0,other.X0),Math.Max(Y0,other.Y0),Math.Min(X1,other.X1),Math.Min(Y1,other.Y1));
}
readonly record struct Color(int R, int G, int B, int A) : IComparable<Color>
{
    public int CompareTo(Color other) => (R,G,B,A).CompareTo((other.R,other.G,other.B,other.A));
    public int this[int i] => i == 0 ? R : i == 1 ? G : i == 2 ? B : A;
    public override string ToString() => $"{R} {G} {B} {A}";
}
readonly record struct Rgb(int R, int G, int B) : IComparable<Rgb>
{
    public int CompareTo(Rgb other) => (R,G,B).CompareTo((other.R,other.G,other.B));
    public int this[int i] => i == 0 ? R : i == 1 ? G : B;
    public override string ToString() => $"{R} {G} {B}";
}
static class CanvasMath
{
    public static int FloorDiv(int n, int d) => n / d - (n % d < 0 ? 1 : 0);
    public static int Round(int n, int d) { if (d < 0) { n = -n; d = -d; } return FloorDiv(2 * n + d,2 * d); }
    public static int EffectiveAlpha(int alpha, int opacity) => Round(alpha * opacity,255);
    public static Rgb[][] Composite(List<Layer> layers, Color background, int width, int height)
    {
        Rgb[][] image = Enumerable.Range(0,height).Select(_ => new Rgb[width]).ToArray();
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) { Rgb color = new(background.R,background.G,background.B); foreach (Layer layer in layers) color = layer.Blend(new(x,y),color); image[y][x] = color; } return image;
    }
}
sealed class Layer(int width, int height, int opacity, string mode)
{
    public int Width = width, Height = height, Opacity = opacity;
    public string Mode = mode;
    readonly Color?[] colors = new Color?[width * height];
    readonly int[] lines = new int[width * height];
    public void Paint(Point p, Color color, int line) { colors[p.Y * Width + p.X] = color; lines[p.Y * Width + p.X] = line; }
    public bool Erase(Point p) { int i = p.Y * Width + p.X; bool painted = colors[i].HasValue; colors[i] = null; return painted; }
    public Color? ColorAt(Point p) => colors[p.Y * Width + p.X];
    public int LineAt(Point p) => lines[p.Y * Width + p.X];
    public int AlphaAt(Point p) => ColorAt(p) is Color color ? CanvasMath.EffectiveAlpha(color.A,Opacity) : 0;
    public Rgb Blend(Point p, Rgb current)
    {
        if (ColorAt(p) is not Color color) return current; int alpha = CanvasMath.EffectiveAlpha(color.A,Opacity); int[] values = new int[3];
        for (int c = 0; c < 3; c++) { int source = color[c], value = current[c]; if (Mode == "multiply") source = CanvasMath.Round(source * value,255); else if (Mode == "screen") source = 255 - CanvasMath.Round((255 - source) * (255 - value),255); values[c] = CanvasMath.Round(alpha * source + (255 - alpha) * value,255); } return new(values[0],values[1],values[2]);
    }
}
