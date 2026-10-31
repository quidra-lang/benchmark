import java.util.*;

final class Proximity {
    static final class Sets {
        int[] parent, size;
        int count;
        Sets(int n) {
            count = n;
            parent = new int[n + 1];
            size = new int[n + 1];
            for (int i = 0; i <= n; i++) {
                parent[i] = i;
                size[i] = 1;
            }
        }
        int find(int i) {
            while (parent[i] != i) {
                parent[i] = parent[parent[i]];
                i = parent[i];
            }
            return i;
        }
        boolean union(int a, int b) {
            a = find(a);
            b = find(b);
            if (a == b)
                return false;
            if (size[a] < size[b]) {
                int swap = a;
                a = b;
                b = swap;
            }
            parent[b] = a;
            size[a] += size[b];
            count--;
            return true;
        }
    }
    static int[] nearest(List<Predicates.Point> points, List<List<Integer>> neighbors) {
        int[] result = new int[points.size()];
        for (int s = 1; s < points.size(); s++) {
            int best = 0;
            long distance = Long.MAX_VALUE;
            for (int t : neighbors.get(s)) {
                long candidate = Predicates.d2(points.get(s), points.get(t));
                if (candidate < distance || candidate == distance && t < best) {
                    best = t;
                    distance = candidate;
                }
            }
            result[s] = best;
        }
        return result;
    }
    static List<List<Integer>> components(int[] nearest) {
        Sets sets = new Sets(nearest.length - 1);
        for (int s = 1; s < nearest.length; s++)
            sets.union(s, nearest[s]);
        Map<Integer, List<Integer>> groups = new HashMap<>();
        for (int s = 1; s < nearest.length; s++)
            groups.computeIfAbsent(sets.find(s), key -> new ArrayList<>()).add(s);
        List<List<Integer>> result = new ArrayList<>(groups.values());
        result.sort(Comparator.comparingInt(row -> row.get(0)));
        return result;
    }
    static List<Triangulation.Edge> mst(List<Predicates.Point> points, List<Triangulation.Edge> edges) {
        List<Triangulation.Edge> ordered = new ArrayList<>(edges);
        ordered.sort((a, b) -> {
            int comparison = Long.compare(Predicates.d2(points.get(a.a()), points.get(a.b())),
                                          Predicates.d2(points.get(b.a()), points.get(b.b())));
            return comparison != 0 ? comparison : a.compareTo(b);
        });
        Sets sets = new Sets(points.size() - 1);
        List<Triangulation.Edge> result = new ArrayList<>();
        for (Triangulation.Edge edge : ordered)
            if (sets.union(edge.a(), edge.b()))
                result.add(edge);
        return result;
    }
    static boolean gabriel(List<Predicates.Point> points, Triangulation.Edge edge,
                           Map<Triangulation.Edge, Integer> directed) {
        for (Triangulation.Edge e : List.of(edge, new Triangulation.Edge(edge.b(), edge.a()))) {
            Integer q = directed.get(e);
            if (q != null && Predicates.dot(points.get(q), points.get(edge.a()), points.get(edge.b())) <= 0)
                return false;
        }
        return true;
    }
    static boolean rng(List<Predicates.Point> points, Triangulation.Edge edge) {
        long length = Predicates.d2(points.get(edge.a()), points.get(edge.b()));
        for (int k = 1; k < points.size(); k++)
            if (Predicates.d2(points.get(edge.a()), points.get(k)) < length &&
                Predicates.d2(points.get(edge.b()), points.get(k)) < length)
                return false;
        return true;
    }
    record Route(List<Integer> sites, double length) {}
    static Route route(List<Predicates.Point> points, List<List<Integer>> neighbors, int start, int target) {
        List<Integer> path = new ArrayList<>();
        path.add(start);
        double length = 0;
        int current = start;
        while (current != target) {
            int best = 0;
            long distance = Long.MAX_VALUE;
            for (int t : neighbors.get(current)) {
                long candidate = Predicates.d2(points.get(t), points.get(target));
                if (candidate < distance || candidate == distance && t < best) {
                    best = t;
                    distance = candidate;
                }
            }
            length += Math.sqrt(Predicates.d2(points.get(current), points.get(best)));
            path.add(best);
            current = best;
        }
        return new Route(path, length);
    }
    record Paths(double[] distance, int[] previous) {
        List<Integer> path(int target) {
            List<Integer> result = new ArrayList<>();
            for (int current = target; current != 0; current = previous[current])
                result.add(current);
            Collections.reverse(result);
            return result;
        }
    }
    static Paths dijkstra(List<Predicates.Point> points, List<List<Integer>> neighbors, int start) {
        int n = points.size() - 1;
        double[] distance = new double[n + 1];
        Arrays.fill(distance, Double.POSITIVE_INFINITY);
        int[] previous = new int[n + 1];
        boolean[] done = new boolean[n + 1];
        distance[start] = 0;
        for (int step = 0; step < n; step++) {
            int site = 0;
            for (int s = 1; s <= n; s++)
                if (!done[s] && (site == 0 || distance[s] < distance[site]))
                    site = s;
            done[site] = true;
            for (int t : neighbors.get(site)) {
                double candidate = distance[site] + Math.sqrt(Predicates.d2(points.get(site), points.get(t)));
                if (candidate < distance[t]) {
                    distance[t] = candidate;
                    previous[t] = site;
                }
            }
        }
        return new Paths(distance, previous);
    }
}
