using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static List<Predicates.Point> points = new();
    public static List<string> rejects = new(), queries = new();
    public static List<string> requested = new(["summary"]), layers = new(["edges", "hull", "sites"]);
    public static List<int> alphas = new();
    public static int width = 61, height = 31, n, lineCount;
    public static Triangulation.Model model;
    public static List<Triangulation.Triangle> triangles;
    public static List<Triangulation.Edge> edges, mst;
    public static Dictionary<Triangulation.Edge, int> directed = new();
    public static Dictionary<int, int> next = new(), previous = new();
    public static List<int> hull = new();
    public static List<List<int>> neighbors = new(), cells = new(), components, convexLayers = new();
    public static List<Triangulation.Insertion> insertions = new();
    public static List<Voronoi.Vertex> vertices = new();
    public static List<string> kinds = new();
    public static double[] minAngles, maxAngles, cellAreas, clipped;
    public static long[] areas;
    public static int[] nearest, component, depth;
    public static HashSet<Triangulation.Edge> gabriel = new(), rng = new(), mstSet;
    public static Proximity.Paths[] paths;
    public static int empty;
    public static Predicates.Center enclosingCenter;
    public static double enclosingRadius2;
    public static List<int> enclosingSites;
    public static Dictionary<string, List<string>> sections = new();
    public static string Real(double value) {
        return value.ToString("F3", CultureInfo.InvariantCulture);
    }
    public static string Numbers(List<int> values) {
        List<string> words = new();
        foreach (int value in values)
            words.Add(Convert.ToString(value));
        return string.Join(" ", words);
    }
    public static string Sites(Triangulation.Triangle t) {
        return t.a + " " + t.b + " " + t.c;
    }
    public static string Direction(Predicates.Point p) {
        return p.x + " " + p.y;
    }
    public static string Center(Predicates.Center c) {
        return Predicates.Fraction(c.x, c.d) + " " + Predicates.Fraction(c.y, c.d);
    }
    public static string Number(int value) {
        return value == 0 ? "-" : Convert.ToString(value);
    }
    public static long Length2(Triangulation.Edge e) {
        return Predicates.D2(points[e.a], points[e.b]);
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static void Read() {
        points.Add(new Predicates.Point(0, 0));
        List<string> source = Lines("points.txt");
        lineCount = source.Count;
        for (int i = 0; i < source.Count; i++) {
            string line = source[i];
            if (line.Count == 0 || line.StartsWith("#"))
                continue;
            string[] words = line.Split(' ');
            string prefix = "reject " + (i + 1) + " ";
            if (words.Length != 2 ||
                !System.Text.RegularExpressions.Regex.IsMatch(words[0], "\\A-?[0-9]+\\z") ||
                !System.Text.RegularExpressions.Regex.IsMatch(words[1], "\\A-?[0-9]+\\z")) {
                rejects.Add(prefix + "format");
                continue;
            }
            long x = long.Parse(words[0]), y = long.Parse(words[1]);
            if (x < 0 || x > 1000 || y < 0 || y > 1000) {
                rejects.Add(prefix + "range");
                continue;
            }
            Predicates.Point point = new Predicates.Point(x, y);
            int duplicate = 0;
            for (int s = 1; s < points.Count; s++)
                if (points[s].Equals(point)) {
                    duplicate = s;
                    break;
                }
            if (duplicate > 0)
                rejects.Add(prefix + "duplicate " + duplicate);
            else
                points.Add(point);
        }
        n = points.Count - 1;
        foreach (string line in Lines("params.txt")) {
            if (line.Count == 0 || line.StartsWith("#"))
                continue;
            string[] words = line.Split(' ');
            switch (words[0]) {
            case "plot": {
                width = int.Parse(words[1]);
                height = int.Parse(words[2]);
                break;
            }
            case "plot_layers":
                layers = new(words.ToList().GetRange(1, words.Length - (1)));
                break;
            case "sections":
                requested = new(words.ToList().GetRange(1, words.Length - (1)));
                break;
            case "alpha": {
                for (int i = 1; i < words.Length; i++)
                    alphas.Add(int.Parse(words[i]));
                break;
            }
            case "query":
                queries.Add(line.Substring(6));
                break;
            }
        }
    }
    public static void Organize() {
        model = new Triangulation.Model(points);
        for (int s = 4; s <= n; s++)
            insertions.Add(model.Insert(s));
        triangles = model.Triangles();
        SortedSet<Triangulation.Edge> all = new();
        for (int k = 0; k < triangles.Count; k++) {
            Triangulation.Triangle t = triangles[k];
            int[] a = t.Sites();
            for (int j = 0; j < 3; j++) {
                int u = a[j], v = a[(j + 1) % 3];
                directed[new Triangulation.Edge(u, v)] = k + 1;
                all.Add(Triangulation.Key(u, v));
            }
        }
        edges = new(all);
        foreach (Triangulation.Edge e in model.HullEdges()) {
            next[e.a] = e.b;
            previous[e.b] = e.a;
        }
        int start = next.Keys.Min(), current = start;
        do {
            hull.Add(current);
            current = next[current];
        } while (current != start);
        List<List<int>> adjacent = new();
        for (int s = 0; s <= n; s++)
            adjacent.Add(new());
        foreach (Triangulation.Edge e in edges) {
            adjacent[e.a].Add(e.b);
            adjacent[e.b].Add(e.a);
        }
        neighbors.Add(new());
        for (int s = 1; s <= n; s++)
            neighbors.Add(Voronoi.Neighbors(s, adjacent[s], model.directed, next.GetValueOrDefault(s)));
        int count = triangles.Count;
        minAngles = new double[count];
        maxAngles = new double[count];
        areas = new long[count];
        for (int k = 0; k < count; k++) {
            Triangulation.Triangle t = triangles[k];
            int[] a = t.Sites();
            long area = Predicates.Orient(points[t.a], points[t.b], points[t.c]);
            areas[k] = area;
            bool right = false, obtuse = false;
            double minimum = 180, maximum = 0;
            for (int j = 0; j < 3; j++) {
                long dot = Predicates.Dot(points[a[j]], points[a[(j + 1) % 3]], points[a[(j + 2) % 3]]);
                if (dot == 0)
                    right = true;
                if (dot < 0)
                    obtuse = true;
                double angle = Math.Atan2((double)area, (double)dot) * 180 / Math.PI;
                minimum = Math.Min(minimum, angle);
                maximum = Math.Max(maximum, angle);
            }
            minAngles[k] = minimum;
            maxAngles[k] = maximum;
            kinds.Add(right ? "right" : obtuse ? "obtuse" : "acute");
            Predicates.Center center = Predicates.Circumcenter(points[t.a], points[t.b], points[t.c]);
            vertices.Add(new Voronoi.Vertex(center, Voronoi.Radius2(points[t.a], points[t.b], points[t.c]),
                                            Voronoi.Position(center, hull, points)));
        }
        cells.Add(new());
        cellAreas = new double[n + 1];
        clipped = new double[n + 1];
        for (int s = 1; s <= n; s++) {
            List<int> ids = new();
            foreach (int neighbor in neighbors[s]) {
                int id = directed.GetValueOrDefault(new Triangulation.Edge(s, neighbor));
                if (id != 0)
                    ids.Add(id);
            }
            cells.Add(ids);
            if (!next.ContainsKey(s))
                cellAreas[s] = Voronoi.Area(s, ids, vertices, points);
            clipped[s] = Voronoi.Clipped(s, neighbors[s], points);
        }
        nearest = Proximity.Nearest(points, neighbors);
        components = Proximity.Components(nearest);
        component = new int[n + 1];
        for (int c = 0; c < components.Count; c++)
            foreach (int s in components[c])
                component[s] = c + 1;
        mst = Proximity.Mst(points, edges);
        mstSet = new(mst);
        foreach (Triangulation.Edge e in edges) {
            if (Proximity.Gabriel(points, e, model.directed))
                gabriel.Add(e);
            if (Proximity.Rng(points, e))
                rng.Add(e);
        }
        for (int k = 0; k < vertices.Count; k++)
            if (vertices[k].position.Equals("inside") &&
                (empty == 0 || vertices[k].r2 > vertices[empty - 1].r2))
                empty = k + 1;
        paths = new Proximity.Paths[n + 1];
        for (int s = 1; s <= n; s++)
            paths[s] = Proximity.Dijkstra(points, neighbors, s);
        Layers();
        Enclosing();
    }
    public static List<int> Convex(List<int> sites) {
        if (sites.Count <= 2) {
            List<int> result = new(sites);
            result.Sort();
            return result;
        }
        List<int> sorted = new(sites);
        sorted.Sort((a, b) => {
            int c = points[a].x.CompareTo(points[b].x);
            return c != 0 ? c : points[a].y.CompareTo(points[b].y);
        });
        List<int> lower = new(), upper = new();
        foreach (int s in sorted) {
            while (lower.Count >= 2 &&
                   Predicates.Orient(points[lower[lower.Count - 2]], points[lower[^1]], points[s]) <= 0)
                lower.RemoveAt(lower.Count - 1);
            lower.Add(s);
        }
        for (int i = sorted.Count - 1; i >= 0; i--) {
            int s = sorted[i];
            while (upper.Count >= 2 &&
                   Predicates.Orient(points[upper[upper.Count - 2]], points[upper[^1]], points[s]) <= 0)
                upper.RemoveAt(upper.Count - 1);
            upper.Add(s);
        }
        lower.RemoveAt(lower.Count - 1);
        upper.RemoveAt(upper.Count - 1);
        lower.AddRange(upper);
        int smallest = lower.IndexOf(lower.Min());
        List<int> hullResult = new();
        for (int i = 0; i < lower.Count; i++)
            hullResult.Add(lower[(smallest + i) % lower.Count]);
        return hullResult;
    }
    public static void Layers() {
        depth = new int[n + 1];
        List<int> remaining = new();
        for (int s = 1; s <= n; s++)
            remaining.Add(s);
        while (remaining.Count != 0) {
            List<int> layer = Convex(remaining);
            convexLayers.Add(layer);
            foreach (int s in layer)
                depth[s] = convexLayers.Count;
            remaining.RemoveAll(s => layer.Contains(s));
        }
    }
    public static long CircleTest(List<int> support, int site) {
        Predicates.Point p = points[site];
        if (support.Count == 1)
            return -Predicates.D2(p, points[support[0]]);
        if (support.Count == 2)
            return -Predicates.Dot(p, points[support[0]], points[support[1]]);
        Predicates.Point a = points[support[0]], b = points[support[1]], c = points[support[2]];
        return Predicates.Orient(a, b, c) > 0 ? Predicates.Incircle(a, b, c, p)
                                              : Predicates.Incircle(a, c, b, p);
    }
    public static void Enclosing() {
        List<int> support = new();
        for (int i = 0; i < hull.Count; i++) {
            int a = hull[i];
            if (support.Count == 0 || CircleTest(support, a) < 0) {
                support = new([a]);
                for (int j = 0; j < i; j++) {
                    int b = hull[j];
                    if (CircleTest(support, b) < 0) {
                        support = new([a, b]);
                        for (int k = 0; k < j; k++) {
                            int c = hull[k];
                            if (CircleTest(support, c) < 0)
                                support = new([a, b, c]);
                        }
                    }
                }
            }
        }
        enclosingSites = new();
        for (int s = 1; s <= n; s++)
            if (CircleTest(support, s) == 0)
                enclosingSites.Add(s);
        for (int i = 0; i < enclosingSites.Count; i++)
            for (int j = i + 1; j < enclosingSites.Count; j++) {
                int a = enclosingSites[i], b = enclosingSites[j];
                bool diameter = true;
                foreach (int s in enclosingSites)
                    if (Predicates.Dot(points[s], points[a], points[b]) != 0)
                        diameter = false;
                if (diameter) {
                    enclosingCenter =
                        new Predicates.Center(points[a].x + points[b].x, points[a].y + points[b].y, 2);
                    enclosingRadius2 = Predicates.D2(points[a], points[b]) / 4.0;
                    return;
                }
            }
        int circleA = enclosingSites[0], circleB = enclosingSites[1], circleC = enclosingSites[2];
        if (Predicates.Orient(points[circleA], points[circleB], points[circleC]) < 0) {
            int swap = circleB;
            circleB = circleC;
            circleC = swap;
        }
        enclosingCenter = Predicates.Circumcenter(points[circleA], points[circleB], points[circleC]);
        enclosingRadius2 = Voronoi.Radius2(points[circleA], points[circleB], points[circleC]);
    }
    public static string Dual(Triangulation.Edge e) {
        int left = directed.GetValueOrDefault(e, 0),
            right = directed.GetValueOrDefault(new Triangulation.Edge(e.b, e.a), 0);
        if (left > 0 && right > 0)
            return "segment " + left + " " + right;
        Predicates.Point direction =
            left > 0 ? Voronoi.Outward(points[e.a], points[e.b]) : Voronoi.Outward(points[e.b], points[e.a]);
        return "ray " + (left > 0 ? left : right) + " " + Direction(direction);
    }
    public static void TriangulationSections() {
        List<string> output = new(["lines " + lineCount, "accepted " + n, "rejected " + rejects.Count]);
        output.AddRange(rejects);
        sections["input"] = output;
        int flips = 0, outside = 0, maxFlips = -1, maxSite = 0, acute = 0, right = 0, obtuse = 0;
        for (int i = 0; i < insertions.Count; i++) {
            Triangulation.Insertion insertion = insertions[i];
            flips += insertion.flips;
            if (insertion.kind.Equals("outside"))
                outside++;
            if (insertion.flips > maxFlips) {
                maxFlips = insertion.flips;
                maxSite = i + 4;
            }
        }
        foreach (string kind in kinds)
            if (kind.Equals("acute"))
                acute++;
            else if (kind.Equals("right"))
                right++;
            else
                obtuse++;
        sections["summary"] = new([
            "sites " + n, "triangles " + triangles.Count, "edges " + edges.Count,
            "hull_vertices " + hull.Count, "interior_sites " + (n - hull.Count),
            "euler " + (n - edges.Count + triangles.Count), "flips " + flips, "outside_insertions " + outside,
            "max_flips " + (maxSite == 0 ? "none" : maxSite + " " + maxFlips), "acute " + acute,
            "right " + right, "obtuse " + obtuse
        ]);
        output = new(["init " + Sites(model.initial)]);
        for (int i = 0; i < insertions.Count; i++) {
            Triangulation.Insertion insertion = insertions[i];
            output.Add("insert " + (i + 4) + " " + insertion.kind + " " +
                       (insertion.containing == null ? Convert.ToString(insertion.visible)
                                                     : Sites(insertion.containing)) +
                       " flips " + insertion.flips + " triangles " + insertion.triangles + " hull " +
                       insertion.hull);
        }
        sections["insertions"] = output;
        output = new();
        for (int k = 0; k < triangles.Count; k++) {
            Triangulation.Triangle t = triangles[k];
            output.Add("tri " + (k + 1) + " " + Sites(t) + " area2 " + areas[k] + " " + kinds[k] + " adj " +
                       Number(directed.GetValueOrDefault(new Triangulation.Edge(t.c, t.b), 0)) + " " +
                       Number(directed.GetValueOrDefault(new Triangulation.Edge(t.a, t.c), 0)) + " " +
                       Number(directed.GetValueOrDefault(new Triangulation.Edge(t.b, t.a), 0)));
        }
        sections["triangles"] = output;
        output = new();
        foreach (Triangulation.Edge e in edges) {
            int left = directed.GetValueOrDefault(e, 0),
                rightId = directed.GetValueOrDefault(new Triangulation.Edge(e.b, e.a), 0);
            output.Add("edge " + e.a + " " + e.b + " " + (left > 0 && rightId > 0 ? "inner" : "hull") +
                       " len2 " + Length2(e) + " left " + Number(left) + " right " + Number(rightId));
        }
        sections["edges"] = output;
        double perimeter = 0;
        long area = 0;
        for (int i = 0; i < hull.Count; i++) {
            Predicates.Point a = points[hull[i]], b = points[hull[(i + 1) % hull.Count]];
            perimeter += Math.Sqrt(Predicates.D2(a, b));
            area += a.x * b.y - b.x * a.y;
        }
        sections["hull"] = new([
            "hull_vertices " + hull.Count, "order " + Numbers(hull), "perimeter " + Real(perimeter),
            "area2 " + area
        ]);
        output = new(["layers " + convexLayers.Count]);
        for (int i = 0; i < convexLayers.Count; i++)
            output.Add("layer " + (i + 1) + " size " + convexLayers[i].Count + " sites " +
                       Numbers(convexLayers[i]));
        sections["convex_layers"] = output;
        int min = 0, max = 0;
        double total = 0;
        int[] histogram = new int[6];
        for (int k = 0; k < triangles.Count; k++) {
            if (minAngles[k] < minAngles[min])
                min = k;
            if (maxAngles[k] > maxAngles[max])
                max = k;
            total += minAngles[k];
            histogram[(int)(minAngles[k] / 10)]++;
        }
        output = new([
            "min_angle " + Real(minAngles[min]) + " tri " + (min + 1),
            "max_angle " + Real(maxAngles[max]) + " tri " + (max + 1),
            "mean_min_angle " + Real(total / triangles.Count)
        ]);
        for (int bin = 0; bin < 6; bin++)
            output.Add("bin " + (10 * bin) + " " + (10 * (bin + 1)) + " " + histogram[bin]);
        sections["quality"] = output;
    }
    public static void VoronoiSections() {
        int inside = 0, on = 0, outside = 0;
        foreach (Voronoi.Vertex vertex in vertices)
            if (vertex.position.Equals("inside"))
                inside++;
            else if (vertex.position.Equals("on"))
                on++;
            else
                outside++;
        List<string> output = new(["inside " + inside, "on " + on, "outside " + outside]);
        for (int k = 0; k < vertices.Count; k++) {
            Voronoi.Vertex v = vertices[k];
            output.Add("v " + (k + 1) + " " + Center(v.center) + " r " + Real(Math.Sqrt(v.r2)) + " " +
                       v.position);
        }
        sections["vertices"] = output;
        output = new(["segments " + (edges.Count - hull.Count), "rays " + hull.Count]);
        foreach (Triangulation.Edge e in edges)
            output.Add("ve " + e.a + " " + e.b + " " + Dual(e));
        sections["voronoi_edges"] = output;
        double total = 0, clipTotal = 0;
        int largest = 0;
        for (int s = 1; s <= n; s++) {
            clipTotal += clipped[s];
            if (!next.ContainsKey(s)) {
                total += cellAreas[s];
                if (largest == 0 || cellAreas[s] > cellAreas[largest])
                    largest = s;
            }
        }
        output = new([
            "bounded " + (n - hull.Count), "unbounded " + hull.Count, "total_area " + Real(total),
            "clip_total " + Real(clipTotal),
            largest == 0 ? "largest none" : "largest " + largest + " area " + Real(cellAreas[largest])
        ]);
        for (int s = 1; s <= n; s++) {
            string line = "cell " + s + " ";
            if (!next.ContainsKey(s))
                line += "bounded " + cells[s].Count + " area " + Real(cellAreas[s]) + " clip " +
                        Real(clipped[s]) + " vertices " + Numbers(cells[s]);
            else {
                Predicates.Point incoming = Voronoi.Outward(points[s], points[next[s]]),
                                 outgoing = Voronoi.Outward(points[previous[s]], points[s]);
                line += "unbounded " + cells[s].Count + " clip " + Real(clipped[s]) + " from " +
                        Direction(incoming) + " vertices " + Numbers(cells[s]) + " to " + Direction(outgoing);
            }
            output.Add(line);
        }
        sections["cells"] = output;
    }
    public static void DerivedSections() {
        int mutual = 0;
        for (int s = 1; s <= n; s++)
            if (nearest[nearest[s]] == s && s < nearest[s])
                mutual++;
        Triangulation.Edge closest = edges[0];
        foreach (Triangulation.Edge e in edges)
            if (Length2(e) < Length2(closest))
                closest = e;
        List<string> output = new([
            "mutual_pairs " + mutual,
            "closest_pair " + closest.a + " " + closest.b + " d2 " + Length2(closest)
        ]);
        for (int s = 1; s <= n; s++)
            output.Add("nn " + s + " " + nearest[s] + " d2 " + Predicates.D2(points[s], points[nearest[s]]) +
                       " " + (nearest[nearest[s]] == s ? "mutual" : "-"));
        sections["nearest"] = output;
        output = new(["components " + components.Count]);
        for (int c = 0; c < components.Count; c++) {
            List<int> sites = components[c];
            int pair = 0;
            foreach (int s in sites)
                if (s < nearest[s] && nearest[nearest[s]] == s) {
                    pair = s;
                    break;
                }
            output.Add("component " + (c + 1) + " size " + sites.Count + " pair " + pair + " " +
                       nearest[pair] + " sites " + Numbers(sites));
        }
        sections["components"] = output;
        double length = 0;
        foreach (Triangulation.Edge e in mst)
            length += Math.Sqrt(Length2(e));
        Triangulation.Edge longest = mst[^1];
        output = new([
            "edges " + (n - 1), "total_length " + Real(length),
            "longest " + longest.a + " " + longest.b + " len2 " + Length2(longest)
        ]);
        foreach (Triangulation.Edge e in mst)
            output.Add("mst " + e.a + " " + e.b + " len2 " + Length2(e));
        sections["mst"] = output;
        output = new([
            "delaunay " + edges.Count, "gabriel " + gabriel.Count, "rng " + rng.Count, "mst " + (n - 1),
            "nn " + (n - mutual)
        ]);
        foreach (Triangulation.Edge e in edges)
            if (rng.Contains(e) && !mstSet.Contains(e))
                output.Add("rng_extra " + e.a + " " + e.b + " len2 " + Length2(e));
        sections["proximity"] = output;
        SortedDictionary<int, int> degreeCounts = new();
        for (int s = 1; s <= n; s++) {
            int degree = neighbors[s].Count;
            degreeCounts[degree] = degreeCounts.GetValueOrDefault(degree, 0) + 1;
        }
        output = new(["min " + degreeCounts.Keys.Min(), "max " + degreeCounts.Keys.Max()]);
        foreach (int degree in degreeCounts.Keys)
            output.Add("degree " + degree + " count " + degreeCounts[degree]);
        sections["degrees"] = output;
        int candidates = 0;
        foreach (Voronoi.Vertex v in vertices)
            if (v.position.Equals("inside"))
                candidates++;
        output = new(["candidates " + candidates]);
        if (empty == 0)
            output.Add("none");
        else {
            Voronoi.Vertex v = vertices[empty - 1];
            output.Add("vertex " + empty);
            output.Add("center " + Center(v.center));
            output.Add("radius " + Real(Math.Sqrt(v.r2)));
            output.Add("sites " + Sites(triangles[empty - 1]));
        }
        sections["empty_circle"] = output;
        int diameterA = 1, diameterB = 2;
        long diameter = Predicates.D2(points[1], points[2]);
        for (int i = 1; i <= n; i++)
            for (int j = i + 1; j <= n; j++) {
                long distance = Predicates.D2(points[i], points[j]);
                if (distance > diameter) {
                    diameter = distance;
                    diameterA = i;
                    diameterB = j;
                }
            }
        double width = double.PositiveInfinity;
        int edgeAt = 0;
        for (int t = 0; t < hull.Count; t++) {
            Predicates.Point a = points[hull[t]], b = points[hull[(t + 1) % hull.Count]];
            long farthest = 0;
            foreach (int s in hull)
                farthest = Math.Max(farthest, Predicates.Orient(a, b, points[s]));
            double candidate = farthest / Math.Sqrt(Predicates.D2(a, b));
            if (candidate < width) {
                width = candidate;
                edgeAt = t;
            }
        }
        sections["extent"] = new([
            "diameter " + diameterA + " " + diameterB + " d2 " + diameter,
            "width " + Real(width) + " edge " + hull[edgeAt] + " " + hull[(edgeAt + 1) % hull.Count],
            "enclosing_center " + Center(enclosingCenter),
            "enclosing_radius " + Real(Math.Sqrt(enclosingRadius2)),
            "enclosing_sites " + Numbers(enclosingSites)
        ]);
        double totalStretch = 0, maxStretch = 0, maxLength = 0, maxDistance = 0;
        int pairA = 0, pairB = 0;
        for (int i = 1; i <= n; i++)
            for (int j = i + 1; j <= n; j++) {
                double distance = Math.Sqrt(Predicates.D2(points[i], points[j])), path = paths[i].distance[j],
                       stretch = path / distance;
                totalStretch += stretch;
                if (stretch > maxStretch) {
                    maxStretch = stretch;
                    pairA = i;
                    pairB = j;
                    maxLength = path;
                    maxDistance = distance;
                }
            }
        int pairs = n * (n - 1) / 2;
        sections["spanner"] = new([
            "pairs " + pairs,
            "max_stretch " + Real(maxStretch) + " pair " + pairA + " " + pairB + " length " +
                Real(maxLength) + " distance " + Real(maxDistance),
            "mean_stretch " + Real(totalStretch / pairs)
        ]);
        output = new();
        foreach (int alpha in alphas) {
            HashSet<Triangulation.Edge> selected = new();
            Dictionary<Triangulation.Edge, int> selectedCounts = new();
            int faces = 0;
            long area2 = 0;
            for (int k = 0; k < triangles.Count; k++)
                if (vertices[k].r2 <= alpha) {
                    faces++;
                    area2 += areas[k];
                    int[] sites = triangles[k].Sites();
                    for (int j = 0; j < 3; j++) {
                        Triangulation.Edge e = Triangulation.Key(sites[j], sites[(j + 1) % 3]);
                        selected.Add(e);
                        selectedCounts[e] = selectedCounts.GetValueOrDefault(e, 0) + 1;
                    }
                }
            foreach (Triangulation.Edge e in edges)
                if (gabriel.Contains(e) && Length2(e) <= 4L * alpha)
                    selected.Add(e);
            Proximity.Sets sets = new Proximity.Sets(n);
            int boundary = 0, dangling = 0;
            HashSet<int> used = new();
            foreach (Triangulation.Edge e in edges)
                if (selected.Contains(e)) {
                    sets.Union(e.a, e.b);
                    used.Add(e.a);
                    used.Add(e.b);
                    int count = selectedCounts.GetValueOrDefault(e, 0);
                    if (count == 1)
                        boundary++;
                    if (count == 0)
                        dangling++;
                }
            output.Add("alpha " + alpha + " triangles " + faces + " edges " + selected.Count + " boundary " +
                       boundary + " dangling " + dangling + " isolated " + (n - used.Count) + " components " +
                       sets.count + " holes " + (sets.count - (n - selected.Count + faces)) + " area2 " +
                       area2);
        }
        sections["alpha"] = output;
        output = new();
        int[] gg = new int[n + 1], rg = new int[n + 1], mt = new int[n + 1];
        foreach (Triangulation.Edge e in edges) {
            if (gabriel.Contains(e)) {
                gg[e.a]++;
                gg[e.b]++;
            }
            if (rng.Contains(e)) {
                rg[e.a]++;
                rg[e.b]++;
            }
            if (mstSet.Contains(e)) {
                mt[e.a]++;
                mt[e.b]++;
            }
        }
        for (int s = 1; s <= n; s++)
            output.Add("site " + s + " " + Direction(points[s]) + " " +
                       (next.ContainsKey(s) ? "hull" : "inner") + " dt " + neighbors[s].Count + " gg " +
                       gg[s] + " rng " + rg[s] + " mst " + mt[s] + " nn " + nearest[s] + " comp " +
                       component[s] + " depth " + depth[s]);
        sections["sites"] = output;
    }
    public static string Locate(Predicates.Point query) {
        for (int s = 1; s <= n; s++)
            if (points[s].Equals(query))
                return "vertex " + s;
        foreach (Triangulation.Edge e in edges)
            if (Predicates.Orient(points[e.a], points[e.b], query) == 0 &&
                Predicates.Dot(query, points[e.a], points[e.b]) < 0)
                return "edge " + e.a + " " + e.b;
        foreach (Triangulation.Triangle t in triangles)
            if (Predicates.Orient(points[t.a], points[t.b], query) > 0 &&
                Predicates.Orient(points[t.b], points[t.c], query) > 0 &&
                Predicates.Orient(points[t.c], points[t.a], query) > 0)
                return "triangle " + Sites(t);
        return "outside";
    }
    public static string Query(string line) {
        string[] w = line.Split(' ');
        string type = w[0];
        int i = int.Parse(w[1]), j = w.Length == 3 ? int.Parse(w[2]) : 0;
        if (new string[] { "locate", "walk", "natural" }.Contains(type)) {
            Predicates.Point point = new Predicates.Point(i, j);
            if (type.Equals("locate")) {
                int nearest = 1;
                long distance = Predicates.D2(points[1], point);
                for (int s = 2; s <= n; s++) {
                    long d = Predicates.D2(points[s], point);
                    if (d < distance) {
                        nearest = s;
                        distance = d;
                    }
                }
                return Locate(point) + " nearest " + nearest + " d2 " + distance;
            }
            if (type.Equals("walk")) {
                Triangulation.Walk walk = Triangulation.VisibilityWalk(point, points, triangles, directed);
                string stop = walk.outside == null ? "triangle " + walk.path[^1]
                                                   : "outside " + walk.outside.a + " " + walk.outside.b;
                return "steps " + (walk.path.Count - 1) + " " + stop + " path " + Numbers(walk.path);
            }
            int count = 0;
            SortedSet<int> selected = new();
            foreach (Triangulation.Triangle t in triangles)
                if (Predicates.Incircle(points[t.a], points[t.b], points[t.c], point) > 0) {
                    count++;
                    selected.Add(t.a);
                    selected.Add(t.b);
                    selected.Add(t.c);
                }
            return "triangles " + count + " sites " + (selected.Count == 0 ? "-" : Numbers(new(selected)));
        }
        if (i < 1 || i > n || w.Length == 3 && (j < 1 || j > n))
            return "error unknown_site";
        if (type.Equals("neighbors"))
            return "degree " + neighbors[i].Count + " sites " + Numbers(neighbors[i]);
        if (type.Equals("route")) {
            Proximity.Route route = Proximity.GreedyRoute(points, neighbors, i, j);
            return "hops " + (route.sites.Count - 1) + " length " + Real(route.length) + " path " +
                   Numbers(route.sites);
        }
        if (type.Equals("path")) {
            List<int> path = paths[i].Path(j);
            double length = paths[i].distance[j];
            return "length " + Real(length) + " stretch " +
                   (i == j ? "-" : Real(length / Math.Sqrt(Predicates.D2(points[i], points[j])))) + " hops " +
                   (path.Count - 1) + " sites " + Numbers(path);
        }
        if (i == j)
            return "error same_site";
        Triangulation.Edge e = Triangulation.Key(i, j);
        if (directed.ContainsKey(e) || directed.ContainsKey(new Triangulation.Edge(e.b, e.a)))
            return "delaunay len2 " + Length2(e) + " gabriel " + (gabriel.Contains(e) ? "yes" : "no") +
                   " rng " + (rng.Contains(e) ? "yes" : "no") + " mst " +
                   (mstSet.Contains(e) ? "yes" : "no") + " dual " + Dual(e);
        List<string> crossing = new();
        foreach (Triangulation.Edge edge in edges)
            if (Predicates.Orient(points[i], points[j], points[edge.a]) *
                        Predicates.Orient(points[i], points[j], points[edge.b]) <
                    0 &&
                Predicates.Orient(points[edge.a], points[edge.b], points[i]) *
                        Predicates.Orient(points[edge.a], points[edge.b], points[j]) <
                    0)
                crossing.Add(edge.a + "-" + edge.b);
        return "missing crossings " + crossing.Count +
               (crossing.Count == 0 ? "" : " " + string.Join(" ", crossing));
    }
    public static void QuerySections() {
        List<string> output = new();
        foreach (string query in queries)
            output.Add(query + " " + Query(query));
        sections["queries"] = output;
    }
    public static void PlotSections() {
        char[][] canvas = Plot.Canvas(width, height);
        foreach (string layer in layers)
            switch (layer) {
            case "edges": {
                foreach (Triangulation.Edge e in edges)
                    Plot.Line(canvas, Plot.Map(points[e.a], width, height),
                              Plot.Map(points[e.b], width, height), '.');
                break;
            }
            case "mst": {
                foreach (Triangulation.Edge e in mst)
                    Plot.Line(canvas, Plot.Map(points[e.a], width, height),
                              Plot.Map(points[e.b], width, height), '*');
                break;
            }
            case "hull": {
                for (int t = 0; t < hull.Count; t++)
                    Plot.Line(canvas, Plot.Map(points[hull[t]], width, height),
                              Plot.Map(points[hull[(t + 1) % hull.Count]], width, height), '#');
                break;
            }
            case "sites": {
                for (int s = 1; s <= n; s++) {
                    Plot.Cell c = Plot.Map(points[s], width, height);
                    canvas[c.row][c.col] = 'o';
                }
                break;
            }
            case "circle": {
                if (empty > 0) {
                    Plot.Cell c = Plot.Center(vertices[empty - 1].center, width, height);
                    canvas[c.row][c.col] = '@';
                }
                break;
            }
            }
        sections["delaunay_plot"] = Plot.Frame(canvas);
        sections["voronoi_plot"] = Plot.Frame(Plot.Voronoi(points, width, height));
    }
    public static void Write() {
        List<string> files = ["triangulation.txt", "voronoi.txt", "derived.txt", "plot.txt"];
        List<List<string>> names = [
            ["input", "summary", "insertions", "triangles", "edges", "hull", "convex_layers", "quality"],
            ["vertices", "voronoi_edges", "cells"],
            [
                "nearest", "components", "mst", "proximity", "degrees", "empty_circle", "extent", "spanner",
                "alpha", "sites", "queries"
            ],
            ["delaunay_plot", "voronoi_plot"]
        ];
        for (int f = 0; f < files.Count; f++) {
            List<string> output = new();
            foreach (string section in requested)
                if (names[f].Contains(section)) {
                    output.Add("[" + section + "]");
                    output.AddRange(sections[section]);
                }
            File.WriteAllText(Path.Combine("output", files[f]),
                              output.Count == 0 ? "" : string.Join("\n", output) + "\n", Encoding.ASCII);
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Read();
        Organize();
        TriangulationSections();
        VoronoiSections();
        DerivedSections();
        QuerySections();
        PlotSections();
        Write();
    }
}
