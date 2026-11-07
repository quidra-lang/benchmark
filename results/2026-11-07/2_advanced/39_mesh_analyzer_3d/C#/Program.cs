using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public sealed class Settings {
        public int snap = 1, fillHoles;
        public bool merge = true, degenerate = true, duplicates = true, orient = true, outward = true,
                    keepUnused = true;
        public List<string> sections = ["summary", "components"];
        public List<string[]> queries = new();
    }
    public static Settings ReadSettings() {
        Settings s = new Settings();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)) {
            if (line.Length == 0 || line.StartsWith("#"))
                continue;
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "snap":
                s.snap = int.Parse(w[1]);
                break;
            case "fill_holes":
                s.fillHoles = int.Parse(w[1]);
                break;
            case "merge":
                s.merge = w[1].Equals("on");
                break;
            case "degenerate":
                s.degenerate = w[1].Equals("on");
                break;
            case "duplicates":
                s.duplicates = w[1].Equals("on");
                break;
            case "orient":
                s.orient = w[1].Equals("on");
                break;
            case "outward":
                s.outward = w[1].Equals("on");
                break;
            case "keep_unused":
                s.keepUnused = w[1].Equals("on");
                break;
            case "sections":
                s.sections = w.Skip(1).ToList();
                break;
            case "query":
                s.queries.Add(w[1..w.Length]);
                break;
            }
        }
        return s;
    }
    public static string Yes(bool b) {
        return b ? "yes" : "no";
    }
    public static string Listing<T>(IEnumerable<T> values) {
        return values.Any() ? string.Join(" ", values) : "-";
    }
    public static string Numbers(int[] a) {
        List<int> s = new();
        foreach (int x in a)
            s.Add(x);
        return Listing(s);
    }
    public static string Longs(long[] a) {
        List<long> s = new();
        foreach (long x in a)
            s.Add(x);
        return Listing(s);
    }
    static List<ObjIo.Face> Selected(List<int> ids, List<ObjIo.Face> faces) {
        List<ObjIo.Face> result = new();
        foreach (int i in ids)
            result.Add(faces[i - 1]);
        return result;
    }
    public sealed class Description {
        public Topology.Component c;
        public bool closed, manifold, consistent, solid, orientable;
        public int loops, euler;
        public int? genus, crosscaps;
        public long volume;
        public double area;
        public Measure.Vec normal;
        public long[] bbox;
        public string centroid = "-";
        public List<int> inside = new();
        public Dictionary<string, int> shapes = new(), angles = new();
        public long edgeMin = long.MaxValue, edgeMax;
        public int valenceMin = int.MaxValue, valenceMax;
    }
    public sealed class Analysis {
        public ObjIo.Model source;
        public Settings settings;
        public List<Measure.Vec> snapped, points = new();
        public List<Repair.Snap> changes = new();
        public int[] representatives;
        public SortedDictionary<int, int> renumber = new();
        public SortedDictionary<int, List<int>> merged = new();
        public List<ObjIo.Face> triangles, faces;
        public List<Repair.Removed> removed = new();
        public Topology.Mesh before, mesh;
        public List<Topology.Edge> inconsistentBefore, inconsistentAfter;
        public List<Topology.Loop> loops;
        public List<Description> components = new();
        public int initial, added, flipped, outward;
        public HashSet<int> nonplanar = new();
        public List<string> groups = new();
    }
    public static void Increment(Dictionary<string, int> m, string key) {
        m[key] = m.GetValueOrDefault(key, 0) + 1;
    }
    public static int Count(Dictionary<string, int> m, string key) {
        return m.GetValueOrDefault(key, 0);
    }
    public static string Shape(Topology.Edge e, Analysis a) {
        List<int> ids = a.mesh.edges[e];
        if (ids.Count != 2)
            return "-";
        ObjIo.Face f = a.faces[ids[0] - 1], g = a.faces[ids[1] - 1];
        if (Orientation.Directed(f, e.a, e.b) == Orientation.Directed(g, e.a, e.b))
            return "inconsistent";
        int third = 0;
        foreach (int v in g.v)
            if (v != e.a && v != e.b)
                third = v;
        long signed =
            Measure.Dot(Measure.Subtract(a.points[third], a.points[f.v[0]]), Measure.Normal(f, a.points));
        return signed < 0 ? "convex" : signed > 0 ? "concave" : "flat";
    }
    public static bool Nonplanar(ObjIo.Polygon polygon, List<Measure.Vec> points) {
        int[] v = polygon.v;
        Measure.Vec first = points[v[0]], normal = new Measure.Vec(0, 0, 0);
        for (int i = 1; i < v.Length - 1; i++)
            normal = Measure.Add(normal, Measure.Cross(Measure.Subtract(points[v[i]], first),
                                                       Measure.Subtract(points[v[i + 1]], first)));
        foreach (int n in v)
            if (Measure.Dot(Measure.Subtract(points[n], first), normal) != 0)
                return true;
        return false;
    }
    public static Analysis Analyze(ObjIo.Model source, Settings settings) {
        Analysis a = new Analysis();
        a.source = source;
        a.settings = settings;
        a.snapped = Repair.SnapVertices(source.vertices, settings.snap, a.changes);
        a.representatives = Repair.Representatives(a.snapped, settings.merge);
        a.triangles = Repair.Split(source.polygons);
        a.faces = Repair.Clean(a.triangles, a.snapped, a.representatives, settings.degenerate,
                               settings.duplicates, a.removed);
        SortedSet<int> present = new SortedSet<int>();
        if (settings.keepUnused) {
            for (int i = 1; i < a.representatives.Length; i++)
                if (a.representatives[i] == i)
                    present.Add(i);
        } else
            foreach (ObjIo.Face f in a.faces)
                foreach (int v in f.v)
                    present.Add(v);
        a.points.Add(new Measure.Vec(0, 0, 0));
        foreach (int v in present) {
            a.renumber[v] = a.points.Count;
            a.points.Add(a.snapped[v]);
        }
        foreach (ObjIo.Face f in a.faces)
            for (int k = 0; k < 3; k++)
                f.v[k] = a.renumber[f.v[k]];
        List<int[]> original = new();
        foreach (ObjIo.Face f in a.faces)
            original.Add(f.v.ToArray());
        a.initial = a.faces.Count;
        a.before = Topology.Analyze(a.faces);
        a.inconsistentBefore = Orientation.Inconsistent(a.faces, a.before.edges);
        if (settings.orient)
            Orientation.Repair(a.faces, a.before.edges);
        a.inconsistentAfter = Orientation.Inconsistent(a.faces, a.before.edges);
        a.loops = Topology.Loops(a.faces, a.before);
        HashSet<int> permitted = new();
        foreach (Topology.Component c in a.before.components) {
            bool consistent = true;
            foreach (Topology.Edge e in c.edges)
                if (a.inconsistentAfter.Contains(e))
                    consistent = false;
            if (c.nonmanifold.Count == 0 && consistent)
                permitted.Add(c.number);
        }
        a.added = Repair.Fill(a.faces, a.loops, settings.fillHoles, permitted);
        a.mesh = Topology.Analyze(a.faces);
        List<Topology.Edge> inconsistent = Orientation.Inconsistent(a.faces, a.mesh.edges);
        foreach (Topology.Component c in a.mesh.components) {
            Description d = new Description();
            d.c = c;
            d.closed = c.boundary.Count == 0;
            d.manifold = c.nonmanifold.Count == 0 && c.nonmanifoldVertices.Count == 0;
            d.consistent = true;
            foreach (Topology.Edge e in c.edges)
                if (inconsistent.Contains(e))
                    d.consistent = false;
            d.solid = d.closed && d.manifold && d.consistent;
            a.components.Add(d);
        }
        foreach (Description d in a.components)
            if (d.solid)
                foreach (Description other in a.components)
                    if (other != d && other.solid) {
                        int vertex = 0;
                        foreach (int v in d.c.vertices)
                            if (!other.c.vertices.Contains(v)) {
                                vertex = v;
                                break;
                            }
                        if (vertex != 0 &&
                            Measure.Winding(other.c.faces, a.faces, a.points, a.points[vertex]) != 0)
                            d.inside.Add(other.c.number);
                    }
        foreach (Description d in a.components)
            if (d.solid && settings.outward) {
                long volume = Measure.Volume(d.c.faces, a.faces, a.points);
                if (volume != 0 &&
                    ((d.inside.Count % 2 == 0 && volume < 0) || (d.inside.Count % 2 == 1 && volume > 0))) {
                    foreach (int i in d.c.faces)
                        Orientation.Flip(a.faces[i - 1]);
                    a.outward++;
                }
            }
        for (int i = 0; i < a.initial; i++)
            if (!Enumerable.SequenceEqual(original[i], a.faces[i].v))
                a.flipped++;
        bool[] orientable = Orientation.Orientable(a.faces, a.mesh);
        int[] loopCount = new int[a.components.Count + 1];
        foreach (Topology.Loop loop in Topology.Loops(a.faces, a.mesh))
            loopCount[loop.component]++;
        foreach (Description d in a.components) {
            Topology.Component c = d.c;
            d.orientable = orientable[c.number];
            d.loops = loopCount[c.number];
            d.euler = c.vertices.Count - c.edges.Count + c.faces.Count;
            if (d.manifold) {
                if (d.orientable)
                    d.genus = (int)Measure.FloorDiv(2 - d.euler - d.loops, 2);
                else
                    d.crosscaps = 2 - d.euler - d.loops;
            }
            d.volume = Measure.Volume(c.faces, a.faces, a.points);
            d.area = Measure.Area(Selected(c.faces, a.faces), a.points);
            d.normal = new Measure.Vec(0, 0, 0);
            foreach (int i in c.faces) {
                ObjIo.Face f = a.faces[i - 1];
                d.normal = Measure.Add(d.normal, Measure.Normal(f, a.points));
                Increment(d.angles, Measure.Angle(f, a.points));
            }
            d.bbox = Measure.Bbox(c.vertices, a.points);
            if (d.solid && d.volume != 0)
                d.centroid = Measure.Centroid(c.faces, a.faces, a.points, d.volume);
            Dictionary<int, int> degree = new();
            foreach (Topology.Edge e in c.edges) {
                Increment(d.shapes, Shape(e, a));
                long length = Measure.Length(e, a.points);
                d.edgeMin = Math.Min(d.edgeMin, length);
                d.edgeMax = Math.Max(d.edgeMax, length);
                degree[e.a] = degree.GetValueOrDefault(e.a, 0) + 1;
                degree[e.b] = degree.GetValueOrDefault(e.b, 0) + 1;
            }
            foreach (int degreeValue in degree.Values) {
                d.valenceMin = Math.Min(d.valenceMin, degreeValue);
                d.valenceMax = Math.Max(d.valenceMax, degreeValue);
            }
        }
        foreach (ObjIo.Polygon p in source.polygons) {
            if (Nonplanar(p, a.snapped))
                a.nonplanar.Add(p.number);
            if (!a.groups.Contains(p.group))
                a.groups.Add(p.group);
        }
        if (a.added > 0)
            a.groups.Add("fill");
        for (int i = 1; i < a.representatives.Length; i++)
            a.merged.GetOrAdd(a.representatives[i], key => new()).Add(i);
        return a;
    }
    public static void Summary(Analysis a, List<string> output) {
        ObjIo.Model s = a.source;
        Dictionary<int, int> sizes = new();
        foreach (ObjIo.Polygon p in s.polygons)
            sizes[p.v.Length] = sizes.GetValueOrDefault(p.v.Length, 0) + 1;
        Dictionary<string, int> reasons = new();
        foreach (Repair.Removed r in a.removed)
            Increment(reasons, r.reason);
        int merged = 0, holes = 0, solids = 0;
        long volume = 0;
        for (int i = 1; i < a.representatives.Length; i++)
            if (a.representatives[i] != i)
                merged++;
        foreach (Topology.Loop l in a.loops)
            if (l.filled)
                holes++;
        foreach (Description d in a.components)
            if (d.solid) {
                solids++;
                volume += d.volume;
            }
        output.AddRange([
            "[summary]", "lines " + s.lines, "vertices " + (s.vertices.Count - 1),
            "polygons " + s.polygons.Count, "errors " + s.errors.Count, "ignored " + s.ignored,
            "nonplanar_polygons " + a.nonplanar.Count
        ]);
        foreach (var e in sizes)
            output.Add("polygon_size " + e.Key + " " + e.Value);
        output.AddRange([
            "triangles " + a.triangles.Count, "snapped " + a.changes.Count, "merged " + merged,
            "removed_repeated " + Count(reasons, "repeated"),
            "removed_zero_area " + Count(reasons, "zero_area"),
            "removed_duplicate " + Count(reasons, "duplicate"), "faces " + a.initial,
            "inconsistent_before " + a.inconsistentBefore.Count, "flipped_faces " + a.flipped,
            "outward_components " + a.outward, "boundary_loops " + a.loops.Count, "holes_filled " + holes,
            "fill_faces " + a.added, "final_vertices " + (a.points.Count - 1), "final_faces " + a.faces.Count,
            "components " + a.components.Count, "solids " + solids,
            "total_area " + Measure.Real(Measure.Area(a.faces, a.points)),
            "total_volume " + Measure.Fraction(volume, 6)
        ]);
    }
    public static void Cleanup(Analysis a, List<string> output) {
        output.Add("[cleanup]");
        output.Add("snapped " + a.changes.Count);
        foreach (Repair.Snap s in a.changes)
            output.Add("snap " + s.number + " " + s.before + " to " + s.after);
        int merged = 0;
        for (int i = 1; i < a.representatives.Length; i++)
            if (a.representatives[i] != i)
                merged++;
        output.Add("merged " + merged);
        foreach (var e in a.merged)
            if (e.Value.Count > 1)
                output.Add("merge " + (a.renumber.ContainsKey(e.Key) ? a.renumber[e.Key].ToString() : "-") +
                           " " + Listing(e.Value));
        output.Add("removed " + a.removed.Count);
        foreach (Repair.Removed r in a.removed) {
            ObjIo.Face f = r.face;
            output.Add("remove " + f.triangle + " polygon " + f.polygon + " line " + f.line + " " + r.reason);
        }
    }
    public static void Components(Analysis a, List<string> output) {
        foreach (Description d in a.components) {
            Topology.Component c = d.c;
            List<string> groups = new();
            foreach (string g in a.groups) {
                bool found = false;
                foreach (int i in c.faces)
                    if (a.faces[i - 1].group.Equals(g))
                        found = true;
                if (found)
                    groups.Add(g);
            }
            output.AddRange([
                "[component " + c.number + "]",
                "groups " + Listing(groups),
                "faces " + c.faces.Count,
                "vertices " + c.vertices.Count,
                "edges " + c.edges.Count,
                "boundary_edges " + c.boundary.Count,
                "nonmanifold_edges " + c.nonmanifold.Count,
                "nonmanifold_vertices " + c.nonmanifoldVertices.Count,
                "boundary_loops " + d.loops,
                "closed " + Yes(d.closed),
                "manifold " + Yes(d.manifold),
                "orientable " + Yes(d.orientable),
                "consistent " + Yes(d.consistent),
                "solid " + Yes(d.solid),
                "euler " + d.euler,
                d.genus != null       ? "genus " + d.genus
                : d.crosscaps != null ? "crosscaps " + d.crosscaps
                                      : "genus -",
                "volume " + (d.solid ? Measure.Fraction(d.volume, 6) : "-"),
                "area " + Measure.Real(d.area),
                "normal_sum " + d.normal,
                "bbox " + Longs(d.bbox),
                "inside " + Listing(d.inside),
                "centroid " + d.centroid
            ]);
            foreach (string key in["convex", "concave", "flat"])
                output.Add(key + " " + Count(d.shapes, key));
            foreach (string key in["acute", "right", "obtuse"])
                output.Add(key + " " + Count(d.angles, key));
            output.Add("edge_len2 " + d.edgeMin + " " + d.edgeMax);
            output.Add("valence " + d.valenceMin + " " + d.valenceMax);
        }
    }
    public static void Groups(Analysis a, List<string> output) {
        foreach (string g in a.groups) {
            int polygons = 0, triangles = 0, nonplanar = 0;
            foreach (ObjIo.Polygon p in a.source.polygons)
                if (p.group.Equals(g)) {
                    polygons++;
                    if (a.nonplanar.Contains(p.number))
                        nonplanar++;
                }
            foreach (ObjIo.Face f in a.triangles)
                if (f.group.Equals(g))
                    triangles++;
            List<ObjIo.Face> chosen = new();
            SortedSet<int> components = new SortedSet<int>();
            for (int i = 0; i < a.faces.Count; i++)
                if (a.faces[i].group.Equals(g)) {
                    chosen.Add(a.faces[i]);
                    components.Add(a.mesh.faceComponent[i + 1]);
                }
            output.AddRange([
                "[group " + g + "]", "polygons " + polygons, "triangles " + triangles,
                "nonplanar " + nonplanar, "faces " + chosen.Count,
                "area " + Measure.Real(Measure.Area(chosen, a.points)), "components " + Listing(components)
            ]);
        }
    }
    public static void Contacts(Analysis a, List<string> output) {
        output.Add("[contacts]");
        for (int i = 0; i < a.components.Count; i++)
            for (int j = i + 1; j < a.components.Count; j++) {
                Description f = a.components[i], g = a.components[j];
                bool intersect = true;
                for (int k = 0; k < 3; k++)
                    if (f.bbox[k] > g.bbox[k + 3] || g.bbox[k] > f.bbox[k + 3])
                        intersect = false;
                if (!intersect)
                    continue;
                int shared = 0;
                long gap = long.MaxValue;
                foreach (int u in f.c.vertices) {
                    if (g.c.vertices.Contains(u))
                        shared++;
                    foreach (int v in g.c.vertices)
                        if (u != v)
                            gap = Math.Min(gap, Measure.Length(Topology.KeyEdge(u, v), a.points));
                }
                output.Add("contact " + f.c.number + " " + g.c.number + " shared " + shared + " gap2 " + gap);
            }
    }
    public static string Kind(int n) {
        return n == 1 ? "boundary" : n == 2 ? "manifold" : "nonmanifold";
    }
    public static void Edges(Analysis a, List<string> output) {
        Dictionary<string, int> counts = new();
        int maxFaces = 0;
        Topology.Edge shortest = null, longest = null;
        long min = long.MaxValue, max = -1;
        foreach (var e in a.mesh.edges) {
            Increment(counts, Kind(e.Value.Count));
            Increment(counts, Shape(e.Key, a));
            maxFaces = Math.Max(maxFaces, e.Value.Count);
            long length = Measure.Length(e.Key, a.points);
            if (length < min) {
                min = length;
                shortest = e.Key;
            }
            if (length > max) {
                max = length;
                longest = e.Key;
            }
        }
        output.AddRange([
            "[edges]", "edges " + a.mesh.edges.Count, "boundary " + Count(counts, "boundary"),
            "manifold " + Count(counts, "manifold"), "nonmanifold " + Count(counts, "nonmanifold"),
            "max_faces " + maxFaces
        ]);
        foreach (string key in["convex", "concave", "flat", "inconsistent"])
            output.Add(key + " " + Count(counts, key));
        output.Add("shortest " + shortest + " len2 " + min);
        output.Add("longest " + longest + " len2 " + max);
    }
    public static void Valence(Analysis a, List<string> output) {
        SortedDictionary<int, int> histogram = new();
        long total = 0;
        int minimum = int.MaxValue, maximum = 0;
        foreach (SortedSet<int> neighbors in a.mesh.neighbors.Values) {
            int d = neighbors.Count;
            histogram[d] = histogram.GetValueOrDefault(d, 0) + 1;
            total += d;
            minimum = Math.Min(minimum, d);
            maximum = Math.Max(maximum, d);
        }
        int used = a.mesh.neighbors.Count;
        output.AddRange([
            "[valence]", "used " + used, "isolated " + (a.points.Count - 1 - used), "min " + minimum,
            "max " + maximum, "mean " + Measure.Fraction(total, used)
        ]);
        foreach (var e in histogram)
            output.Add("degree " + e.Key + " " + e.Value);
    }
    public static string Query(string[] w, Analysis a) {
        string kind = w[0];
        int x = int.Parse(w[1]);
        string prefix = kind + " " + x;
        int nv = a.points.Count - 1;
        if (kind.Equals("vertex")) {
            if (x < 1 || x > nv)
                return prefix + " invalid";
            int faces = 0;
            SortedSet<int> components = new SortedSet<int>();
            for (int i = 1; i <= a.faces.Count; i++)
                foreach (int v in a.faces[i - 1].v)
                    if (v == x) {
                        faces++;
                        components.Add(a.mesh.faceComponent[i]);
                        break;
                    }
            bool boundary = false;
            foreach (var e in a.mesh.edges)
                if ((e.Key.a == x || e.Key.b == x) && e.Value.Count == 1)
                    boundary = true;
            int degree = a.mesh.neighbors.GetValueOrDefault(x, new SortedSet<int>()).Count,
                fans = a.mesh.fans.GetValueOrDefault(x, new()).Count;
            return prefix + " at " + a.points[x] + " faces " + faces + " valence " + degree + " fans " +
                   fans + " boundary " + Yes(boundary) + " components " + Listing(components);
        }
        if (kind.Equals("face")) {
            if (x < 1 || x > a.faces.Count)
                return prefix + " invalid";
            ObjIo.Face f = a.faces[x - 1];
            List<string> neighbors = new();
            for (int k = 0; k < 3; k++) {
                List<int> ids = a.mesh.edges[Topology.KeyEdge(f.v[k], f.v[(k + 1) % 3])];
                neighbors.Add(ids.Count == 1   ? "-"
                              : ids.Count >= 3 ? "*"
                                               : Convert.ToString(ids[0] == x ? ids[1] : ids[0]));
            }
            return prefix + " vertices " + Numbers(f.v) + " group " + f.group + " polygon " +
                   (f.polygon == 0 ? "-" : Convert.ToString(f.polygon)) + " line " +
                   (f.line == 0 ? "-" : Convert.ToString(f.line)) + " component " + a.mesh.faceComponent[x] +
                   " normal " + Measure.Normal(f, a.points) + " area " +
                   Measure.Real(Measure.Area([f], a.points)) + " neighbors " + Listing(neighbors);
        }
        int y = int.Parse(w[2]);
        if (kind.Equals("edge")) {
            Topology.Edge e = Topology.KeyEdge(x, y);
            List<int> ids = a.mesh.edges.GetValueOrDefault(e);
            prefix = "edge " + e;
            if (ids == null)
                return prefix + " none";
            return prefix + " faces " + Listing(ids) + " kind " + Kind(ids.Count) + " shape " + Shape(e, a) +
                   " len2 " + Measure.Length(e, a.points);
        }
        if (kind.Equals("path")) {
            prefix += " " + y;
            if (x < 1 || x > nv || y < 1 || y > nv)
                return prefix + " invalid";
            int[] parent = new int[nv + 1];
            Array.Fill(parent, -1);
            parent[x] = 0;
            Queue<int> queue = new();
            queue.Enqueue(x);
            while (queue.Count != 0) {
                int v = queue.Dequeue();
                foreach (int n in a.mesh.neighbors.GetValueOrDefault(v, new SortedSet<int>()))
                    if (parent[n] == -1) {
                        parent[n] = v;
                        queue.Enqueue(n);
                    }
            }
            if (parent[y] == -1)
                return prefix + " none";
            List<int> path = new();
            for (int n = y; n != 0; n = parent[n])
                path.Add(n);
            path.Reverse();
            return prefix + " hops " + (path.Count - 1) + " vertices " + Listing(path);
        }
        int z = int.Parse(w[3]);
        Measure.Vec p = new Measure.Vec(x, y, z);
        prefix = kind + " " + p;
        if (kind.Equals("point")) {
            List<int> inside = new();
            int sum = 0;
            foreach (Description d in a.components)
                if (d.solid) {
                    int winding = Measure.Winding(d.c.faces, a.faces, a.points, p);
                    if (winding != 0) {
                        inside.Add(d.c.number);
                        sum += winding;
                    }
                }
            return prefix + " inside " + Listing(inside) + " winding " + sum;
        }
        long[] scores = new long[a.faces.Count];
        int front = 0, back = 0, side = 0, silhouette = 0;
        for (int i = 0; i < scores.Length; i++) {
            scores[i] = Measure.Dot(Measure.Normal(a.faces[i], a.points), p);
            if (scores[i] > 0)
                front++;
            else if (scores[i] < 0)
                back++;
            else
                side++;
        }
        foreach (List<int> ids in a.mesh.edges.Values)
            if (ids.Count == 2) {
                long f = scores[ids[0] - 1], g = scores[ids[1] - 1];
                if ((f > 0 && g < 0) || (f < 0 && g > 0))
                    silhouette++;
            }
        return prefix + " front " + front + " back " + back + " side " + side + " silhouette " + silhouette;
    }
    public static List<string> Boundaries(Analysis a) {
        List<string> output = new();
        output.Add("loops " + a.loops.Count);
        foreach (Topology.Loop l in a.loops)
            output.Add("loop " + l.number + " component " + l.component + " length " + l.length + " " +
                       l.kind + " " + (l.filled ? "filled" : "kept") + " vertices " + Listing(l.vertices));
        List<Topology.Edge> edges = new();
        foreach (var e in a.before.edges)
            if (e.Value.Count >= 3)
                edges.Add(e.Key);
        output.Add("nonmanifold_edges " + edges.Count);
        foreach (Topology.Edge e in edges)
            output.Add("edge " + e + " faces " + Listing(a.before.edges[e]));
        output.Add("nonmanifold_vertices " + a.before.nonmanifoldVertices.Count);
        foreach (int v in a.before.nonmanifoldVertices) {
            SortedSet<int> components = new SortedSet<int>();
            foreach (List<int> fan in a.before.fans[v])
                foreach (int f in fan)
                    components.Add(a.before.faceComponent[f]);
            output.Add("vertex " + v + " fans " + a.before.fans[v].Count + " components " +
                       Listing(components));
        }
        output.Add("inconsistent_edges " + a.inconsistentAfter.Count);
        foreach (Topology.Edge e in a.inconsistentAfter)
            output.Add("edge " + e + " faces " + Listing(a.before.edges[e]));
        return output;
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Analysis a = Analyze(ObjIo.Read(), ReadSettings());
        Directory.CreateDirectory(Path.Combine("output"));
        List<string> output = new();
        foreach (string section in a.settings.sections)
            switch (section) {
            case "summary":
                Summary(a, output);
                break;
            case "warnings": {
                output.Add("[warnings]");
                foreach (ObjIo.Error e in a.source.errors)
                    output.Add("line " + e.line + " " + e.kind);
                break;
            }
            case "cleanup":
                Cleanup(a, output);
                break;
            case "components":
                Components(a, output);
                break;
            case "groups":
                Groups(a, output);
                break;
            case "contacts":
                Contacts(a, output);
                break;
            case "edges":
                Edges(a, output);
                break;
            case "valence":
                Valence(a, output);
                break;
            case "queries": {
                output.Add("[queries]");
                foreach (string[] w in a.settings.queries)
                    output.Add(Query(w, a));
                break;
            }
            }
        Write("report.txt", output);
        List<string> csv = ["component,faces,vertices,closed,euler,genus,volume6,area"];
        foreach (Description d in a.components)
            csv.Add(d.c.number + "," + d.c.faces.Count + "," + d.c.vertices.Count + "," + Yes(d.closed) +
                    "," + d.euler + "," + (d.genus == null ? "-" : d.genus.ToString()) + "," +
                    (d.solid ? Convert.ToString(d.volume) : "-") + "," + Measure.Real(d.area));
        Write("components.csv", csv);
        Write("boundaries.txt", Boundaries(a));
        Write("repaired.obj", ObjIo.Repaired(a.points, a.faces));
    }
}
