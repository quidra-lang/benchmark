import java.util.ArrayList;
import java.util.List;

record Boundary(int axis, int limit, boolean minimum) {
    boolean inside(Point p) { int value = axis == 0 ? p.x() : p.y(); return minimum ? value >= limit : value <= limit; }
    Point intersection(Point a, Point b) { return axis == 0 ? new Point(limit,a.y() + Canvas.round((limit - a.x()) * (b.y() - a.y()),b.x() - a.x())) : new Point(a.x() + Canvas.round((limit - a.y()) * (b.x() - a.x()),b.y() - a.y()),limit); }
}
final class Clipping {
    static int region(Point p, Rect clip) { return (p.x() < clip.x0() ? 1 : 0) | (p.x() > clip.x1() ? 2 : 0) | (p.y() < clip.y0() ? 4 : 0) | (p.y() > clip.y1() ? 8 : 0); }
    static Segment clipSegment(Point start, Point end, Rect clip) {
        while (true) {
            int first = region(start,clip), second = region(end,clip); if (first == 0 && second == 0) return new Segment(start,end); if ((first & second) != 0) return null;
            int code = first != 0 ? first : second; Point a = first != 0 ? start : end, b = first != 0 ? end : start, point;
            if ((code & 4) != 0) point = new Point(a.x() + Canvas.round((b.x() - a.x()) * (clip.y0() - a.y()),b.y() - a.y()),clip.y0());
            else if ((code & 8) != 0) point = new Point(a.x() + Canvas.round((b.x() - a.x()) * (clip.y1() - a.y()),b.y() - a.y()),clip.y1());
            else if ((code & 2) != 0) point = new Point(clip.x1(),a.y() + Canvas.round((b.y() - a.y()) * (clip.x1() - a.x()),b.x() - a.x()));
            else point = new Point(clip.x0(),a.y() + Canvas.round((b.y() - a.y()) * (clip.x0() - a.x()),b.x() - a.x()));
            if (first != 0) start = point; else end = point;
        }
    }
    static List<Point> clipPolygon(List<Point> vertices, Rect clip) {
        for (Boundary boundary : List.of(new Boundary(0,clip.x0(),true),new Boundary(0,clip.x1() + 1,false),new Boundary(1,clip.y0(),true),new Boundary(1,clip.y1() + 1,false))) {
            List<Point> output = new ArrayList<>();
            for (int i = 0; i < vertices.size(); i++) { Point start = vertices.get(i == 0 ? vertices.size() - 1 : i - 1), end = vertices.get(i); if (boundary.inside(end)) { if (!boundary.inside(start)) output.add(boundary.intersection(start,end)); output.add(end); } else if (boundary.inside(start)) output.add(boundary.intersection(start,end)); } vertices = output;
        }
        return vertices;
    }
}
