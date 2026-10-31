import java.util.*;

record Cell(int x, int y) {}
record Neighborhood(int[] points, int candidates) {}
final class GridIndex {
    final List<Point> points;
    final int radius;
    final Map<Cell, List<Integer>> cells = new HashMap<>();
    GridIndex(List<Point> points, int radius) {
        this.points = points;
        this.radius = radius;
        for (int i = 0; i < points.size(); i++) {
            Point point = points.get(i);
            Cell cell = new Cell(point.x() / radius, point.y() / radius);
            cells.computeIfAbsent(cell, key -> new ArrayList<>()).add(i);
        }
    }
    static int distance(Point a, Point b) {
        int x = a.x() - b.x(), y = a.y() - b.y();
        return x * x + y * y;
    }
    Neighborhood neighborhood(int index) {
        Point point = points.get(index);
        int x = point.x() / radius, y = point.y() / radius, candidates = 0;
        List<Integer> neighbors = new ArrayList<>();
        for (int row = y - 1; row <= y + 1; row++)
            for (int column = x - 1; column <= x + 1; column++)
                for (int other : cells.getOrDefault(new Cell(column, row), List.of())) {
                    candidates++;
                    if (distance(point, points.get(other)) <= radius * radius)
                        neighbors.add(other);
                }
        return new Neighborhood(neighbors.stream().mapToInt(Integer::intValue).toArray(), candidates);
    }
    Cell busiest() {
        Cell best = null;
        for (Map.Entry<Cell, List<Integer>> entry : cells.entrySet()) {
            Cell cell = entry.getKey();
            if (best == null || entry.getValue().size() > cells.get(best).size() ||
                entry.getValue().size() == cells.get(best).size() &&
                    (cell.y() < best.y() || cell.y() == best.y() && cell.x() < best.x()))
                best = cell;
        }
        return best;
    }
    int[] bruteCounts() {
        int[] counts = new int[points.size()];
        for (int i = 0; i < points.size(); i++)
            for (Point point : points)
                if (distance(points.get(i), point) <= radius * radius)
                    counts[i]++;
        return counts;
    }
}
