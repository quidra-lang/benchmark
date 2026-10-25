import java.util.List;

record Point(int x, int y) {}
record Segment(Point start, Point end) {}
record Rect(int x0, int y0, int x1, int y1) {
    boolean empty() { return x0 > x1 || y0 > y1; }
    boolean contains(Point p) { return x0 <= p.x() && p.x() <= x1 && y0 <= p.y() && p.y() <= y1; }
    Rect intersect(Rect other) { return new Rect(Math.max(x0,other.x0),Math.max(y0,other.y0),Math.min(x1,other.x1),Math.min(y1,other.y1)); }
}
record Color(int r, int g, int b, int a) implements Comparable<Color> {
    int component(int i) { return i == 0 ? r : i == 1 ? g : i == 2 ? b : a; }
    public int compareTo(Color other) { for (int i = 0; i < 4; i++) { int order = Integer.compare(component(i),other.component(i)); if (order != 0) return order; } return 0; }
    public String toString() { return r + " " + g + " " + b + " " + a; }
}
record Rgb(int r, int g, int b) implements Comparable<Rgb> {
    int component(int i) { return i == 0 ? r : i == 1 ? g : b; }
    public int compareTo(Rgb other) { for (int i = 0; i < 3; i++) { int order = Integer.compare(component(i),other.component(i)); if (order != 0) return order; } return 0; }
    public String toString() { return r + " " + g + " " + b; }
}
final class Canvas {
    static int floorDiv(int n, int d) { return Math.floorDiv(n,d); }
    static int round(int n, int d) { if (d < 0) { n = -n; d = -d; } return floorDiv(2 * n + d,2 * d); }
    static int effectiveAlpha(int alpha, int opacity) { return round(alpha * opacity,255); }
    static Rgb[][] composite(List<Layer> layers, Color background, int width, int height) {
        Rgb[][] image = new Rgb[height][width];
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) { Rgb color = new Rgb(background.r(),background.g(),background.b()); for (Layer layer : layers) color = layer.blend(new Point(x,y),color); image[y][x] = color; } return image;
    }
}
final class Layer {
    final int width, height, opacity;
    final String mode;
    final Color[] colors;
    final int[] lines;
    Layer(int width, int height, int opacity, String mode) { this.width = width; this.height = height; this.opacity = opacity; this.mode = mode; colors = new Color[width * height]; lines = new int[width * height]; }
    void paint(Point p, Color color, int line) { colors[p.y() * width + p.x()] = color; lines[p.y() * width + p.x()] = line; }
    boolean erase(Point p) { int i = p.y() * width + p.x(); boolean painted = colors[i] != null; colors[i] = null; return painted; }
    Color colorAt(Point p) { return colors[p.y() * width + p.x()]; }
    int lineAt(Point p) { return lines[p.y() * width + p.x()]; }
    int alphaAt(Point p) { Color color = colorAt(p); return color == null ? 0 : Canvas.effectiveAlpha(color.a(),opacity); }
    Rgb blend(Point p, Rgb current) {
        Color color = colorAt(p); if (color == null) return current; int alpha = Canvas.effectiveAlpha(color.a(),opacity); int[] values = new int[3];
        for (int i = 0; i < 3; i++) { int source = color.component(i), value = current.component(i); if (mode.equals("multiply")) source = Canvas.round(source * value,255); else if (mode.equals("screen")) source = 255 - Canvas.round((255 - source) * (255 - value),255); values[i] = Canvas.round(alpha * source + (255 - alpha) * value,255); } return new Rgb(values[0],values[1],values[2]);
    }
}
