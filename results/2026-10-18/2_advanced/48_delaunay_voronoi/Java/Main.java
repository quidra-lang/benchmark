import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class Main {
    static List<Predicates.Point> points = new ArrayList<>();
    static List<String> rejects = new ArrayList<>(), queries = new ArrayList<>();
    static List<String> requested = new ArrayList<>(List.of("summary")),
                        layers = new ArrayList<>(List.of("edges", "hull", "sites"));
    static List<Integer> alphas = new ArrayList<>();
    static int width = 61, height = 31, n, lineCount;
    static Triangulation.Model model;
    static List<Triangulation.Triangle> triangles;
    static List<Triangulation.Edge> edges, mst;
    static Map<Triangulation.Edge, Integer> directed = new HashMap<>();
    static Map<Integer, Integer> next = new HashMap<>(), previous = new HashMap<>();
    static List<Integer> hull = new ArrayList<>();
    static List<List<Integer>> neighbors = new ArrayList<>(), cells = new ArrayList<>(), components,
                               convexLayers = new ArrayList<>();
    static List<Triangulation.Insertion> insertions = new ArrayList<>();
    static List<Voronoi.Vertex> vertices = new ArrayList<>();
    static List<String> kinds = new ArrayList<>();
    static double[] minAngles, maxAngles, cellAreas, clipped;
    static long[] areas;
    static int[] nearest, component, depth;
    static Set<Triangulation.Edge> gabriel = new HashSet<>(), rng = new HashSet<>(), mstSet;
    static Proximity.Paths[] paths;
    static int empty;
    static Predicates.Center enclosingCenter;
    static double enclosingRadius2;
    static List<Integer> enclosingSites;
    static Map<String, List<String>> sections = new HashMap<>();
    static String real(double value) {
        return String.format(Locale.ROOT, "%.3f", value);
    }
    static String numbers(List<Integer> values) {
        List<String> words = new ArrayList<>();
        for (int value : values)
            words.add(Integer.toString(value));
        return String.join(" ", words);
    }
    static String sites(Triangulation.Triangle t) {
        return t.a() + " " + t.b() + " " + t.c();
    }
    static String direction(Predicates.Point p) {
        return p.x() + " " + p.y();
    }
    static String center(Predicates.Center c) {
        return Predicates.fraction(c.x(), c.d()) + " " + Predicates.fraction(c.y(), c.d());
    }
    static String number(int value) {
        return value == 0 ? "-" : Integer.toString(value);
    }
    static long length2(Triangulation.Edge e) {
        return Predicates.d2(points.get(e.a()), points.get(e.b()));
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static void read() throws IOException {
        points.add(new Predicates.Point(0, 0));
        List<String> source = lines("points.txt");
        lineCount = source.size();
        for (int i = 0; i < source.size(); i++) {
            String line = source.get(i);
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            String[] words = line.split(" ", -1);
            String prefix = "reject " + (i + 1) + " ";
            if (words.length != 2 || !words[0].matches("-?[0-9]+") || !words[1].matches("-?[0-9]+")) {
                rejects.add(prefix + "format");
                continue;
            }
            long x = Long.parseLong(words[0]), y = Long.parseLong(words[1]);
            if (x < 0 || x > 1000 || y < 0 || y > 1000) {
                rejects.add(prefix + "range");
                continue;
            }
            Predicates.Point point = new Predicates.Point(x, y);
            int duplicate = 0;
            for (int s = 1; s < points.size(); s++)
                if (points.get(s).equals(point)) {
                    duplicate = s;
                    break;
                }
            if (duplicate > 0)
                rejects.add(prefix + "duplicate " + duplicate);
            else
                points.add(point);
        }
        n = points.size() - 1;
        for (String line : lines("params.txt")) {
            if (line.isEmpty() || line.startsWith("#"))
                continue;
            String[] words = line.split(" ");
            switch (words[0]) {
            case "plot" -> {
                width = Integer.parseInt(words[1]);
                height = Integer.parseInt(words[2]);
            }
            case "plot_layers" -> layers = new ArrayList<>(Arrays.asList(words).subList(1, words.length));
            case "sections" -> requested = new ArrayList<>(Arrays.asList(words).subList(1, words.length));
            case "alpha" -> {
                for (int i = 1; i < words.length; i++)
                    alphas.add(Integer.parseInt(words[i]));
            }
            case "query" -> queries.add(line.substring(6));
            }
        }
    }
    static void organize() {
        model = new Triangulation.Model(points);
        for (int s = 4; s <= n; s++)
            insertions.add(model.insert(s));
        triangles = model.triangles();
        SortedSet<Triangulation.Edge> all = new TreeSet<>();
        for (int k = 0; k < triangles.size(); k++) {
            Triangulation.Triangle t = triangles.get(k);
            int[] a = t.sites();
            for (int j = 0; j < 3; j++) {
                int u = a[j], v = a[(j + 1) % 3];
                directed.put(new Triangulation.Edge(u, v), k + 1);
                all.add(Triangulation.key(u, v));
            }
        }
        edges = new ArrayList<>(all);
        for (Triangulation.Edge e : model.hullEdges()) {
            next.put(e.a(), e.b());
            previous.put(e.b(), e.a());
        }
        int start = Collections.min(next.keySet()), current = start;
        do {
            hull.add(current);
            current = next.get(current);
        } while (current != start);
        List<List<Integer>> adjacent = new ArrayList<>();
        for (int s = 0; s <= n; s++)
            adjacent.add(new ArrayList<>());
        for (Triangulation.Edge e : edges) {
            adjacent.get(e.a()).add(e.b());
            adjacent.get(e.b()).add(e.a());
        }
        neighbors.add(new ArrayList<>());
        for (int s = 1; s <= n; s++)
            neighbors.add(Voronoi.neighbors(s, adjacent.get(s), model.directed, next.get(s)));
        int count = triangles.size();
        minAngles = new double[count];
        maxAngles = new double[count];
        areas = new long[count];
        for (int k = 0; k < count; k++) {
            Triangulation.Triangle t = triangles.get(k);
            int[] a = t.sites();
            long area = Predicates.orient(points.get(t.a()), points.get(t.b()), points.get(t.c()));
            areas[k] = area;
            boolean right = false, obtuse = false;
            double minimum = 180, maximum = 0;
            for (int j = 0; j < 3; j++) {
                long dot =
                    Predicates.dot(points.get(a[j]), points.get(a[(j + 1) % 3]), points.get(a[(j + 2) % 3]));
                if (dot == 0)
                    right = true;
                if (dot < 0)
                    obtuse = true;
                double angle = Math.atan2((double)area, (double)dot) * 180 / Math.PI;
                minimum = Math.min(minimum, angle);
                maximum = Math.max(maximum, angle);
            }
            minAngles[k] = minimum;
            maxAngles[k] = maximum;
            kinds.add(right ? "right" : obtuse ? "obtuse" : "acute");
            Predicates.Center center =
                Predicates.center(points.get(t.a()), points.get(t.b()), points.get(t.c()));
            vertices.add(new Voronoi.Vertex(
                center, Voronoi.radius2(points.get(t.a()), points.get(t.b()), points.get(t.c())),
                Voronoi.position(center, hull, points)));
        }
        cells.add(new ArrayList<>());
        cellAreas = new double[n + 1];
        clipped = new double[n + 1];
        for (int s = 1; s <= n; s++) {
            List<Integer> ids = new ArrayList<>();
            for (int neighbor : neighbors.get(s)) {
                Integer id = directed.get(new Triangulation.Edge(s, neighbor));
                if (id != null)
                    ids.add(id);
            }
            cells.add(ids);
            if (!next.containsKey(s))
                cellAreas[s] = Voronoi.area(s, ids, vertices, points);
            clipped[s] = Voronoi.clipped(s, neighbors.get(s), points);
        }
        nearest = Proximity.nearest(points, neighbors);
        components = Proximity.components(nearest);
        component = new int[n + 1];
        for (int c = 0; c < components.size(); c++)
            for (int s : components.get(c))
                component[s] = c + 1;
        mst = Proximity.mst(points, edges);
        mstSet = new HashSet<>(mst);
        for (Triangulation.Edge e : edges) {
            if (Proximity.gabriel(points, e, model.directed))
                gabriel.add(e);
            if (Proximity.rng(points, e))
                rng.add(e);
        }
        for (int k = 0; k < vertices.size(); k++)
            if (vertices.get(k).position().equals("inside") &&
                (empty == 0 || vertices.get(k).r2() > vertices.get(empty - 1).r2()))
                empty = k + 1;
        paths = new Proximity.Paths[n + 1];
        for (int s = 1; s <= n; s++)
            paths[s] = Proximity.dijkstra(points, neighbors, s);
        layers();
        enclosing();
    }
    static List<Integer> convex(List<Integer> sites) {
        if (sites.size() <= 2) {
            List<Integer> result = new ArrayList<>(sites);
            Collections.sort(result);
            return result;
        }
        List<Integer> sorted = new ArrayList<>(sites);
        sorted.sort((a, b) -> {
            int c = Long.compare(points.get(a).x(), points.get(b).x());
            return c != 0 ? c : Long.compare(points.get(a).y(), points.get(b).y());
        });
        List<Integer> lower = new ArrayList<>(), upper = new ArrayList<>();
        for (int s : sorted) {
            while (lower.size() >= 2 && Predicates.orient(points.get(lower.get(lower.size() - 2)),
                                                          points.get(lower.getLast()), points.get(s)) <= 0)
                lower.removeLast();
            lower.add(s);
        }
        for (int i = sorted.size() - 1; i >= 0; i--) {
            int s = sorted.get(i);
            while (upper.size() >= 2 && Predicates.orient(points.get(upper.get(upper.size() - 2)),
                                                          points.get(upper.getLast()), points.get(s)) <= 0)
                upper.removeLast();
            upper.add(s);
        }
        lower.removeLast();
        upper.removeLast();
        lower.addAll(upper);
        int smallest = lower.indexOf(Collections.min(lower));
        List<Integer> result = new ArrayList<>();
        for (int i = 0; i < lower.size(); i++)
            result.add(lower.get((smallest + i) % lower.size()));
        return result;
    }
    static void layers() {
        depth = new int[n + 1];
        List<Integer> remaining = new ArrayList<>();
        for (int s = 1; s <= n; s++)
            remaining.add(s);
        while (!remaining.isEmpty()) {
            List<Integer> layer = convex(remaining);
            convexLayers.add(layer);
            for (int s : layer)
                depth[s] = convexLayers.size();
            remaining.removeAll(layer);
        }
    }
    static long circleTest(List<Integer> support, int site) {
        Predicates.Point p = points.get(site);
        if (support.size() == 1)
            return -Predicates.d2(p, points.get(support.get(0)));
        if (support.size() == 2)
            return -Predicates.dot(p, points.get(support.get(0)), points.get(support.get(1)));
        Predicates.Point a = points.get(support.get(0)), b = points.get(support.get(1)),
                         c = points.get(support.get(2));
        return Predicates.orient(a, b, c) > 0 ? Predicates.incircle(a, b, c, p)
                                              : Predicates.incircle(a, c, b, p);
    }
    static void enclosing() {
        List<Integer> support = new ArrayList<>();
        for (int i = 0; i < hull.size(); i++) {
            int a = hull.get(i);
            if (support.isEmpty() || circleTest(support, a) < 0) {
                support = new ArrayList<>(List.of(a));
                for (int j = 0; j < i; j++) {
                    int b = hull.get(j);
                    if (circleTest(support, b) < 0) {
                        support = new ArrayList<>(List.of(a, b));
                        for (int k = 0; k < j; k++) {
                            int c = hull.get(k);
                            if (circleTest(support, c) < 0)
                                support = new ArrayList<>(List.of(a, b, c));
                        }
                    }
                }
            }
        }
        enclosingSites = new ArrayList<>();
        for (int s = 1; s <= n; s++)
            if (circleTest(support, s) == 0)
                enclosingSites.add(s);
        for (int i = 0; i < enclosingSites.size(); i++)
            for (int j = i + 1; j < enclosingSites.size(); j++) {
                int a = enclosingSites.get(i), b = enclosingSites.get(j);
                boolean diameter = true;
                for (int s : enclosingSites)
                    if (Predicates.dot(points.get(s), points.get(a), points.get(b)) != 0)
                        diameter = false;
                if (diameter) {
                    enclosingCenter = new Predicates.Center(points.get(a).x() + points.get(b).x(),
                                                            points.get(a).y() + points.get(b).y(), 2);
                    enclosingRadius2 = Predicates.d2(points.get(a), points.get(b)) / 4.0;
                    return;
                }
            }
        int a = enclosingSites.get(0), b = enclosingSites.get(1), c = enclosingSites.get(2);
        if (Predicates.orient(points.get(a), points.get(b), points.get(c)) < 0) {
            int swap = b;
            b = c;
            c = swap;
        }
        enclosingCenter = Predicates.center(points.get(a), points.get(b), points.get(c));
        enclosingRadius2 = Voronoi.radius2(points.get(a), points.get(b), points.get(c));
    }
    static String dual(Triangulation.Edge e) {
        int left = directed.getOrDefault(e, 0),
            right = directed.getOrDefault(new Triangulation.Edge(e.b(), e.a()), 0);
        if (left > 0 && right > 0)
            return "segment " + left + " " + right;
        Predicates.Point direction = left > 0 ? Voronoi.outward(points.get(e.a()), points.get(e.b()))
                                              : Voronoi.outward(points.get(e.b()), points.get(e.a()));
        return "ray " + (left > 0 ? left : right) + " " + direction(direction);
    }
    static void triangulationSections() {
        List<String> out =
            new ArrayList<>(List.of("lines " + lineCount, "accepted " + n, "rejected " + rejects.size()));
        out.addAll(rejects);
        sections.put("input", out);
        int flips = 0, outside = 0, maxFlips = -1, maxSite = 0, acute = 0, right = 0, obtuse = 0;
        for (int i = 0; i < insertions.size(); i++) {
            Triangulation.Insertion insertion = insertions.get(i);
            flips += insertion.flips();
            if (insertion.kind().equals("outside"))
                outside++;
            if (insertion.flips() > maxFlips) {
                maxFlips = insertion.flips();
                maxSite = i + 4;
            }
        }
        for (String kind : kinds)
            if (kind.equals("acute"))
                acute++;
            else if (kind.equals("right"))
                right++;
            else
                obtuse++;
        sections.put("summary", new ArrayList<>(List.of(
                                    "sites " + n, "triangles " + triangles.size(), "edges " + edges.size(),
                                    "hull_vertices " + hull.size(), "interior_sites " + (n - hull.size()),
                                    "euler " + (n - edges.size() + triangles.size()), "flips " + flips,
                                    "outside_insertions " + outside,
                                    "max_flips " + (maxSite == 0 ? "none" : maxSite + " " + maxFlips),
                                    "acute " + acute, "right " + right, "obtuse " + obtuse)));
        out = new ArrayList<>(List.of("init " + sites(model.initial)));
        for (int i = 0; i < insertions.size(); i++) {
            Triangulation.Insertion insertion = insertions.get(i);
            out.add("insert " + (i + 4) + " " + insertion.kind() + " " +
                    (insertion.containing() == null ? Integer.toString(insertion.visible())
                                                    : sites(insertion.containing())) +
                    " flips " + insertion.flips() + " triangles " + insertion.triangles() + " hull " +
                    insertion.hull());
        }
        sections.put("insertions", out);
        out = new ArrayList<>();
        for (int k = 0; k < triangles.size(); k++) {
            Triangulation.Triangle t = triangles.get(k);
            out.add("tri " + (k + 1) + " " + sites(t) + " area2 " + areas[k] + " " + kinds.get(k) + " adj " +
                    number(directed.getOrDefault(new Triangulation.Edge(t.c(), t.b()), 0)) + " " +
                    number(directed.getOrDefault(new Triangulation.Edge(t.a(), t.c()), 0)) + " " +
                    number(directed.getOrDefault(new Triangulation.Edge(t.b(), t.a()), 0)));
        }
        sections.put("triangles", out);
        out = new ArrayList<>();
        for (Triangulation.Edge e : edges) {
            int left = directed.getOrDefault(e, 0),
                rightId = directed.getOrDefault(new Triangulation.Edge(e.b(), e.a()), 0);
            out.add("edge " + e.a() + " " + e.b() + " " + (left > 0 && rightId > 0 ? "inner" : "hull") +
                    " len2 " + length2(e) + " left " + number(left) + " right " + number(rightId));
        }
        sections.put("edges", out);
        double perimeter = 0;
        long area = 0;
        for (int i = 0; i < hull.size(); i++) {
            Predicates.Point a = points.get(hull.get(i)), b = points.get(hull.get((i + 1) % hull.size()));
            perimeter += Math.sqrt(Predicates.d2(a, b));
            area += a.x() * b.y() - b.x() * a.y();
        }
        sections.put("hull", new ArrayList<>(List.of("hull_vertices " + hull.size(), "order " + numbers(hull),
                                                     "perimeter " + real(perimeter), "area2 " + area)));
        out = new ArrayList<>(List.of("layers " + convexLayers.size()));
        for (int i = 0; i < convexLayers.size(); i++)
            out.add("layer " + (i + 1) + " size " + convexLayers.get(i).size() + " sites " +
                    numbers(convexLayers.get(i)));
        sections.put("convex_layers", out);
        int min = 0, max = 0;
        double total = 0;
        int[] histogram = new int[6];
        for (int k = 0; k < triangles.size(); k++) {
            if (minAngles[k] < minAngles[min])
                min = k;
            if (maxAngles[k] > maxAngles[max])
                max = k;
            total += minAngles[k];
            histogram[(int)(minAngles[k] / 10)]++;
        }
        out = new ArrayList<>(List.of("min_angle " + real(minAngles[min]) + " tri " + (min + 1),
                                      "max_angle " + real(maxAngles[max]) + " tri " + (max + 1),
                                      "mean_min_angle " + real(total / triangles.size())));
        for (int bin = 0; bin < 6; bin++)
            out.add("bin " + (10 * bin) + " " + (10 * (bin + 1)) + " " + histogram[bin]);
        sections.put("quality", out);
    }
    static void voronoiSections() {
        int inside = 0, on = 0, outside = 0;
        for (Voronoi.Vertex vertex : vertices)
            if (vertex.position().equals("inside"))
                inside++;
            else if (vertex.position().equals("on"))
                on++;
            else
                outside++;
        List<String> out = new ArrayList<>(List.of("inside " + inside, "on " + on, "outside " + outside));
        for (int k = 0; k < vertices.size(); k++) {
            Voronoi.Vertex v = vertices.get(k);
            out.add("v " + (k + 1) + " " + center(v.center()) + " r " + real(Math.sqrt(v.r2())) + " " +
                    v.position());
        }
        sections.put("vertices", out);
        out = new ArrayList<>(List.of("segments " + (edges.size() - hull.size()), "rays " + hull.size()));
        for (Triangulation.Edge e : edges)
            out.add("ve " + e.a() + " " + e.b() + " " + dual(e));
        sections.put("voronoi_edges", out);
        double total = 0, clipTotal = 0;
        int largest = 0;
        for (int s = 1; s <= n; s++) {
            clipTotal += clipped[s];
            if (!next.containsKey(s)) {
                total += cellAreas[s];
                if (largest == 0 || cellAreas[s] > cellAreas[largest])
                    largest = s;
            }
        }
        out = new ArrayList<>(List.of(
            "bounded " + (n - hull.size()), "unbounded " + hull.size(), "total_area " + real(total),
            "clip_total " + real(clipTotal),
            largest == 0 ? "largest none" : "largest " + largest + " area " + real(cellAreas[largest])));
        for (int s = 1; s <= n; s++) {
            String line = "cell " + s + " ";
            if (!next.containsKey(s))
                line += "bounded " + cells.get(s).size() + " area " + real(cellAreas[s]) + " clip " +
                        real(clipped[s]) + " vertices " + numbers(cells.get(s));
            else {
                Predicates.Point incoming = Voronoi.outward(points.get(s), points.get(next.get(s))),
                                 outgoing = Voronoi.outward(points.get(previous.get(s)), points.get(s));
                line += "unbounded " + cells.get(s).size() + " clip " + real(clipped[s]) + " from " +
                        direction(incoming) + " vertices " + numbers(cells.get(s)) + " to " +
                        direction(outgoing);
            }
            out.add(line);
        }
        sections.put("cells", out);
    }
    static void derivedSections() {
        int mutual = 0;
        for (int s = 1; s <= n; s++)
            if (nearest[nearest[s]] == s && s < nearest[s])
                mutual++;
        Triangulation.Edge closest = edges.get(0);
        for (Triangulation.Edge e : edges)
            if (length2(e) < length2(closest))
                closest = e;
        List<String> out =
            new ArrayList<>(List.of("mutual_pairs " + mutual, "closest_pair " + closest.a() + " " +
                                                                  closest.b() + " d2 " + length2(closest)));
        for (int s = 1; s <= n; s++)
            out.add("nn " + s + " " + nearest[s] + " d2 " +
                    Predicates.d2(points.get(s), points.get(nearest[s])) + " " +
                    (nearest[nearest[s]] == s ? "mutual" : "-"));
        sections.put("nearest", out);
        out = new ArrayList<>(List.of("components " + components.size()));
        for (int c = 0; c < components.size(); c++) {
            List<Integer> sites = components.get(c);
            int pair = 0;
            for (int s : sites)
                if (s < nearest[s] && nearest[nearest[s]] == s) {
                    pair = s;
                    break;
                }
            out.add("component " + (c + 1) + " size " + sites.size() + " pair " + pair + " " + nearest[pair] +
                    " sites " + numbers(sites));
        }
        sections.put("components", out);
        double length = 0;
        for (Triangulation.Edge e : mst)
            length += Math.sqrt(length2(e));
        Triangulation.Edge longest = mst.getLast();
        out = new ArrayList<>(
            List.of("edges " + (n - 1), "total_length " + real(length),
                    "longest " + longest.a() + " " + longest.b() + " len2 " + length2(longest)));
        for (Triangulation.Edge e : mst)
            out.add("mst " + e.a() + " " + e.b() + " len2 " + length2(e));
        sections.put("mst", out);
        out = new ArrayList<>(List.of("delaunay " + edges.size(), "gabriel " + gabriel.size(),
                                      "rng " + rng.size(), "mst " + (n - 1), "nn " + (n - mutual)));
        for (Triangulation.Edge e : edges)
            if (rng.contains(e) && !mstSet.contains(e))
                out.add("rng_extra " + e.a() + " " + e.b() + " len2 " + length2(e));
        sections.put("proximity", out);
        SortedMap<Integer, Integer> degreeCounts = new TreeMap<>();
        for (int s = 1; s <= n; s++) {
            int degree = neighbors.get(s).size();
            degreeCounts.put(degree, degreeCounts.getOrDefault(degree, 0) + 1);
        }
        out = new ArrayList<>(List.of("min " + Collections.min(degreeCounts.keySet()),
                                      "max " + Collections.max(degreeCounts.keySet())));
        for (int degree : degreeCounts.keySet())
            out.add("degree " + degree + " count " + degreeCounts.get(degree));
        sections.put("degrees", out);
        int candidates = 0;
        for (Voronoi.Vertex v : vertices)
            if (v.position().equals("inside"))
                candidates++;
        out = new ArrayList<>(List.of("candidates " + candidates));
        if (empty == 0)
            out.add("none");
        else {
            Voronoi.Vertex v = vertices.get(empty - 1);
            out.add("vertex " + empty);
            out.add("center " + center(v.center()));
            out.add("radius " + real(Math.sqrt(v.r2())));
            out.add("sites " + sites(triangles.get(empty - 1)));
        }
        sections.put("empty_circle", out);
        int diameterA = 1, diameterB = 2;
        long diameter = Predicates.d2(points.get(1), points.get(2));
        for (int i = 1; i <= n; i++)
            for (int j = i + 1; j <= n; j++) {
                long distance = Predicates.d2(points.get(i), points.get(j));
                if (distance > diameter) {
                    diameter = distance;
                    diameterA = i;
                    diameterB = j;
                }
            }
        double width = Double.POSITIVE_INFINITY;
        int edgeAt = 0;
        for (int t = 0; t < hull.size(); t++) {
            Predicates.Point a = points.get(hull.get(t)), b = points.get(hull.get((t + 1) % hull.size()));
            long farthest = 0;
            for (int s : hull)
                farthest = Math.max(farthest, Predicates.orient(a, b, points.get(s)));
            double candidate = farthest / Math.sqrt(Predicates.d2(a, b));
            if (candidate < width) {
                width = candidate;
                edgeAt = t;
            }
        }
        sections.put("extent",
                     new ArrayList<>(List.of("diameter " + diameterA + " " + diameterB + " d2 " + diameter,
                                             "width " + real(width) + " edge " + hull.get(edgeAt) + " " +
                                                 hull.get((edgeAt + 1) % hull.size()),
                                             "enclosing_center " + center(enclosingCenter),
                                             "enclosing_radius " + real(Math.sqrt(enclosingRadius2)),
                                             "enclosing_sites " + numbers(enclosingSites))));
        double totalStretch = 0, maxStretch = 0, maxLength = 0, maxDistance = 0;
        int pairA = 0, pairB = 0;
        for (int i = 1; i <= n; i++)
            for (int j = i + 1; j <= n; j++) {
                double distance = Math.sqrt(Predicates.d2(points.get(i), points.get(j))),
                       path = paths[i].distance()[j], stretch = path / distance;
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
        sections.put("spanner", new ArrayList<>(List.of("pairs " + pairs,
                                                        "max_stretch " + real(maxStretch) + " pair " + pairA +
                                                            " " + pairB + " length " + real(maxLength) +
                                                            " distance " + real(maxDistance),
                                                        "mean_stretch " + real(totalStretch / pairs))));
        out = new ArrayList<>();
        for (int alpha : alphas) {
            Set<Triangulation.Edge> selected = new HashSet<>();
            Map<Triangulation.Edge, Integer> selectedCounts = new HashMap<>();
            int faces = 0;
            long area2 = 0;
            for (int k = 0; k < triangles.size(); k++)
                if (vertices.get(k).r2() <= alpha) {
                    faces++;
                    area2 += areas[k];
                    int[] sites = triangles.get(k).sites();
                    for (int j = 0; j < 3; j++) {
                        Triangulation.Edge e = Triangulation.key(sites[j], sites[(j + 1) % 3]);
                        selected.add(e);
                        selectedCounts.put(e, selectedCounts.getOrDefault(e, 0) + 1);
                    }
                }
            for (Triangulation.Edge e : edges)
                if (gabriel.contains(e) && length2(e) <= 4L * alpha)
                    selected.add(e);
            Proximity.Sets sets = new Proximity.Sets(n);
            int boundary = 0, dangling = 0;
            Set<Integer> used = new HashSet<>();
            for (Triangulation.Edge e : edges)
                if (selected.contains(e)) {
                    sets.union(e.a(), e.b());
                    used.add(e.a());
                    used.add(e.b());
                    int count = selectedCounts.getOrDefault(e, 0);
                    if (count == 1)
                        boundary++;
                    if (count == 0)
                        dangling++;
                }
            out.add("alpha " + alpha + " triangles " + faces + " edges " + selected.size() + " boundary " +
                    boundary + " dangling " + dangling + " isolated " + (n - used.size()) + " components " +
                    sets.count + " holes " + (sets.count - (n - selected.size() + faces)) + " area2 " +
                    area2);
        }
        sections.put("alpha", out);
        out = new ArrayList<>();
        int[] gg = new int[n + 1], rg = new int[n + 1], mt = new int[n + 1];
        for (Triangulation.Edge e : edges) {
            if (gabriel.contains(e)) {
                gg[e.a()]++;
                gg[e.b()]++;
            }
            if (rng.contains(e)) {
                rg[e.a()]++;
                rg[e.b()]++;
            }
            if (mstSet.contains(e)) {
                mt[e.a()]++;
                mt[e.b()]++;
            }
        }
        for (int s = 1; s <= n; s++)
            out.add("site " + s + " " + direction(points.get(s)) + " " +
                    (next.containsKey(s) ? "hull" : "inner") + " dt " + neighbors.get(s).size() + " gg " +
                    gg[s] + " rng " + rg[s] + " mst " + mt[s] + " nn " + nearest[s] + " comp " +
                    component[s] + " depth " + depth[s]);
        sections.put("sites", out);
    }
    static String locate(Predicates.Point query) {
        for (int s = 1; s <= n; s++)
            if (points.get(s).equals(query))
                return "vertex " + s;
        for (Triangulation.Edge e : edges)
            if (Predicates.orient(points.get(e.a()), points.get(e.b()), query) == 0 &&
                Predicates.dot(query, points.get(e.a()), points.get(e.b())) < 0)
                return "edge " + e.a() + " " + e.b();
        for (Triangulation.Triangle t : triangles)
            if (Predicates.orient(points.get(t.a()), points.get(t.b()), query) > 0 &&
                Predicates.orient(points.get(t.b()), points.get(t.c()), query) > 0 &&
                Predicates.orient(points.get(t.c()), points.get(t.a()), query) > 0)
                return "triangle " + sites(t);
        return "outside";
    }
    static String query(String line) {
        String[] w = line.split(" ");
        String type = w[0];
        int i = Integer.parseInt(w[1]), j = w.length == 3 ? Integer.parseInt(w[2]) : 0;
        if (List.of("locate", "walk", "natural").contains(type)) {
            Predicates.Point point = new Predicates.Point(i, j);
            if (type.equals("locate")) {
                int nearest = 1;
                long distance = Predicates.d2(points.get(1), point);
                for (int s = 2; s <= n; s++) {
                    long d = Predicates.d2(points.get(s), point);
                    if (d < distance) {
                        nearest = s;
                        distance = d;
                    }
                }
                return locate(point) + " nearest " + nearest + " d2 " + distance;
            }
            if (type.equals("walk")) {
                Triangulation.Walk walk = Triangulation.walk(point, points, triangles, directed);
                String stop = walk.outside() == null
                                  ? "triangle " + walk.path().getLast()
                                  : "outside " + walk.outside().a() + " " + walk.outside().b();
                return "steps " + (walk.path().size() - 1) + " " + stop + " path " + numbers(walk.path());
            }
            int count = 0;
            SortedSet<Integer> selected = new TreeSet<>();
            for (Triangulation.Triangle t : triangles)
                if (Predicates.incircle(points.get(t.a()), points.get(t.b()), points.get(t.c()), point) > 0) {
                    count++;
                    selected.add(t.a());
                    selected.add(t.b());
                    selected.add(t.c());
                }
            return "triangles " + count + " sites " +
                (selected.isEmpty() ? "-" : numbers(new ArrayList<>(selected)));
        }
        if (i < 1 || i > n || w.length == 3 && (j < 1 || j > n))
            return "error unknown_site";
        if (type.equals("neighbors"))
            return "degree " + neighbors.get(i).size() + " sites " + numbers(neighbors.get(i));
        if (type.equals("route")) {
            Proximity.Route route = Proximity.route(points, neighbors, i, j);
            return "hops " + (route.sites().size() - 1) + " length " + real(route.length()) + " path " +
                numbers(route.sites());
        }
        if (type.equals("path")) {
            List<Integer> path = paths[i].path(j);
            double length = paths[i].distance()[j];
            return "length " + real(length) + " stretch " +
                (i == j ? "-" : real(length / Math.sqrt(Predicates.d2(points.get(i), points.get(j))))) +
                " hops " + (path.size() - 1) + " sites " + numbers(path);
        }
        if (i == j)
            return "error same_site";
        Triangulation.Edge e = Triangulation.key(i, j);
        if (directed.containsKey(e) || directed.containsKey(new Triangulation.Edge(e.b(), e.a())))
            return "delaunay len2 " + length2(e) + " gabriel " + (gabriel.contains(e) ? "yes" : "no") +
                " rng " + (rng.contains(e) ? "yes" : "no") + " mst " + (mstSet.contains(e) ? "yes" : "no") +
                " dual " + dual(e);
        List<String> crossing = new ArrayList<>();
        for (Triangulation.Edge edge : edges)
            if (Predicates.orient(points.get(i), points.get(j), points.get(edge.a())) *
                        Predicates.orient(points.get(i), points.get(j), points.get(edge.b())) <
                    0 &&
                Predicates.orient(points.get(edge.a()), points.get(edge.b()), points.get(i)) *
                        Predicates.orient(points.get(edge.a()), points.get(edge.b()), points.get(j)) <
                    0)
                crossing.add(edge.a() + "-" + edge.b());
        return "missing crossings " + crossing.size() +
            (crossing.isEmpty() ? "" : " " + String.join(" ", crossing));
    }
    static void querySections() {
        List<String> out = new ArrayList<>();
        for (String query : queries)
            out.add(query + " " + query(query));
        sections.put("queries", out);
    }
    static void plotSections() {
        char[][] canvas = Plot.canvas(width, height);
        for (String layer : layers)
            switch (layer) {
            case "edges" -> {
                for (Triangulation.Edge e : edges)
                    Plot.line(canvas, Plot.map(points.get(e.a()), width, height),
                              Plot.map(points.get(e.b()), width, height), '.');
            }
            case "mst" -> {
                for (Triangulation.Edge e : mst)
                    Plot.line(canvas, Plot.map(points.get(e.a()), width, height),
                              Plot.map(points.get(e.b()), width, height), '*');
            }
            case "hull" -> {
                for (int t = 0; t < hull.size(); t++)
                    Plot.line(canvas, Plot.map(points.get(hull.get(t)), width, height),
                              Plot.map(points.get(hull.get((t + 1) % hull.size())), width, height), '#');
            }
            case "sites" -> {
                for (int s = 1; s <= n; s++) {
                    Plot.Cell c = Plot.map(points.get(s), width, height);
                    canvas[c.row()][c.col()] = 'o';
                }
            }
            case "circle" -> {
                if (empty > 0) {
                    Plot.Cell c = Plot.center(vertices.get(empty - 1).center(), width, height);
                    canvas[c.row()][c.col()] = '@';
                }
            }
            }
        sections.put("delaunay_plot", Plot.frame(canvas));
        sections.put("voronoi_plot", Plot.frame(Plot.voronoi(points, width, height)));
    }
    static void write() throws IOException {
        List<String> files = List.of("triangulation.txt", "voronoi.txt", "derived.txt", "plot.txt");
        List<List<String>> names =
            List.of(List.of("input", "summary", "insertions", "triangles", "edges", "hull", "convex_layers",
                            "quality"),
                    List.of("vertices", "voronoi_edges", "cells"),
                    List.of("nearest", "components", "mst", "proximity", "degrees", "empty_circle", "extent",
                            "spanner", "alpha", "sites", "queries"),
                    List.of("delaunay_plot", "voronoi_plot"));
        for (int f = 0; f < files.size(); f++) {
            List<String> out = new ArrayList<>();
            for (String section : requested)
                if (names.get(f).contains(section)) {
                    out.add("[" + section + "]");
                    out.addAll(sections.get(section));
                }
            Files.writeString(Path.of("output", files.get(f)),
                              out.isEmpty() ? "" : String.join("\n", out) + "\n", StandardCharsets.US_ASCII);
        }
    }
    public static void main(String[] args) throws IOException {
        read();
        organize();
        triangulationSections();
        voronoiSections();
        derivedSections();
        querySections();
        plotSections();
        write();
    }
}
