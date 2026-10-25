import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

record Crossing(int x, int direction) {}
final class Fill {
    static Set<Point> polygons(List<List<Point>> sequences, String rule, Rect clip) {
        List<Segment> edges = new ArrayList<>(); for (List<Point> vertices : sequences) for (int i = 0; i < vertices.size(); i++) { Point a = vertices.get(i), b = vertices.get((i + 1) % vertices.size()); if (a.y() != b.y()) edges.add(new Segment(a,b)); } Set<Point> result = new HashSet<>();
        for (int y = clip.y0(); y <= clip.y1(); y++) {
            List<Crossing> crossings = new ArrayList<>();
            for (Segment edge : edges) { Point a = edge.start(), b = edge.end(); if (Math.min(a.y(),b.y()) <= y && y < Math.max(a.y(),b.y())) { int d = b.y() - a.y(), n = 2 * a.x() * d + (2 * y + 1 - 2 * a.y()) * (b.x() - a.x()); if (d < 0) { n = -n; d = -d; } crossings.add(new Crossing(Canvas.floorDiv(n - d,2 * d) + 1,b.y() > a.y() ? 1 : -1)); } }
            crossings.sort(Comparator.comparingInt(Crossing::x).thenComparingInt(Crossing::direction)); int index = 0, count = 0, winding = 0;
            for (int x = clip.x0(); x <= clip.x1(); x++) { while (index < crossings.size() && crossings.get(index).x() <= x) { count++; winding += crossings.get(index++).direction(); } if (rule.equals("evenodd") ? count % 2 != 0 : winding != 0) result.add(new Point(x,y)); }
        }
        return result;
    }
    static Set<Point> shape(Point center, Set<Point> shape, Rect clip) {
        Map<Integer, Integer> extents = new HashMap<>(); for (Point point : shape) extents.merge(point.y(),Math.abs(point.x()),Math::max); Set<Point> pixels = new HashSet<>();
        for (Map.Entry<Integer, Integer> extent : extents.entrySet()) { int y = center.y() + extent.getKey(); if (y < clip.y0() || y > clip.y1()) continue; for (int x = Math.max(clip.x0(),center.x() - extent.getValue()); x <= Math.min(clip.x1(),center.x() + extent.getValue()); x++) pixels.add(new Point(x,y)); } return pixels;
    }
    static Set<Point> flood(Layer layer, Point seed, Rect clip) {
        Color target = layer.colorAt(seed); Set<Point> pixels = new HashSet<>(); pixels.add(seed); ArrayDeque<Point> pending = new ArrayDeque<>(); pending.addLast(seed);
        while (!pending.isEmpty()) { Point p = pending.removeLast(); for (Point next : List.of(new Point(p.x() + 1,p.y()),new Point(p.x() - 1,p.y()),new Point(p.x(),p.y() + 1),new Point(p.x(),p.y() - 1))) if (clip.contains(next) && !pixels.contains(next) && Objects.equals(layer.colorAt(next),target)) { pixels.add(next); pending.addLast(next); } } return pixels;
    }
}
