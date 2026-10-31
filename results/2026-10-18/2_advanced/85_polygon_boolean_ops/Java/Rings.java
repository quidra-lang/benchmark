import java.util.*;
final class Rings {
    record Polygon(List<List<Rational.Point>> rings) {}
    record Edge(Rational.Point first, Rational.Point second) {}
    static List<Edge> edges(List<Rational.Point> ring) {
        List<Edge> result = new ArrayList<>();
        for (int i = 0; i < ring.size(); i++)
            result.add(new Edge(ring.get(i), ring.get((i + 1) % ring.size())));
        return result;
    }
    static boolean inside(List<Rational.Point> ring, Rational.Point point) {
        boolean parity = false;
        for (Edge edge : edges(ring)) {
            Rational.Point a = edge.first(), b = edge.second();
            if ((a.y().compareTo(point.y()) > 0) != (b.y().compareTo(point.y()) > 0)) {
                Rational.Point low = a.y().compareTo(b.y()) < 0 ? a : b, high = low == a ? b : a;
                if (Rational.cross(low, high, point).sign() > 0)
                    parity = !parity;
            }
        }
        return parity;
    }
    static boolean interior(List<List<Rational.Point>> rings, Rational.Point point) {
        boolean parity = false;
        for (List<Rational.Point> ring : rings)
            if (inside(ring, point))
                parity = !parity;
        return parity;
    }
    static boolean boundary(List<Rational.Point> ring, Rational.Point point) {
        for (Edge edge : edges(ring))
            if (Intersections.onSegment(point, edge.first(), edge.second()))
                return true;
        return false;
    }
    static List<Rational.Point> rotate(List<Rational.Point> ring) {
        int start = ring.indexOf(Collections.min(ring));
        List<Rational.Point> result = new ArrayList<>(ring.subList(start, ring.size()));
        result.addAll(ring.subList(0, start));
        return result;
    }
    static boolean counterclockwise(List<Rational.Point> ring) {
        return Rational.cross(ring.getLast(), ring.getFirst(), ring.get(1)).sign() > 0;
    }
    static List<Rational.Point> reverse(List<Rational.Point> ring) {
        List<Rational.Point> result = new ArrayList<>();
        result.add(ring.getFirst());
        for (int i = ring.size() - 1; i > 0; i--)
            result.add(ring.get(i));
        return result;
    }
    static List<Rational.Point> normalize(List<Rational.Point> ring, boolean outer) {
        List<Rational.Point> rotated = rotate(ring);
        return counterclockwise(rotated) == outer ? rotated : reverse(rotated);
    }
    static List<Polygon> assemble(List<List<Rational.Point>> resultRings) {
        List<List<Rational.Point>> rotated = new ArrayList<>();
        for (List<Rational.Point> ring : resultRings)
            rotated.add(rotate(ring));
        int[] depths = new int[rotated.size()];
        for (int i = 0; i < rotated.size(); i++)
            for (int j = 0; j < rotated.size(); j++)
                if (i != j && inside(rotated.get(j), rotated.get(i).getFirst()))
                    depths[i]++;
        List<List<Rational.Point>> oriented = new ArrayList<>();
        List<Integer> outerIndices = new ArrayList<>();
        for (int i = 0; i < rotated.size(); i++) {
            List<Rational.Point> ring = rotated.get(i);
            boolean outer = depths[i] % 2 == 0;
            oriented.add(counterclockwise(ring) == outer ? ring : reverse(ring));
            if (outer)
                outerIndices.add(i);
        }
        outerIndices.sort(Comparator.comparing(i -> oriented.get(i).getFirst()));
        List<Polygon> result = new ArrayList<>();
        for (int index : outerIndices) {
            List<Rational.Point> outer = oriented.get(index);
            List<List<Rational.Point>> holes = new ArrayList<>();
            for (int j = 0; j < oriented.size(); j++)
                if (depths[j] == depths[index] + 1 && inside(outer, oriented.get(j).getFirst()))
                    holes.add(oriented.get(j));
            holes.sort(Comparator.comparing(List::getFirst));
            List<List<Rational.Point>> polygon = new ArrayList<>();
            polygon.add(outer);
            polygon.addAll(holes);
            result.add(new Polygon(polygon));
        }
        return result;
    }
    static double area(List<Rational.Point> ring) {
        double total = 0;
        for (Edge edge : edges(ring)) {
            double x1 = edge.first().x().real(), y1 = edge.first().y().real(),
                   x2 = edge.second().x().real(), y2 = edge.second().y().real();
            total += x1 * y2 - x2 * y1;
        }
        return total / 2;
    }
    static double perimeter(List<Rational.Point> ring) {
        double total = 0;
        for (Edge edge : edges(ring)) {
            double x1 = edge.first().x().real(), y1 = edge.first().y().real(),
                   x2 = edge.second().x().real(), y2 = edge.second().y().real(), dx = x2 - x1,
                   dy = y2 - y1;
            total += Math.sqrt(dx * dx + dy * dy);
        }
        return total;
    }
    static List<List<Rational.Point>> flatten(List<Polygon> polygons) {
        List<List<Rational.Point>> rings = new ArrayList<>();
        for (Polygon polygon : polygons)
            rings.addAll(polygon.rings());
        return rings;
    }
}
