import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.*;

public final class Main {
    static final class Settings {
        int snap = 1, fillHoles;
        boolean merge = true, degenerate = true, duplicates = true, orient = true, outward = true,
                keepUnused = true;
        List<String> sections = new ArrayList<>(List.of("summary", "components"));
        List<String[]> queries = new ArrayList<>();
    }
    static Settings settings() throws IOException {
        Settings s = new Settings();
        for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            String[] w = line.split(" ");
            switch (w[0]) {
            case "snap" -> s.snap = Integer.parseInt(w[1]);
            case "fill_holes" -> s.fillHoles = Integer.parseInt(w[1]);
            case "merge" -> s.merge = w[1].equals("on");
            case "degenerate" -> s.degenerate = w[1].equals("on");
            case "duplicates" -> s.duplicates = w[1].equals("on");
            case "orient" -> s.orient = w[1].equals("on");
            case "outward" -> s.outward = w[1].equals("on");
            case "keep_unused" -> s.keepUnused = w[1].equals("on");
            case "sections" -> s.sections = new ArrayList<>(Arrays.asList(w).subList(1, w.length));
            case "query" -> s.queries.add(Arrays.copyOfRange(w, 1, w.length));
            }
        }
        return s;
    }
    static String yes(boolean b) {
        return b ? "yes" : "no";
    }
    static String listing(Collection<?> values) {
        if (values.isEmpty())
            return "-";
        List<String> s = new ArrayList<>();
        for (Object x : values)
            s.add(x.toString());
        return String.join(" ", s);
    }
    static String numbers(int[] a) {
        List<Integer> s = new ArrayList<>();
        for (int x : a)
            s.add(x);
        return listing(s);
    }
    static String longs(long[] a) {
        List<Long> s = new ArrayList<>();
        for (long x : a)
            s.add(x);
        return listing(s);
    }
    static List<ObjIo.Face> selected(List<Integer> ids, List<ObjIo.Face> faces) {
        List<ObjIo.Face> result = new ArrayList<>();
        for (int i : ids)
            result.add(faces.get(i - 1));
        return result;
    }
    static final class Description {
        Topology.Component c;
        boolean closed, manifold, consistent, solid, orientable;
        int loops, euler;
        Integer genus, crosscaps;
        long volume;
        double area;
        Measure.Vec normal;
        long[] bbox;
        String centroid = "-";
        List<Integer> inside = new ArrayList<>();
        Map<String, Integer> shapes = new HashMap<>(), angles = new HashMap<>();
        long edgeMin = Long.MAX_VALUE, edgeMax;
        int valenceMin = Integer.MAX_VALUE, valenceMax;
    }
    static final class Analysis {
        ObjIo.Model source;
        Settings settings;
        List<Measure.Vec> snapped, points = new ArrayList<>();
        List<Repair.Snap> changes = new ArrayList<>();
        int[] representatives;
        SortedMap<Integer, Integer> renumber = new TreeMap<>();
        SortedMap<Integer, List<Integer>> merged = new TreeMap<>();
        List<ObjIo.Face> triangles, faces;
        List<Repair.Removed> removed = new ArrayList<>();
        Topology.Mesh before, mesh;
        List<Topology.Edge> inconsistentBefore, inconsistentAfter;
        List<Topology.Loop> loops;
        List<Description> components = new ArrayList<>();
        int initial, added, flipped, outward;
        Set<Integer> nonplanar = new HashSet<>();
        List<String> groups = new ArrayList<>();
    }
    static void increment(Map<String, Integer> m, String key) {
        m.put(key, m.getOrDefault(key, 0) + 1);
    }
    static int count(Map<String, Integer> m, String key) {
        return m.getOrDefault(key, 0);
    }
    static String shape(Topology.Edge e, Analysis a) {
        List<Integer> ids = a.mesh.edges.get(e);
        if (ids.size() != 2)
            return "-";
        ObjIo.Face f = a.faces.get(ids.get(0) - 1), g = a.faces.get(ids.get(1) - 1);
        if (Orientation.directed(f, e.a(), e.b()) == Orientation.directed(g, e.a(), e.b()))
            return "inconsistent";
        int third = 0;
        for (int v : g.v)
            if (v != e.a() && v != e.b())
                third = v;
        long signed = Measure.dot(Measure.subtract(a.points.get(third), a.points.get(f.v[0])),
                                  Measure.normal(f, a.points));
        return signed < 0 ? "convex" : signed > 0 ? "concave" : "flat";
    }
    static boolean nonplanar(ObjIo.Polygon polygon, List<Measure.Vec> points) {
        int[] v = polygon.v();
        Measure.Vec first = points.get(v[0]), normal = new Measure.Vec(0, 0, 0);
        for (int i = 1; i < v.length - 1; i++)
            normal = Measure.add(normal, Measure.cross(Measure.subtract(points.get(v[i]), first),
                                                       Measure.subtract(points.get(v[i + 1]), first)));
        for (int n : v)
            if (Measure.dot(Measure.subtract(points.get(n), first), normal) != 0)
                return true;
        return false;
    }
    static Analysis analyze(ObjIo.Model source, Settings settings) {
        Analysis a = new Analysis();
        a.source = source;
        a.settings = settings;
        a.snapped = Repair.snap(source.vertices, settings.snap, a.changes);
        a.representatives = Repair.representatives(a.snapped, settings.merge);
        a.triangles = Repair.split(source.polygons);
        a.faces = Repair.clean(a.triangles, a.snapped, a.representatives, settings.degenerate,
                               settings.duplicates, a.removed);
        SortedSet<Integer> present = new TreeSet<>();
        if (settings.keepUnused) {
            for (int i = 1; i < a.representatives.length; i++)
                if (a.representatives[i] == i)
                    present.add(i);
        } else
            for (ObjIo.Face f : a.faces)
                for (int v : f.v)
                    present.add(v);
        a.points.add(new Measure.Vec(0, 0, 0));
        for (int v : present) {
            a.renumber.put(v, a.points.size());
            a.points.add(a.snapped.get(v));
        }
        for (ObjIo.Face f : a.faces)
            for (int k = 0; k < 3; k++)
                f.v[k] = a.renumber.get(f.v[k]);
        List<int[]> original = new ArrayList<>();
        for (ObjIo.Face f : a.faces)
            original.add(f.v.clone());
        a.initial = a.faces.size();
        a.before = Topology.analyze(a.faces);
        a.inconsistentBefore = Orientation.inconsistent(a.faces, a.before.edges);
        if (settings.orient)
            Orientation.repair(a.faces, a.before.edges);
        a.inconsistentAfter = Orientation.inconsistent(a.faces, a.before.edges);
        a.loops = Topology.loops(a.faces, a.before);
        Set<Integer> permitted = new HashSet<>();
        for (Topology.Component c : a.before.components) {
            boolean consistent = true;
            for (Topology.Edge e : c.edges)
                if (a.inconsistentAfter.contains(e))
                    consistent = false;
            if (c.nonmanifold.isEmpty() && consistent)
                permitted.add(c.number);
        }
        a.added = Repair.fill(a.faces, a.loops, settings.fillHoles, permitted);
        a.mesh = Topology.analyze(a.faces);
        List<Topology.Edge> inconsistent = Orientation.inconsistent(a.faces, a.mesh.edges);
        for (Topology.Component c : a.mesh.components) {
            Description d = new Description();
            d.c = c;
            d.closed = c.boundary.isEmpty();
            d.manifold = c.nonmanifold.isEmpty() && c.nonmanifoldVertices.isEmpty();
            d.consistent = true;
            for (Topology.Edge e : c.edges)
                if (inconsistent.contains(e))
                    d.consistent = false;
            d.solid = d.closed && d.manifold && d.consistent;
            a.components.add(d);
        }
        for (Description d : a.components)
            if (d.solid)
                for (Description other : a.components)
                    if (other != d && other.solid) {
                        int vertex = 0;
                        for (int v : d.c.vertices)
                            if (!other.c.vertices.contains(v)) {
                                vertex = v;
                                break;
                            }
                        if (vertex != 0 &&
                            Measure.winding(other.c.faces, a.faces, a.points, a.points.get(vertex)) != 0)
                            d.inside.add(other.c.number);
                    }
        for (Description d : a.components)
            if (d.solid && settings.outward) {
                long volume = Measure.volume(d.c.faces, a.faces, a.points);
                if (volume != 0 &&
                    ((d.inside.size() % 2 == 0 && volume < 0) || (d.inside.size() % 2 == 1 && volume > 0))) {
                    for (int i : d.c.faces)
                        Orientation.flip(a.faces.get(i - 1));
                    a.outward++;
                }
            }
        for (int i = 0; i < a.initial; i++)
            if (!Arrays.equals(original.get(i), a.faces.get(i).v))
                a.flipped++;
        boolean[] orientable = Orientation.orientable(a.faces, a.mesh);
        int[] loopCount = new int[a.components.size() + 1];
        for (Topology.Loop loop : Topology.loops(a.faces, a.mesh))
            loopCount[loop.component]++;
        for (Description d : a.components) {
            Topology.Component c = d.c;
            d.orientable = orientable[c.number];
            d.loops = loopCount[c.number];
            d.euler = c.vertices.size() - c.edges.size() + c.faces.size();
            if (d.manifold) {
                if (d.orientable)
                    d.genus = Math.floorDiv(2 - d.euler - d.loops, 2);
                else
                    d.crosscaps = 2 - d.euler - d.loops;
            }
            d.volume = Measure.volume(c.faces, a.faces, a.points);
            d.area = Measure.area(selected(c.faces, a.faces), a.points);
            d.normal = new Measure.Vec(0, 0, 0);
            for (int i : c.faces) {
                ObjIo.Face f = a.faces.get(i - 1);
                d.normal = Measure.add(d.normal, Measure.normal(f, a.points));
                increment(d.angles, Measure.angle(f, a.points));
            }
            d.bbox = Measure.bbox(c.vertices, a.points);
            if (d.solid && d.volume != 0)
                d.centroid = Measure.centroid(c.faces, a.faces, a.points, d.volume);
            Map<Integer, Integer> degree = new HashMap<>();
            for (Topology.Edge e : c.edges) {
                increment(d.shapes, shape(e, a));
                long length = Measure.length(e, a.points);
                d.edgeMin = Math.min(d.edgeMin, length);
                d.edgeMax = Math.max(d.edgeMax, length);
                degree.put(e.a(), degree.getOrDefault(e.a(), 0) + 1);
                degree.put(e.b(), degree.getOrDefault(e.b(), 0) + 1);
            }
            for (int degreeValue : degree.values()) {
                d.valenceMin = Math.min(d.valenceMin, degreeValue);
                d.valenceMax = Math.max(d.valenceMax, degreeValue);
            }
        }
        for (ObjIo.Polygon p : source.polygons) {
            if (nonplanar(p, a.snapped))
                a.nonplanar.add(p.number());
            if (!a.groups.contains(p.group()))
                a.groups.add(p.group());
        }
        if (a.added > 0)
            a.groups.add("fill");
        for (int i = 1; i < a.representatives.length; i++)
            a.merged.computeIfAbsent(a.representatives[i], key -> new ArrayList<>()).add(i);
        return a;
    }
    static void summary(Analysis a, List<String> out) {
        ObjIo.Model s = a.source;
        Map<Integer, Integer> sizes = new TreeMap<>();
        for (ObjIo.Polygon p : s.polygons)
            sizes.put(p.v().length, sizes.getOrDefault(p.v().length, 0) + 1);
        Map<String, Integer> reasons = new HashMap<>();
        for (Repair.Removed r : a.removed)
            increment(reasons, r.reason());
        int merged = 0, holes = 0, solids = 0;
        long volume = 0;
        for (int i = 1; i < a.representatives.length; i++)
            if (a.representatives[i] != i)
                merged++;
        for (Topology.Loop l : a.loops)
            if (l.filled)
                holes++;
        for (Description d : a.components)
            if (d.solid) {
                solids++;
                volume += d.volume;
            }
        out.addAll(List.of("[summary]", "lines " + s.lines, "vertices " + (s.vertices.size() - 1),
                           "polygons " + s.polygons.size(), "errors " + s.errors.size(),
                           "ignored " + s.ignored, "nonplanar_polygons " + a.nonplanar.size()));
        for (var e : sizes.entrySet())
            out.add("polygon_size " + e.getKey() + " " + e.getValue());
        out.addAll(List.of("triangles " + a.triangles.size(), "snapped " + a.changes.size(),
                           "merged " + merged, "removed_repeated " + count(reasons, "repeated"),
                           "removed_zero_area " + count(reasons, "zero_area"),
                           "removed_duplicate " + count(reasons, "duplicate"), "faces " + a.initial,
                           "inconsistent_before " + a.inconsistentBefore.size(), "flipped_faces " + a.flipped,
                           "outward_components " + a.outward, "boundary_loops " + a.loops.size(),
                           "holes_filled " + holes, "fill_faces " + a.added,
                           "final_vertices " + (a.points.size() - 1), "final_faces " + a.faces.size(),
                           "components " + a.components.size(), "solids " + solids,
                           "total_area " + Measure.real(Measure.area(a.faces, a.points)),
                           "total_volume " + Measure.fraction(volume, 6)));
    }
    static void cleanup(Analysis a, List<String> out) {
        out.add("[cleanup]");
        out.add("snapped " + a.changes.size());
        for (Repair.Snap s : a.changes)
            out.add("snap " + s.number() + " " + s.before() + " to " + s.after());
        int merged = 0;
        for (int i = 1; i < a.representatives.length; i++)
            if (a.representatives[i] != i)
                merged++;
        out.add("merged " + merged);
        for (var e : a.merged.entrySet())
            if (e.getValue().size() > 1)
                out.add("merge " +
                        (a.renumber.containsKey(e.getKey()) ? a.renumber.get(e.getKey()).toString() : "-") +
                        " " + listing(e.getValue()));
        out.add("removed " + a.removed.size());
        for (Repair.Removed r : a.removed) {
            ObjIo.Face f = r.face();
            out.add("remove " + f.triangle + " polygon " + f.polygon + " line " + f.line + " " + r.reason());
        }
    }
    static void components(Analysis a, List<String> out) {
        for (Description d : a.components) {
            Topology.Component c = d.c;
            List<String> groups = new ArrayList<>();
            for (String g : a.groups) {
                boolean found = false;
                for (int i : c.faces)
                    if (a.faces.get(i - 1).group.equals(g))
                        found = true;
                if (found)
                    groups.add(g);
            }
            out.addAll(List.of(
                "[component " + c.number + "]", "groups " + listing(groups), "faces " + c.faces.size(),
                "vertices " + c.vertices.size(), "edges " + c.edges.size(),
                "boundary_edges " + c.boundary.size(), "nonmanifold_edges " + c.nonmanifold.size(),
                "nonmanifold_vertices " + c.nonmanifoldVertices.size(), "boundary_loops " + d.loops,
                "closed " + yes(d.closed), "manifold " + yes(d.manifold), "orientable " + yes(d.orientable),
                "consistent " + yes(d.consistent), "solid " + yes(d.solid), "euler " + d.euler,
                d.genus != null       ? "genus " + d.genus
                : d.crosscaps != null ? "crosscaps " + d.crosscaps
                                      : "genus -",
                "volume " + (d.solid ? Measure.fraction(d.volume, 6) : "-"), "area " + Measure.real(d.area),
                "normal_sum " + d.normal, "bbox " + longs(d.bbox), "inside " + listing(d.inside),
                "centroid " + d.centroid));
            for (String key : List.of("convex", "concave", "flat"))
                out.add(key + " " + count(d.shapes, key));
            for (String key : List.of("acute", "right", "obtuse"))
                out.add(key + " " + count(d.angles, key));
            out.add("edge_len2 " + d.edgeMin + " " + d.edgeMax);
            out.add("valence " + d.valenceMin + " " + d.valenceMax);
        }
    }
    static void groups(Analysis a, List<String> out) {
        for (String g : a.groups) {
            int polygons = 0, triangles = 0, nonplanar = 0;
            for (ObjIo.Polygon p : a.source.polygons)
                if (p.group().equals(g)) {
                    polygons++;
                    if (a.nonplanar.contains(p.number()))
                        nonplanar++;
                }
            for (ObjIo.Face f : a.triangles)
                if (f.group.equals(g))
                    triangles++;
            List<ObjIo.Face> chosen = new ArrayList<>();
            SortedSet<Integer> components = new TreeSet<>();
            for (int i = 0; i < a.faces.size(); i++)
                if (a.faces.get(i).group.equals(g)) {
                    chosen.add(a.faces.get(i));
                    components.add(a.mesh.faceComponent[i + 1]);
                }
            out.addAll(List.of("[group " + g + "]", "polygons " + polygons, "triangles " + triangles,
                               "nonplanar " + nonplanar, "faces " + chosen.size(),
                               "area " + Measure.real(Measure.area(chosen, a.points)),
                               "components " + listing(components)));
        }
    }
    static void contacts(Analysis a, List<String> out) {
        out.add("[contacts]");
        for (int i = 0; i < a.components.size(); i++)
            for (int j = i + 1; j < a.components.size(); j++) {
                Description f = a.components.get(i), g = a.components.get(j);
                boolean intersect = true;
                for (int k = 0; k < 3; k++)
                    if (f.bbox[k] > g.bbox[k + 3] || g.bbox[k] > f.bbox[k + 3])
                        intersect = false;
                if (!intersect)
                    continue;
                int shared = 0;
                long gap = Long.MAX_VALUE;
                for (int u : f.c.vertices) {
                    if (g.c.vertices.contains(u))
                        shared++;
                    for (int v : g.c.vertices)
                        if (u != v)
                            gap = Math.min(gap, Measure.length(Topology.edge(u, v), a.points));
                }
                out.add("contact " + f.c.number + " " + g.c.number + " shared " + shared + " gap2 " + gap);
            }
    }
    static String kind(int n) {
        return n == 1 ? "boundary" : n == 2 ? "manifold" : "nonmanifold";
    }
    static void edges(Analysis a, List<String> out) {
        Map<String, Integer> counts = new HashMap<>();
        int maxFaces = 0;
        Topology.Edge shortest = null, longest = null;
        long min = Long.MAX_VALUE, max = -1;
        for (var e : a.mesh.edges.entrySet()) {
            increment(counts, kind(e.getValue().size()));
            increment(counts, shape(e.getKey(), a));
            maxFaces = Math.max(maxFaces, e.getValue().size());
            long length = Measure.length(e.getKey(), a.points);
            if (length < min) {
                min = length;
                shortest = e.getKey();
            }
            if (length > max) {
                max = length;
                longest = e.getKey();
            }
        }
        out.addAll(List.of("[edges]", "edges " + a.mesh.edges.size(), "boundary " + count(counts, "boundary"),
                           "manifold " + count(counts, "manifold"),
                           "nonmanifold " + count(counts, "nonmanifold"), "max_faces " + maxFaces));
        for (String key : List.of("convex", "concave", "flat", "inconsistent"))
            out.add(key + " " + count(counts, key));
        out.add("shortest " + shortest + " len2 " + min);
        out.add("longest " + longest + " len2 " + max);
    }
    static void valence(Analysis a, List<String> out) {
        SortedMap<Integer, Integer> histogram = new TreeMap<>();
        long total = 0;
        int minimum = Integer.MAX_VALUE, maximum = 0;
        for (SortedSet<Integer> neighbors : a.mesh.neighbors.values()) {
            int d = neighbors.size();
            histogram.put(d, histogram.getOrDefault(d, 0) + 1);
            total += d;
            minimum = Math.min(minimum, d);
            maximum = Math.max(maximum, d);
        }
        int used = a.mesh.neighbors.size();
        out.addAll(List.of("[valence]", "used " + used, "isolated " + (a.points.size() - 1 - used),
                           "min " + minimum, "max " + maximum, "mean " + Measure.fraction(total, used)));
        for (var e : histogram.entrySet())
            out.add("degree " + e.getKey() + " " + e.getValue());
    }
    static String query(String[] w, Analysis a) {
        String kind = w[0];
        int x = Integer.parseInt(w[1]);
        String prefix = kind + " " + x;
        int nv = a.points.size() - 1;
        if (kind.equals("vertex")) {
            if (x < 1 || x > nv)
                return prefix + " invalid";
            int faces = 0;
            SortedSet<Integer> components = new TreeSet<>();
            for (int i = 1; i <= a.faces.size(); i++)
                for (int v : a.faces.get(i - 1).v)
                    if (v == x) {
                        faces++;
                        components.add(a.mesh.faceComponent[i]);
                        break;
                    }
            boolean boundary = false;
            for (var e : a.mesh.edges.entrySet())
                if ((e.getKey().a() == x || e.getKey().b() == x) && e.getValue().size() == 1)
                    boundary = true;
            int degree = a.mesh.neighbors.getOrDefault(x, new TreeSet<>()).size(),
                fans = a.mesh.fans.getOrDefault(x, new ArrayList<>()).size();
            return prefix + " at " + a.points.get(x) + " faces " + faces + " valence " + degree + " fans " +
                fans + " boundary " + yes(boundary) + " components " + listing(components);
        }
        if (kind.equals("face")) {
            if (x < 1 || x > a.faces.size())
                return prefix + " invalid";
            ObjIo.Face f = a.faces.get(x - 1);
            List<String> neighbors = new ArrayList<>();
            for (int k = 0; k < 3; k++) {
                List<Integer> ids = a.mesh.edges.get(Topology.edge(f.v[k], f.v[(k + 1) % 3]));
                neighbors.add(ids.size() == 1 ? "-"
                              : ids.size() >= 3
                                  ? "*"
                                  : Integer.toString(ids.get(0) == x ? ids.get(1) : ids.get(0)));
            }
            return prefix + " vertices " + numbers(f.v) + " group " + f.group + " polygon " +
                (f.polygon == 0 ? "-" : Integer.toString(f.polygon)) + " line " +
                (f.line == 0 ? "-" : Integer.toString(f.line)) + " component " + a.mesh.faceComponent[x] +
                " normal " + Measure.normal(f, a.points) + " area " +
                Measure.real(Measure.area(List.of(f), a.points)) + " neighbors " + listing(neighbors);
        }
        int y = Integer.parseInt(w[2]);
        if (kind.equals("edge")) {
            Topology.Edge e = Topology.edge(x, y);
            List<Integer> ids = a.mesh.edges.get(e);
            prefix = "edge " + e;
            if (ids == null)
                return prefix + " none";
            return prefix + " faces " + listing(ids) + " kind " + kind(ids.size()) + " shape " + shape(e, a) +
                " len2 " + Measure.length(e, a.points);
        }
        if (kind.equals("path")) {
            prefix += " " + y;
            if (x < 1 || x > nv || y < 1 || y > nv)
                return prefix + " invalid";
            int[] parent = new int[nv + 1];
            Arrays.fill(parent, -1);
            parent[x] = 0;
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            queue.add(x);
            while (!queue.isEmpty()) {
                int v = queue.remove();
                for (int n : a.mesh.neighbors.getOrDefault(v, new TreeSet<>()))
                    if (parent[n] == -1) {
                        parent[n] = v;
                        queue.add(n);
                    }
            }
            if (parent[y] == -1)
                return prefix + " none";
            List<Integer> path = new ArrayList<>();
            for (int n = y; n != 0; n = parent[n])
                path.add(n);
            Collections.reverse(path);
            return prefix + " hops " + (path.size() - 1) + " vertices " + listing(path);
        }
        int z = Integer.parseInt(w[3]);
        Measure.Vec p = new Measure.Vec(x, y, z);
        prefix = kind + " " + p;
        if (kind.equals("point")) {
            List<Integer> inside = new ArrayList<>();
            int sum = 0;
            for (Description d : a.components)
                if (d.solid) {
                    int winding = Measure.winding(d.c.faces, a.faces, a.points, p);
                    if (winding != 0) {
                        inside.add(d.c.number);
                        sum += winding;
                    }
                }
            return prefix + " inside " + listing(inside) + " winding " + sum;
        }
        long[] scores = new long[a.faces.size()];
        int front = 0, back = 0, side = 0, silhouette = 0;
        for (int i = 0; i < scores.length; i++) {
            scores[i] = Measure.dot(Measure.normal(a.faces.get(i), a.points), p);
            if (scores[i] > 0)
                front++;
            else if (scores[i] < 0)
                back++;
            else
                side++;
        }
        for (List<Integer> ids : a.mesh.edges.values())
            if (ids.size() == 2) {
                long f = scores[ids.get(0) - 1], g = scores[ids.get(1) - 1];
                if ((f > 0 && g < 0) || (f < 0 && g > 0))
                    silhouette++;
            }
        return prefix + " front " + front + " back " + back + " side " + side + " silhouette " + silhouette;
    }
    static List<String> boundaries(Analysis a) {
        List<String> out = new ArrayList<>();
        out.add("loops " + a.loops.size());
        for (Topology.Loop l : a.loops)
            out.add("loop " + l.number + " component " + l.component + " length " + l.length + " " + l.kind +
                    " " + (l.filled ? "filled" : "kept") + " vertices " + listing(l.vertices));
        List<Topology.Edge> edges = new ArrayList<>();
        for (var e : a.before.edges.entrySet())
            if (e.getValue().size() >= 3)
                edges.add(e.getKey());
        out.add("nonmanifold_edges " + edges.size());
        for (Topology.Edge e : edges)
            out.add("edge " + e + " faces " + listing(a.before.edges.get(e)));
        out.add("nonmanifold_vertices " + a.before.nonmanifoldVertices.size());
        for (int v : a.before.nonmanifoldVertices) {
            SortedSet<Integer> components = new TreeSet<>();
            for (List<Integer> fan : a.before.fans.get(v))
                for (int f : fan)
                    components.add(a.before.faceComponent[f]);
            out.add("vertex " + v + " fans " + a.before.fans.get(v).size() + " components " +
                    listing(components));
        }
        out.add("inconsistent_edges " + a.inconsistentAfter.size());
        for (Topology.Edge e : a.inconsistentAfter)
            out.add("edge " + e + " faces " + listing(a.before.edges.get(e)));
        return out;
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Analysis a = analyze(ObjIo.read(), settings());
        Files.createDirectories(Path.of("output"));
        List<String> out = new ArrayList<>();
        for (String section : a.settings.sections)
            switch (section) {
            case "summary" -> summary(a, out);
            case "warnings" -> {
                out.add("[warnings]");
                for (ObjIo.Error e : a.source.errors)
                    out.add("line " + e.line() + " " + e.kind());
            }
            case "cleanup" -> cleanup(a, out);
            case "components" -> components(a, out);
            case "groups" -> groups(a, out);
            case "contacts" -> contacts(a, out);
            case "edges" -> edges(a, out);
            case "valence" -> valence(a, out);
            case "queries" -> {
                out.add("[queries]");
                for (String[] w : a.settings.queries)
                    out.add(query(w, a));
            }
            }
        write("report.txt", out);
        List<String> csv =
            new ArrayList<>(List.of("component,faces,vertices,closed,euler,genus,volume6,area"));
        for (Description d : a.components)
            csv.add(d.c.number + "," + d.c.faces.size() + "," + d.c.vertices.size() + "," + yes(d.closed) +
                    "," + d.euler + "," + (d.genus == null ? "-" : d.genus.toString()) + "," +
                    (d.solid ? Long.toString(d.volume) : "-") + "," + Measure.real(d.area));
        write("components.csv", csv);
        write("boundaries.txt", boundaries(a));
        write("repaired.obj", ObjIo.repaired(a.points, a.faces));
    }
}
