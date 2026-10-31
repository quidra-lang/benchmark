import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class Primitives {
    static List<Point> bresenham(Point start, Point end) {
        int x = start.x(), y = start.y(), dx = Math.abs(end.x() - x), dy = -Math.abs(end.y() - y), sx = x < end.x() ? 1 : -1, sy = y < end.y() ? 1 : -1, error = dx + dy; List<Point> points = new ArrayList<>();
        while (true) { points.add(new Point(x,y)); if (x == end.x() && y == end.y()) return points; int doubled = 2 * error; if (doubled >= dy) { error += dy; x += sx; } if (doubled <= dx) { error += dx; y += sy; } }
    }
    static List<Point> expandSquare(Point p, int width) { int low = -((width - 1) / 2); List<Point> points = new ArrayList<>(); for (int j = low; j < low + width; j++) for (int i = low; i < low + width; i++) points.add(new Point(p.x() + i,p.y() + j)); return points; }
    static Set<Point> circle(int radius) {
        Set<Point> points = new HashSet<>(); int a = radius, b = 0, error = 1 - radius;
        while (a >= b) { points.addAll(List.of(new Point(a,b),new Point(b,a),new Point(-b,a),new Point(-a,b),new Point(-a,-b),new Point(-b,-a),new Point(b,-a),new Point(a,-b))); b++; if (error < 0) error += 2 * b + 1; else { a--; error += 2 * (b - a) + 1; } } return points;
    }
    static void quadrants(Set<Point> points, int x, int y) { points.addAll(List.of(new Point(x,y),new Point(-x,y),new Point(x,-y),new Point(-x,-y))); }
    static Set<Point> ellipse(int rx, int ry) {
        int rx2 = rx * rx, ry2 = ry * ry, x = 0, y = ry; Set<Point> points = new HashSet<>(List.of(new Point(0,ry),new Point(0,-ry)));
        while (ry2 * x < rx2 * y) { int decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2; x++; if (decision >= 0) y--; quadrants(points,x,y); }
        while (y > 0) { int decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2; y--; if (decision <= 0) x++; quadrants(points,x,y); } return points;
    }
    static List<Point> bezier(List<Point> controls, int segments) {
        boolean cubic = controls.size() == 4; int scale = segments * segments * (cubic ? segments : 1); List<Point> points = new ArrayList<>();
        for (int i = 0; i <= segments; i++) { int rest = segments - i; int[] weights = cubic ? new int[] { rest * rest * rest,3 * i * rest * rest,3 * i * i * rest,i * i * i } : new int[] { rest * rest,2 * i * rest,i * i }; int x = 0, y = 0; for (int j = 0; j < weights.length; j++) { x += weights[j] * controls.get(j).x(); y += weights[j] * controls.get(j).y(); } points.add(new Point(Canvas.round(x,scale),Canvas.round(y,scale))); } return points;
    }
}
