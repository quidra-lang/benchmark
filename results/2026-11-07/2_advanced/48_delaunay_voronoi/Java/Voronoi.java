import java.util.*;

final class Voronoi {
    record Vertex(Predicates.Center center, double r2, String position) {}
    record RealPoint(double x, double y) {}
    static double radius2(Predicates.Point a, Predicates.Point b, Predicates.Point c) {
        long area = Predicates.orient(a, b, c);
        return (((double)Predicates.d2(a, b) * Predicates.d2(b, c)) * Predicates.d2(c, a)) /
            ((4.0 * area) * area);
    }
    static String position(Predicates.Center v, List<Integer> hull, List<Predicates.Point> points) {
        boolean on = false;
        for (int i = 0; i < hull.size(); i++) {
            Predicates.Point a = points.get(hull.get(i)), b = points.get(hull.get((i + 1) % hull.size()));
            long sigma =
                (b.x() - a.x()) * (v.y() - a.y() * v.d()) - (b.y() - a.y()) * (v.x() - a.x() * v.d());
            if (sigma < 0)
                return "outside";
            if (sigma == 0)
                on = true;
        }
        return on ? "on" : "inside";
    }
    static Predicates.Point outward(Predicates.Point a, Predicates.Point b) {
        return Predicates.reduce(b.y() - a.y(), a.x() - b.x());
    }
    static List<Integer> neighbors(int site, List<Integer> adjacent,
                                   Map<Triangulation.Edge, Integer> directed, Integer next) {
        int start = next == null ? Collections.min(adjacent) : next;
        List<Integer> result = new ArrayList<>();
        int current = start;
        while (true) {
            result.add(current);
            Integer following = directed.get(new Triangulation.Edge(site, current));
            if (following == null || following == start)
                break;
            current = following;
        }
        return result;
    }
    static double area(int site, List<Integer> vertexIds, List<Vertex> vertices,
                       List<Predicates.Point> points) {
        Predicates.Point origin = points.get(site);
        double sum = 0;
        for (int i = 0; i < vertexIds.size(); i++) {
            Predicates.Center a = vertices.get(vertexIds.get(i) - 1).center(),
                              b = vertices.get(vertexIds.get((i + 1) % vertexIds.size()) - 1).center();
            double u = (double)a.x() / a.d() - origin.x(), w = (double)a.y() / a.d() - origin.y(),
                   un = (double)b.x() / b.d() - origin.x(), wn = (double)b.y() / b.d() - origin.y();
            sum += u * wn - un * w;
        }
        return sum / 2;
    }
    static double clipped(int site, List<Integer> neighbors, List<Predicates.Point> points) {
        List<RealPoint> polygon = new ArrayList<>(List.of(new RealPoint(0, 0), new RealPoint(1000, 0),
                                                          new RealPoint(1000, 1000), new RealPoint(0, 1000)));
        Predicates.Point s = points.get(site);
        for (int neighbor : neighbors) {
            Predicates.Point t = points.get(neighbor);
            long c1 = 2 * (t.x() - s.x()), c2 = 2 * (t.y() - s.y()),
                 c3 = t.x() * t.x() + t.y() * t.y() - s.x() * s.x() - s.y() * s.y();
            List<RealPoint> next = new ArrayList<>();
            for (int i = 0; i < polygon.size(); i++) {
                RealPoint a = polygon.get(i), b = polygon.get((i + 1) % polygon.size());
                double fa = c1 * a.x() + c2 * a.y() - c3, fb = c1 * b.x() + c2 * b.y() - c3;
                if (fa <= 0)
                    next.add(a);
                if (fa < 0 && fb > 0 || fb < 0 && fa > 0) {
                    double lambda = fa / (fa - fb);
                    next.add(
                        new RealPoint(a.x() + (b.x() - a.x()) * lambda, a.y() + (b.y() - a.y()) * lambda));
                }
            }
            polygon = next;
        }
        double sum = 0;
        for (int i = 0; i < polygon.size(); i++) {
            RealPoint a = polygon.get(i), b = polygon.get((i + 1) % polygon.size());
            sum += a.x() * b.y() - b.x() * a.y();
        }
        return sum / 2;
    }
}
