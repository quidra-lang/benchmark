using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Voronoi {
    public record Vertex(Predicates.Center center, double r2, string position) {
    }
    public record RealPoint(double x, double y) {
    }
    public static double Radius2(Predicates.Point a, Predicates.Point b, Predicates.Point c) {
        long area = Predicates.Orient(a, b, c);
        return (((double)Predicates.D2(a, b) * Predicates.D2(b, c)) * Predicates.D2(c, a)) /
               ((4.0 * area) * area);
    }
    public static string Position(Predicates.Center v, List<int> hull, List<Predicates.Point> points) {
        bool on = false;
        for (int i = 0; i < hull.Count; i++) {
            Predicates.Point a = points[hull[i]], b = points[hull[(i + 1) % hull.Count]];
            long sigma = (b.x - a.x) * (v.y - a.y * v.d) - (b.y - a.y) * (v.x - a.x * v.d);
            if (sigma < 0)
                return "outside";
            if (sigma == 0)
                on = true;
        }
        return on ? "on" : "inside";
    }
    public static Predicates.Point Outward(Predicates.Point a, Predicates.Point b) {
        return Predicates.Reduce(b.y - a.y, a.x - b.x);
    }
    public static List<int> Neighbors(int site, List<int> adjacent,
                                      Dictionary<Triangulation.Edge, int> directed, int next) {
        int start = next == 0 ? adjacent.Min() : next;
        List<int> result = new();
        int current = start;
        while (true) {
            result.Add(current);
            int following = directed.GetValueOrDefault(new Triangulation.Edge(site, current));
            if (following == 0 || following == start)
                break;
            current = following;
        }
        return result;
    }
    public static double Area(int site, List<int> vertexIds, List<Vertex> vertices,
                              List<Predicates.Point> points) {
        Predicates.Point origin = points[site];
        double sum = 0;
        for (int i = 0; i < vertexIds.Count; i++) {
            Predicates.Center a = vertices[vertexIds[i] - 1].center,
                              b = vertices[vertexIds[(i + 1) % vertexIds.Count] - 1].center;
            double u = (double)a.x / a.d - origin.x, w = (double)a.y / a.d - origin.y,
                   un = (double)b.x / b.d - origin.x, wn = (double)b.y / b.d - origin.y;
            sum += u * wn - un * w;
        }
        return sum / 2;
    }
    public static double Clipped(int site, List<int> neighbors, List<Predicates.Point> points) {
        List<RealPoint> polygon = new(
            [new RealPoint(0, 0), new RealPoint(1000, 0), new RealPoint(1000, 1000), new RealPoint(0, 1000)]);
        Predicates.Point s = points[site];
        foreach (int neighbor in neighbors) {
            Predicates.Point t = points[neighbor];
            long c1 = 2 * (t.x - s.x), c2 = 2 * (t.y - s.y),
                 c3 = t.x * t.x + t.y * t.y - s.x * s.x - s.y * s.y;
            List<RealPoint> next = new();
            for (int i = 0; i < polygon.Count; i++) {
                RealPoint a = polygon[i], b = polygon[(i + 1) % polygon.Count];
                double fa = c1 * a.x + c2 * a.y - c3, fb = c1 * b.x + c2 * b.y - c3;
                if (fa <= 0)
                    next.Add(a);
                if (fa < 0 && fb > 0 || fb < 0 && fa > 0) {
                    double lambda = fa / (fa - fb);
                    next.Add(new RealPoint(a.x + (b.x - a.x) * lambda, a.y + (b.y - a.y) * lambda));
                }
            }
            polygon = next;
        }
        double sum = 0;
        for (int i = 0; i < polygon.Count; i++) {
            RealPoint a = polygon[i], b = polygon[(i + 1) % polygon.Count];
            sum += a.x * b.y - b.x * a.y;
        }
        return sum / 2;
    }
}
