import java.util.*;

final class Triangulation {
    record Edge(int a, int b) implements Comparable<Edge> {
        public int compareTo(Edge e) {
            int c = Integer.compare(a, e.a());
            return c != 0 ? c : Integer.compare(b, e.b());
        }
    }
    record Triangle(int a, int b, int c) implements Comparable<Triangle> {
        public int compareTo(Triangle t) {
            int result = Integer.compare(a, t.a());
            if (result == 0)
                result = Integer.compare(b, t.b());
            return result != 0 ? result : Integer.compare(c, t.c());
        }
        int[] sites() {
            return new int[] {a, b, c};
        }
    }
    static Edge key(int a, int b) {
        return new Edge(Math.min(a, b), Math.max(a, b));
    }
    static Triangle canonical(int a, int b, int c) {
        return a < b && a < c ? new Triangle(a, b, c) : b < c ? new Triangle(b, c, a) : new Triangle(c, a, b);
    }
    record Insertion(String kind, Triangle containing, int visible, int flips, int triangles, int hull) {}
    static final class Model {
        List<Predicates.Point> points;
        Map<Edge, Integer> directed = new HashMap<>();
        Triangle initial;
        Model(List<Predicates.Point> points) {
            this.points = points;
            initial = Predicates.orient(points.get(1), points.get(2), points.get(3)) > 0
                          ? new Triangle(1, 2, 3)
                          : new Triangle(1, 3, 2);
            add(initial.a(), initial.b(), initial.c());
        }
        void add(int a, int b, int c) {
            directed.put(new Edge(a, b), c);
            directed.put(new Edge(b, c), a);
            directed.put(new Edge(c, a), b);
        }
        void remove(int a, int b, int c) {
            directed.remove(new Edge(a, b));
            directed.remove(new Edge(b, c));
            directed.remove(new Edge(c, a));
        }
        List<Triangle> triangles() {
            SortedSet<Triangle> result = new TreeSet<>();
            for (Map.Entry<Edge, Integer> entry : directed.entrySet())
                result.add(canonical(entry.getKey().a(), entry.getKey().b(), entry.getValue()));
            return new ArrayList<>(result);
        }
        List<Edge> hullEdges() {
            List<Edge> result = new ArrayList<>();
            for (Edge e : directed.keySet())
                if (!directed.containsKey(new Edge(e.b(), e.a())))
                    result.add(e);
            Collections.sort(result);
            return result;
        }
        Insertion insert(int site) {
            Triangle containing = null;
            for (Triangle t : triangles())
                if (Predicates.orient(points.get(t.a()), points.get(t.b()), points.get(site)) > 0 &&
                    Predicates.orient(points.get(t.b()), points.get(t.c()), points.get(site)) > 0 &&
                    Predicates.orient(points.get(t.c()), points.get(t.a()), points.get(site)) > 0) {
                    containing = t;
                    break;
                }
            SortedSet<Edge> check = new TreeSet<>();
            int visible = 0;
            if (containing != null) {
                int a = containing.a(), b = containing.b(), c = containing.c();
                remove(a, b, c);
                check.add(new Edge(a, b));
                check.add(new Edge(b, c));
                check.add(new Edge(c, a));
            } else {
                for (Edge e : hullEdges())
                    if (Predicates.orient(points.get(e.a()), points.get(e.b()), points.get(site)) < 0)
                        check.add(new Edge(e.b(), e.a()));
                visible = check.size();
            }
            for (Edge e : check)
                add(e.a(), e.b(), site);
            int flips = 0;
            while (!check.isEmpty()) {
                Edge edge = check.first();
                check.remove(edge);
                int a = edge.a(), b = edge.b();
                Integer q = directed.get(new Edge(b, a));
                if (q != null &&
                    Predicates.incircle(points.get(a), points.get(b), points.get(site), points.get(q)) > 0) {
                    remove(a, b, site);
                    remove(b, a, q);
                    add(a, q, site);
                    add(q, b, site);
                    check.add(new Edge(a, q));
                    check.add(new Edge(q, b));
                    flips++;
                }
            }
            return new Insertion(containing == null ? "outside" : "inside", containing, visible, flips,
                                 directed.size() / 3, hullEdges().size());
        }
    }
    record Walk(List<Integer> path, Edge outside) {}
    static Walk walk(Predicates.Point query, List<Predicates.Point> points, List<Triangle> triangles,
                     Map<Edge, Integer> directed) {
        List<Integer> path = new ArrayList<>();
        path.add(1);
        while (true) {
            Triangle t = triangles.get(path.getLast() - 1);
            boolean moved = false;
            for (Edge e : List.of(new Edge(t.a(), t.b()), new Edge(t.b(), t.c()), new Edge(t.c(), t.a())))
                if (Predicates.orient(points.get(e.a()), points.get(e.b()), query) < 0) {
                    Integer next = directed.get(new Edge(e.b(), e.a()));
                    if (next == null)
                        return new Walk(path, key(e.a(), e.b()));
                    path.add(next);
                    moved = true;
                    break;
                }
            if (!moved)
                return new Walk(path, null);
        }
    }
}
