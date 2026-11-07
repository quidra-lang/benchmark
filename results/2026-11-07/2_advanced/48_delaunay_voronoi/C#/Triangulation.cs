using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Triangulation {
    public record Edge(int a, int b) : IComparable<Edge> {
        public int CompareTo(Edge e) {
            int c = a.CompareTo(e.a);
            return c != 0 ? c : b.CompareTo(e.b);
        }
    }
    public record Triangle(int a, int b, int c) : IComparable<Triangle> {
        public int CompareTo(Triangle t) {
            int result = a.CompareTo(t.a);
            if (result == 0)
                result = b.CompareTo(t.b);
            return result != 0 ? result : c.CompareTo(t.c);
        }
        public int[] Sites() {
            return new int[] { a, b, c };
        }
    }
    public static Edge Key(int a, int b) {
        return new Edge(Math.Min(a, b), Math.Max(a, b));
    }
    public static Triangle Canonical(int a, int b, int c) {
        return a < b && a < c ? new Triangle(a, b, c) : b < c ? new Triangle(b, c, a) : new Triangle(c, a, b);
    }
    public record Insertion(string kind, Triangle containing, int visible, int flips, int triangles,
                            int hull) {
    }
    public sealed class Model {
        public List<Predicates.Point> points;
        public Dictionary<Edge, int> directed = new();
        public Triangle initial;
        public Model(List<Predicates.Point> points) {
            this.points = points;
            initial = Predicates.Orient(points[1], points[2], points[3]) > 0 ? new Triangle(1, 2, 3)
                                                                             : new Triangle(1, 3, 2);
            Add(initial.a, initial.b, initial.c);
        }
        public void Add(int a, int b, int c) {
            directed[new Edge(a, b)] = c;
            directed[new Edge(b, c)] = a;
            directed[new Edge(c, a)] = b;
        }
        public void Remove(int a, int b, int c) {
            directed.Remove(new Edge(a, b));
            directed.Remove(new Edge(b, c));
            directed.Remove(new Edge(c, a));
        }
        public List<Triangle> Triangles() {
            SortedSet<Triangle> result = new();
            foreach (KeyValuePair<Edge, int> entry in directed)
                result.Add(Canonical(entry.Key.a, entry.Key.b, entry.Value));
            return new(result);
        }
        public List<Edge> HullEdges() {
            List<Edge> result = new();
            foreach (Edge e in directed.Keys)
                if (!directed.ContainsKey(new Edge(e.b, e.a)))
                    result.Add(e);
            result.Sort();
            return result;
        }
        public Insertion Insert(int site) {
            Triangle containing = null;
            foreach (Triangle t in Triangles())
                if (Predicates.Orient(points[t.a], points[t.b], points[site]) > 0 &&
                    Predicates.Orient(points[t.b], points[t.c], points[site]) > 0 &&
                    Predicates.Orient(points[t.c], points[t.a], points[site]) > 0) {
                    containing = t;
                    break;
                }
            SortedSet<Edge> check = new();
            int visible = 0;
            if (containing != null) {
                int a = containing.a, b = containing.b, c = containing.c;
                Remove(a, b, c);
                check.Add(new Edge(a, b));
                check.Add(new Edge(b, c));
                check.Add(new Edge(c, a));
            } else {
                foreach (Edge e in HullEdges())
                    if (Predicates.Orient(points[e.a], points[e.b], points[site]) < 0)
                        check.Add(new Edge(e.b, e.a));
                visible = check.Count;
            }
            foreach (Edge e in check)
                Add(e.a, e.b, site);
            int flips = 0;
            while (check.Count != 0) {
                Edge edge = check.Min;
                check.Remove(edge);
                int a = edge.a, b = edge.b;
                int q = directed.GetValueOrDefault(new Edge(b, a));
                if (q != 0 && Predicates.Incircle(points[a], points[b], points[site], points[q]) > 0) {
                    Remove(a, b, site);
                    Remove(b, a, q);
                    Add(a, q, site);
                    Add(q, b, site);
                    check.Add(new Edge(a, q));
                    check.Add(new Edge(q, b));
                    flips++;
                }
            }
            return new Insertion(containing == null ? "outside" : "inside", containing, visible, flips,
                                 directed.Count / 3, HullEdges().Count);
        }
    }
    public record Walk(List<int> path, Edge outside) {
    }
    public static Walk VisibilityWalk(Predicates.Point query, List<Predicates.Point> points,
                                      List<Triangle> triangles, Dictionary<Edge, int> directed) {
        List<int> path = new();
        path.Add(1);
        while (true) {
            Triangle t = triangles[path[^1] - 1];
            bool moved = false;
            foreach (Edge e in new Edge[] { new Edge(t.a, t.b), new Edge(t.b, t.c), new Edge(t.c, t.a) })
                if (Predicates.Orient(points[e.a], points[e.b], query) < 0) {
                    int next = directed.GetValueOrDefault(new Edge(e.b, e.a));
                    if (next == 0)
                        return new Walk(path, Key(e.a, e.b));
                    path.Add(next);
                    moved = true;
                    break;
                }
            if (!moved)
                return new Walk(path, null);
        }
    }
}
