import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

public class Main {
    record Point(int x, int y) {}

    static int cross(Point o, Point a, Point b) {
        return (a.x() - o.x()) * (b.y() - o.y()) - (a.y() - o.y()) * (b.x() - o.x());
    }

    static List<Point> chain(List<Point> points) {
        List<Point> result = new ArrayList<>();
        for (Point point : points) {
            while (result.size() >= 2 && cross(result.get(result.size() - 2), result.getLast(), point) <= 0) {
                result.removeLast();
            }
            result.add(point);
        }
        return result;
    }

    public static void main(String[] args) {
        List<Point> points = new ArrayList<>(List.of(
                new Point(3, 2), new Point(-6, 1), new Point(8, 4), new Point(0, 0), new Point(-3, 7),
                new Point(4, -3), new Point(1, -5), new Point(-2, 1), new Point(5, 6), new Point(-6, -2),
                new Point(2, -2), new Point(7, -1), new Point(-3, 4), new Point(2, 8), new Point(-6, 3)));
        points.sort(Comparator.comparingInt(Point::x).thenComparingInt(Point::y));
        List<Point> lower = chain(points);
        List<Point> upper = chain(points.reversed());
        lower.removeLast();
        upper.removeLast();
        lower.addAll(upper);
        int crossSum = 0;
        System.out.println("hull: " + lower.size() + " points");
        for (int i = 0; i < lower.size(); i++) {
            Point a = lower.get(i), b = lower.get((i + 1) % lower.size());
            System.out.println("(" + a.x() + ", " + a.y() + ")");
            crossSum += a.x() * b.y() - b.x() * a.y();
        }
        System.out.printf(Locale.ROOT, "area: %.1f%n", crossSum / 2.0);
    }
}
