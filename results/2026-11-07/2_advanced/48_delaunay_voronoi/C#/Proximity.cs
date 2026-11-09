using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Proximity {
    public sealed class Sets {
        public int[] parent, size;
        public int count;
        public Sets(int n) {
            count = n;
            parent = new int[n + 1];
            size = new int[n + 1];
            for (int i = 0; i <= n; i++) {
                parent[i] = i;
                size[i] = 1;
            }
        }
        public int Find(int i) {
            while (parent[i] != i) {
                parent[i] = parent[parent[i]];
                i = parent[i];
            }
            return i;
        }
        public bool Union(int a, int b) {
            a = Find(a);
            b = Find(b);
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
    public static int[] Nearest(List<Predicates.Point> points, List<List<int>> neighbors) {
        int[] result = new int[points.Count];
        for (int s = 1; s < points.Count; s++) {
            int best = 0;
            long distance = long.MaxValue;
            foreach (int t in neighbors[s]) {
                long candidate = Predicates.D2(points[s], points[t]);
                if (candidate < distance || candidate == distance && t < best) {
                    best = t;
                    distance = candidate;
                }
            }
            result[s] = best;
        }
        return result;
    }
    public static List<List<int>> Components(int[] nearest) {
        Sets sets = new Sets(nearest.Length - 1);
        for (int s = 1; s < nearest.Length; s++)
            sets.Union(s, nearest[s]);
        Dictionary<int, List<int>> groups = new();
        for (int s = 1; s < nearest.Length; s++) {
            int root = sets.Find(s);
            if (!groups.ContainsKey(root))
                groups[root] = new();
            groups[root].Add(s);
        }
        List<List<int>> result = new(groups.Values);
        result.Sort((a, b) => a[0].CompareTo(b[0]));
        return result;
    }
    public static List<Triangulation.Edge> Mst(List<Predicates.Point> points,
                                               List<Triangulation.Edge> edges) {
        List<Triangulation.Edge> ordered = new(edges);
        ordered.Sort((a, b) => {
            int comparison =
                Predicates.D2(points[a.a], points[a.b]).CompareTo(Predicates.D2(points[b.a], points[b.b]));
            return comparison != 0 ? comparison : a.CompareTo(b);
        });
        Sets sets = new Sets(points.Count - 1);
        List<Triangulation.Edge> result = new();
        foreach (Triangulation.Edge edge in ordered)
            if (sets.Union(edge.a, edge.b))
                result.Add(edge);
        return result;
    }
    public static bool Gabriel(List<Predicates.Point> points, Triangulation.Edge edge,
                               Dictionary<Triangulation.Edge, int> directed) {
        foreach (Triangulation.Edge e in[edge, new Triangulation.Edge(edge.b, edge.a)]) {
            int q = directed.GetValueOrDefault(e);
            if (q != 0 && Predicates.Dot(points[q], points[edge.a], points[edge.b]) <= 0)
                return false;
        }
        return true;
    }
    public static bool Rng(List<Predicates.Point> points, Triangulation.Edge edge) {
        long length = Predicates.D2(points[edge.a], points[edge.b]);
        for (int k = 1; k < points.Count; k++)
            if (Predicates.D2(points[edge.a], points[k]) < length &&
                Predicates.D2(points[edge.b], points[k]) < length)
                return false;
        return true;
    }
    public record Route(List<int> sites, double length) {
    }
    public static Route GreedyRoute(List<Predicates.Point> points, List<List<int>> neighbors, int start,
                                    int target) {
        List<int> path = new();
        path.Add(start);
        double length = 0;
        int current = start;
        while (current != target) {
            int best = 0;
            long distance = long.MaxValue;
            foreach (int t in neighbors[current]) {
                long candidate = Predicates.D2(points[t], points[target]);
                if (candidate < distance || candidate == distance && t < best) {
                    best = t;
                    distance = candidate;
                }
            }
            length += Math.Sqrt(Predicates.D2(points[current], points[best]));
            path.Add(best);
            current = best;
        }
        return new Route(path, length);
    }
    public record Paths(double[] distance, int[] previous) {
        public List<int> Path(int target) {
            List<int> result = new();
            for (int current = target; current != 0; current = previous[current])
                result.Add(current);
            result.Reverse();
            return result;
        }
    }
    public static Paths Dijkstra(List<Predicates.Point> points, List<List<int>> neighbors, int start) {
        int n = points.Count - 1;
        double[] distance = new double[n + 1];
        Array.Fill(distance, double.PositiveInfinity);
        int[] previous = new int[n + 1];
        bool[] done = new bool[n + 1];
        distance[start] = 0;
        for (int step = 0; step < n; step++) {
            int site = 0;
            for (int s = 1; s <= n; s++)
                if (!done[s] && (site == 0 || distance[s] < distance[site]))
                    site = s;
            done[site] = true;
            foreach (int t in neighbors[site]) {
                double candidate = distance[site] + Math.Sqrt(Predicates.D2(points[site], points[t]));
                if (candidate < distance[t]) {
                    distance[t] = candidate;
                    previous[t] = site;
                }
            }
        }
        return new Paths(distance, previous);
    }
}
