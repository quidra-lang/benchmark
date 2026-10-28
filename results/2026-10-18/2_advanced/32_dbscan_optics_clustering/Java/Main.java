import java.io.*;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static char character(int label) {
        return label < 0 ? '.'
        : label < 26     ? (char)('A' + label)
        : label < 52     ? (char)('a' + label - 26)
                         : '#';
    }
    static String optional(int value) {
        return value == Optics.INF || value < 0 ? "-" : Integer.toString(value);
    }
    static String joined(Collection<Integer> values) {
        List<String> parts = new ArrayList<>();
        for (int value : values)
            parts.add(Integer.toString(value));
        return String.join(" ", parts);
    }
    static String test(boolean value) {
        return value ? "ok" : "mismatch";
    }
    static String condition(boolean value) {
        return value ? "ok" : "fail";
    }
    static List<String> join(List<List<String>> parts) {
        List<String> lines = new ArrayList<>();
        for (List<String> part : parts) {
            if (!lines.isEmpty())
                lines.add("");
            lines.addAll(part);
        }
        return lines;
    }
    static int radius(int value) {
        int low = 1, high = 46341;
        while (low < high) {
            int middle = (low + high) / 2;
            if ((long)middle * middle >= value)
                high = middle;
            else
                low = middle + 1;
        }
        return low;
    }
    static long pairs(long count) {
        return count * (count - 1) / 2;
    }
    static final class Curve {
        final List<Integer> order = new ArrayList<>();
        final int[] values;
        final int knee, eps;
        final long cross;
        Curve(int[] distances) {
            int count = distances.length;
            for (int i = 0; i < count; i++)
                order.add(i);
            order.sort(
                Comparator.<Integer>comparingInt(i -> distances[i]).reversed().thenComparingInt(i -> i));
            values = new int[count];
            for (int i = 0; i < count; i++)
                values[i] = distances[order.get(i)];
            long maximum = -1;
            int knee = 0;
            for (int i = 0; i < count; i++) {
                long value = Math.abs((count - 1L) * (values[i] - values[0]) -
                                      (long)(values[count - 1] - values[0]) * i);
                if (value > maximum) {
                    maximum = value;
                    knee = i;
                }
            }
            this.knee = knee;
            cross = maximum;
            eps = radius(values[knee]);
        }
    }
    static final class GridSummary {
        final int eps, candidates, pairs, brutePairs;
        final GridIndex grid;
        final int[][] neighborhoods;
        final boolean consistent;
        final Map<Integer, Integer> occupancy = new TreeMap<>();
        GridSummary(List<Point> points, int eps) {
            this.eps = eps;
            grid = new GridIndex(points, eps);
            neighborhoods = new int[points.size()][];
            int candidates = 0, total = 0, bruteTotal = 0;
            boolean consistent = true;
            int[] brute = grid.bruteCounts();
            for (int i = 0; i < points.size(); i++) {
                Neighborhood neighbors = grid.neighborhood(i);
                neighborhoods[i] = neighbors.points();
                candidates += neighbors.candidates();
                total += neighborhoods[i].length;
                bruteTotal += brute[i];
                if (neighborhoods[i].length != brute[i])
                    consistent = false;
            }
            this.candidates = candidates;
            pairs = (total - points.size()) / 2;
            brutePairs = (bruteTotal - points.size()) / 2;
            this.consistent = consistent;
            for (List<Integer> cell : grid.cells.values())
                occupancy.merge(cell.size(), 1, Integer::sum);
        }
        List<String> lines() {
            Cell cell = grid.busiest();
            List<String> sizes = new ArrayList<>();
            for (Map.Entry<Integer, Integer> entry : occupancy.entrySet())
                sizes.add(entry.getKey() + ":" + entry.getValue());
            return List.of("eps " + eps + " cells " + grid.cells.size() + " busiest " + cell.x() + " " +
                               cell.y() + " " + grid.cells.get(cell).size() + " candidates " + candidates +
                               " pairs " + pairs + " brute_pairs " + brutePairs + " " + test(consistent),
                           "  occupancy " + String.join(" ", sizes));
        }
    }
    static final class Setting {
        final String name;
        final int kind, radius, count, noise, coreCount, borderCount;
        final int[] labels;
        final boolean[] core;
        final List<List<Integer>> members = new ArrayList<>();
        Setting(String name, int kind, int radius, Clustering clustering) {
            this.name = name;
            this.kind = kind;
            this.radius = radius;
            labels = clustering.labels();
            core = clustering.core();
            int maximum = -1, noise = 0, coreCount = 0;
            for (int i = 0; i < labels.length; i++) {
                maximum = Math.max(maximum, labels[i]);
                if (labels[i] < 0)
                    noise++;
                else if (core[i])
                    coreCount++;
            }
            count = maximum + 1;
            this.noise = noise;
            this.coreCount = coreCount;
            borderCount = labels.length - noise - coreCount;
            for (int label = 0; label < count; label++)
                members.add(new ArrayList<>());
            for (int i = 0; i < labels.length; i++)
                if (labels[i] >= 0)
                    members.get(labels[i]).add(i);
        }
    }
    static Clustering extract(Optics optics, int radius) {
        int[] labels = new int[optics.reach.length];
        Arrays.fill(labels, -1);
        boolean[] core = new boolean[labels.length];
        int cluster = -1;
        for (int i = 0; i < core.length; i++)
            core[i] = optics.core[i] <= radius * radius;
        for (int i : optics.order) {
            if (optics.reach[i] > radius * radius) {
                if (core[i])
                    labels[i] = ++cluster;
            } else
                labels[i] = cluster;
        }
        return new Clustering(labels, core);
    }
    record Area(String kind, int start, int end) {}
    record Range(int start, int end) {
        int size() {
            return end - start + 1;
        }
    }
    static final class DownArea {
        final int start, end;
        int high;
        DownArea(int start, int end) {
            this.start = start;
            this.end = end;
        }
    }
    static final class Xi {
        final int[] reach, labels, clusterLabels, parents;
        final boolean[] steepUp, steepDown, up, down;
        final int count, minimum, minimumSize;
        final long alpha, beta;
        final List<Area> areas = new ArrayList<>();
        final List<Range> clusters = new ArrayList<>();
        Xi(int[] reach, Dataset data) {
            this.reach = reach;
            count = reach.length - 1;
            minimum = data.value("MIN_PTS");
            minimumSize = data.value("XI_MIN_SIZE");
            String[] fraction = data.settings.get("XI")[0].split("/");
            int u = Integer.parseInt(fraction[0]), v = Integer.parseInt(fraction[1]);
            alpha = (long)(v - u) * (v - u);
            beta = (long)v * v;
            steepUp = new boolean[count];
            steepDown = new boolean[count];
            up = new boolean[count];
            down = new boolean[count];
            for (int i = 0; i < count; i++) {
                boolean defined = reach[i] != Optics.INF || reach[i + 1] != Optics.INF;
                steepUp[i] = defined && xle(reach[i], reach[i + 1]);
                steepDown[i] = defined && xle(reach[i + 1], reach[i]);
                up[i] = reach[i] < reach[i + 1];
                down[i] = reach[i] > reach[i + 1];
            }
            scan();
            labels = new int[count];
            Arrays.fill(labels, -1);
            clusterLabels = new int[clusters.size()];
            parents = new int[clusters.size()];
            Arrays.fill(clusterLabels, -1);
            Arrays.fill(parents, -1);
            int next = 0;
            for (int i = 0; i < clusters.size(); i++) {
                Range range = clusters.get(i);
                boolean free = true;
                for (int p = range.start(); p <= range.end(); p++)
                    if (labels[p] >= 0)
                        free = false;
                if (free) {
                    clusterLabels[i] = next;
                    for (int p = range.start(); p <= range.end(); p++)
                        labels[p] = next;
                    next++;
                }
            }
            for (int j = 0; j < clusters.size(); j++) {
                Range range = clusters.get(j);
                int size = Integer.MAX_VALUE;
                for (int i = 0; i < clusters.size(); i++) {
                    Range other = clusters.get(i);
                    if (i == j || other.start() > range.start() || range.end() > other.end() ||
                        other.size() < range.size() || other.size() == range.size() && i < j)
                        continue;
                    if (other.size() < size) {
                        parents[j] = i;
                        size = other.size();
                    }
                }
            }
        }
        boolean xle(int a, int b) {
            if (b == Optics.INF)
                return true;
            if (a == Optics.INF)
                return false;
            return beta * a <= alpha * b;
        }
        int end(int start, boolean[] steep, boolean[] reverse) {
            int end = start, flat = 0;
            for (int i = start; i < count; i++) {
                if (steep[i]) {
                    end = i;
                    flat = 0;
                } else if (reverse[i])
                    break;
                else if (++flat > minimum)
                    break;
            }
            return end;
        }
        void scan() {
            List<DownArea> downAreas = new ArrayList<>();
            int index = 0, mib = 0;
            for (int start = 0; start < count; start++) {
                if (start < index || !steepUp[start] && !steepDown[start])
                    continue;
                for (int i = index; i <= start; i++)
                    mib = Math.max(mib, reach[i]);
                if (mib == Optics.INF)
                    downAreas.clear();
                else {
                    List<DownArea> retained = new ArrayList<>();
                    for (DownArea area : downAreas)
                        if (xle(mib, reach[area.start])) {
                            area.high = Math.max(area.high, mib);
                            retained.add(area);
                        }
                    downAreas = retained;
                }
                if (steepDown[start]) {
                    int end = end(start, steepDown, up);
                    areas.add(new Area("down", start, end));
                    downAreas.add(new DownArea(start, end));
                    index = end + 1;
                    mib = reach[index];
                } else {
                    int end = end(start, steepUp, down);
                    areas.add(new Area("up", start, end));
                    index = end + 1;
                    mib = reach[index];
                    List<Range> candidates = new ArrayList<>();
                    for (DownArea area : downAreas) {
                        int cs = area.start, ce = end;
                        if (!xle(area.high, reach[ce + 1]))
                            continue;
                        int top = reach[area.start];
                        if (xle(reach[ce + 1], top)) {
                            while (cs < area.end && reach[cs + 1] > reach[ce + 1])
                                cs++;
                        } else if (xle(top, reach[ce + 1])) {
                            while (ce > start && reach[ce - 1] > top)
                                ce--;
                        }
                        if (ce - cs + 1 >= minimumSize && cs <= area.end && ce >= start)
                            candidates.add(new Range(cs, ce));
                    }
                    Collections.reverse(candidates);
                    clusters.addAll(candidates);
                }
            }
        }
    }
    static long turn(Point origin, Point a, Point b) {
        return (long)(a.x() - origin.x()) * (b.y() - origin.y()) -
            (long)(a.y() - origin.y()) * (b.x() - origin.x());
    }
    static List<Point> halfHull(List<Point> ordered) {
        List<Point> chain = new ArrayList<>();
        for (Point point : ordered) {
            while (chain.size() >= 2 && turn(chain.get(chain.size() - 2), chain.getLast(), point) <= 0)
                chain.removeLast();
            chain.add(point);
        }
        return chain;
    }
    static List<Point> hull(List<Point> members) {
        List<Point> ordered = new ArrayList<>(members);
        ordered.sort(Comparator.comparingInt(Point::x).thenComparingInt(Point::y));
        if (ordered.size() <= 2)
            return ordered;
        List<Point> lower = halfHull(ordered);
        Collections.reverse(ordered);
        List<Point> upper = halfHull(ordered);
        lower.removeLast();
        upper.removeLast();
        lower.addAll(upper);
        return lower;
    }
    static long[] ari(int[] first, int[] second) {
        int n = first.length;
        int[] rows = new int[n + 1], columns = new int[n + 1];
        Map<Long, Integer> cells = new HashMap<>();
        for (int i = 0; i < n; i++) {
            int a = first[i] + 1, b = second[i] + 1;
            rows[a]++;
            columns[b]++;
            cells.merge((long)a * (n + 1) + b, 1, Integer::sum);
        }
        long same = 0, a = 0, b = 0;
        for (int count : cells.values())
            same += pairs(count);
        for (int count : rows)
            a += pairs(count);
        for (int count : columns)
            b += pairs(count);
        long total = pairs(n), numerator = 2 * (total * same - a * b),
             denominator = total * (a + b) - 2 * a * b;
        return denominator == 0 ? new long[] {1, 1} : new long[] {numerator, denominator};
    }
    static final class Analysis {
        final Dataset data;
        final List<Point> points;
        final int n, minimum, k;
        final int[] kdist, mapColumns, mapRows;
        final List<Curve> curves = new ArrayList<>();
        final Curve curve;
        final Map<Integer, GridSummary> grids = new TreeMap<>();
        final List<Setting> settings = new ArrayList<>();
        final Setting knee, xiSetting;
        final Optics optics;
        final int[] positions;
        final Xi xi;
        Analysis(Dataset data) {
            this.data = data;
            points = data.points;
            n = points.size();
            minimum = data.value("MIN_PTS");
            k = minimum - 1;
            int[][] nearest = new int[n][];
            for (int i = 0; i < n; i++) {
                int[] distances = new int[n - 1];
                int position = 0;
                for (int j = 0; j < n; j++)
                    if (j != i)
                        distances[position++] = GridIndex.distance(points.get(i), points.get(j));
                Arrays.sort(distances);
                nearest[i] = Arrays.copyOf(distances, 2 * minimum);
            }
            for (int j = 0; j < 2 * minimum; j++) {
                int[] distances = new int[n];
                for (int i = 0; i < n; i++)
                    distances[i] = nearest[i][j];
                curves.add(new Curve(distances));
            }
            curve = curves.get(k - 1);
            kdist = new int[n];
            for (int i = 0; i < n; i++)
                kdist[i] = nearest[i][k - 1];
            Set<Integer> radii = new TreeSet<>();
            for (int value : data.values("EPS"))
                radii.add(value);
            radii.add(curve.eps);
            radii.add(data.value("OPTICS_MAX_EPS"));
            for (int radius : radii)
                grids.put(radius, new GridSummary(points, radius));
            for (int radius : data.values("EPS"))
                addDbscan("db" + radius, radius);
            knee = addDbscan("knee" + curve.eps, curve.eps);
            optics = new Optics(points, grids.get(data.value("OPTICS_MAX_EPS")).neighborhoods, minimum);
            for (int radius : data.values("EXTRACT_EPS"))
                settings.add(new Setting("op" + radius, 1, radius, extract(optics, radius)));
            positions = new int[n + 1];
            for (int i = 0; i < n; i++)
                positions[i] = optics.reach[optics.order.get(i)];
            positions[n] = Optics.INF;
            xi = new Xi(positions, data);
            int[] labels = new int[n];
            boolean[] core = new boolean[n];
            for (int i = 0; i < n; i++) {
                labels[optics.order.get(i)] = xi.labels[i];
                core[i] = optics.core[i] != Optics.INF;
            }
            xiSetting = new Setting("xi", 2, data.value("OPTICS_MAX_EPS"), new Clustering(labels, core));
            settings.add(xiSetting);
            int minX = Integer.MAX_VALUE, minY = Integer.MAX_VALUE, maxX = 0, maxY = 0;
            for (Point point : points) {
                minX = Math.min(minX, point.x());
                maxX = Math.max(maxX, point.x());
                minY = Math.min(minY, point.y());
                maxY = Math.max(maxY, point.y());
            }
            mapColumns = new int[n];
            mapRows = new int[n];
            for (int i = 0; i < n; i++) {
                mapColumns[i] = (points.get(i).x() - minX) * data.value("MAP_SIZE", 0) / (maxX - minX + 1);
                mapRows[i] = (maxY - points.get(i).y()) * data.value("MAP_SIZE", 1) / (maxY - minY + 1);
            }
        }
        Setting addDbscan(String name, int radius) {
            Setting setting =
                new Setting(name, 0, radius, Dbscan.cluster(grids.get(radius).neighborhoods, minimum));
            settings.add(setting);
            return setting;
        }
        List<Setting> dbscanSettings() {
            List<Setting> result = new ArrayList<>();
            for (Setting setting : settings)
                if (setting.kind == 0)
                    result.add(setting);
            return result;
        }
        List<String> labelLines() {
            List<String> lines = new ArrayList<>();
            String header = "id";
            for (Setting setting : settings)
                header += "," + setting.name;
            lines.add(header);
            for (int i = 0; i < n; i++) {
                String line = Integer.toString(points.get(i).id());
                for (Setting setting : settings)
                    line += "," + setting.labels[i];
                lines.add(line);
            }
            return lines;
        }
        List<String> opticsLines() {
            List<String> lines = new ArrayList<>(List.of("order,id,core_sq,reach_sq,reach,predecessor"));
            for (int position = 0; position < n; position++) {
                int i = optics.order.get(position);
                lines.add((position + 1) + "," + points.get(i).id() + "," + optional(optics.core[i]) + "," +
                          optional(optics.reach[i]) + "," + Report.root(optics.reach[i]) + "," +
                          (optics.predecessor[i] < 0
                               ? "-"
                               : Integer.toString(points.get(optics.predecessor[i]).id())));
            }
            return lines;
        }
        List<String> kdistLines() {
            List<String> lines =
                new ArrayList<>(List.of("k_distance k " + k + " points " + n, "rank id kdist_sq kdist"));
            for (int rank = 0; rank < n; rank++)
                lines.add((rank + 1) + " " + points.get(curve.order.get(rank)).id() + " " +
                          curve.values[rank] + " " + Report.root(curve.values[rank]));
            lines.add("");
            lines.add("knee rank " + (curve.knee + 1) + " id " +
                      points.get(curve.order.get(curve.knee)).id() + " kdist_sq " + curve.values[curve.knee] +
                      " kdist " + Report.root(curve.values[curve.knee]) + " cross " + curve.cross);
            lines.add("suggested_eps " + curve.eps);
            lines.add("");
            lines.add("knee_table");
            for (int j = 0; j < curves.size(); j++) {
                Curve row = curves.get(j);
                lines.add("k " + (j + 1) + " rank " + (row.knee + 1) + " id " +
                          points.get(row.order.get(row.knee)).id() + " kdist_sq " + row.values[row.knee] +
                          " eps " + row.eps);
            }
            lines.add("");
            lines.add("core_check");
            for (Setting setting : dbscanSettings()) {
                int core = 0, gridCore = 0;
                for (int i = 0; i < n; i++) {
                    if (kdist[i] <= setting.radius * setting.radius)
                        core++;
                    if (setting.core[i])
                        gridCore++;
                }
                lines.add("eps " + setting.radius + " core " + core + " non_core " + (n - core) +
                          " grid_core " + gridCore + " " + test(core == gridCore));
            }
            int core = 0;
            boolean consistent = true;
            for (int i = 0; i < n; i++)
                if (optics.core[i] != Optics.INF) {
                    core++;
                    if (optics.core[i] != kdist[i])
                        consistent = false;
                }
            lines.add("optics max_eps " + data.value("OPTICS_MAX_EPS") + " core " + core + " " +
                      test(consistent));
            return lines;
        }
        List<String> clusterLines(Setting setting, int label) {
            List<Point> members = new ArrayList<>();
            int core = 0;
            long sumX = 0, sumY = 0;
            int minX = Integer.MAX_VALUE, minY = Integer.MAX_VALUE, maxX = 0, maxY = 0;
            for (int i : setting.members.get(label)) {
                Point point = points.get(i);
                members.add(point);
                if (setting.core[i])
                    core++;
                sumX += point.x();
                sumY += point.y();
                minX = Math.min(minX, point.x());
                minY = Math.min(minY, point.y());
                maxX = Math.max(maxX, point.x());
                maxY = Math.max(maxY, point.y());
            }
            int size = members.size(), medoid = members.getFirst().id();
            long nearest = Long.MAX_VALUE;
            for (Point point : members) {
                long x = (long)size * point.x() - sumX, y = (long)size * point.y() - sumY,
                     metric = x * x + y * y;
                if (metric < nearest) {
                    nearest = metric;
                    medoid = point.id();
                }
            }
            int area = (maxX - minX + 1) * (maxY - minY + 1);
            List<Point> hull = hull(members);
            long doubled = 0;
            int diameter = 0;
            for (int i = 0; i < hull.size(); i++) {
                Point a = hull.get(i), b = hull.get((i + 1) % hull.size());
                doubled += (long)a.x() * b.y() - (long)b.x() * a.y();
                for (Point point : hull)
                    diameter = Math.max(diameter, GridIndex.distance(a, point));
            }
            doubled = Math.abs(doubled);
            return List.of("cluster " + label + " " + character(label) + " size " + size + " core " + core +
                               " border " + (size - core) + " centroid " + Report.fraction(sumX, size) + " " +
                               Report.fraction(sumY, size) + " medoid " + medoid,
                           "  bbox " + minX + " " + minY + " " + maxX + " " + maxY + " area " + area +
                               " density " + Report.fraction(size, area),
                           "  hull " + hull.size() + " hull_area " + doubled / 2 + "." +
                               (doubled % 2 == 0 ? 0 : 5) + " diameter_sq " + diameter + " diameter " +
                               Report.root(diameter));
        }
        List<String> checkLines(Setting setting) {
            boolean a = true, b = true, c = true;
            int isolated = 0;
            List<String> ambiguous = new ArrayList<>();
            int[][] neighborhoods = grids.get(setting.radius).neighborhoods;
            for (int i = 0; i < n; i++) {
                if (setting.core[i]) {
                    for (int other : neighborhoods[i])
                        if (setting.core[other] && setting.labels[other] != setting.labels[i])
                            a = false;
                } else if (setting.labels[i] >= 0) {
                    boolean supported = false;
                    Set<Integer> others = new TreeSet<>();
                    for (int other : neighborhoods[i])
                        if (setting.core[other]) {
                            if (setting.labels[other] == setting.labels[i])
                                supported = true;
                            else
                                others.add(setting.labels[other]);
                        }
                    if (!supported)
                        b = false;
                    if (!others.isEmpty())
                        ambiguous.add("  " + points.get(i).id() + " cluster " + setting.labels[i] + " also " +
                                      joined(others));
                } else {
                    if (neighborhoods[i].length == 1)
                        isolated++;
                    for (int other : neighborhoods[i])
                        if (setting.core[other])
                            c = false;
                }
            }
            List<String> lines =
                new ArrayList<>(List.of("check " + condition(a) + " " + condition(b) + " " + condition(c),
                                        "isolated " + isolated, "ambiguous " + ambiguous.size()));
            lines.addAll(ambiguous);
            return lines;
        }
        List<String> settingLines(Setting setting) {
            List<String> lines = new ArrayList<>(List.of(
                "setting " + setting.name + " eps " + setting.radius + " clusters " + setting.count +
                " noise " + setting.noise + " core " + setting.coreCount + " border " + setting.borderCount));
            for (int label = 0; label < setting.count; label++)
                lines.addAll(clusterLines(setting, label));
            if (setting.kind == 0)
                lines.addAll(checkLines(setting));
            return lines;
        }
        List<String> hierarchyLines() {
            List<String> lines = new ArrayList<>(List.of("hierarchy"));
            List<Setting> ordered = dbscanSettings();
            ordered.sort(Comparator.comparingInt(setting -> setting.radius));
            for (int i = 0; i + 1 < ordered.size(); i++) {
                Setting first = ordered.get(i), second = ordered.get(i + 1);
                lines.add(first.name + " -> " + second.name);
                List<List<Integer>> incoming = new ArrayList<>();
                for (int label = 0; label < second.count; label++)
                    incoming.add(new ArrayList<>());
                for (int label = 0; label < first.count; label++) {
                    int destination = -1;
                    for (int point : first.members.get(label))
                        if (first.core[point]) {
                            destination = second.labels[point];
                            break;
                        }
                    incoming.get(destination).add(label);
                }
                for (int label = 0; label < second.count; label++)
                    lines.add("  " + label + " <- " +
                              (incoming.get(label).isEmpty() ? "-" : joined(incoming.get(label))));
            }
            return lines;
        }
        List<String> comparisonLines() {
            List<String> lines = new ArrayList<>(List.of("optics_vs_dbscan"));
            for (Setting first : settings)
                if (first.kind == 1) {
                    Setting second = null;
                    for (Setting other : dbscanSettings())
                        if (other.radius == first.radius) {
                            second = other;
                            break;
                        }
                    if (second == null)
                        continue;
                    Map<Integer, Integer> mapping = new HashMap<>(), reverse = new HashMap<>();
                    boolean same = true;
                    int borderAsNoise = 0;
                    for (int i = 0; i < n; i++) {
                        if (first.core[i]) {
                            int a = first.labels[i], b = second.labels[i];
                            if (mapping.containsKey(a) && mapping.get(a) != b ||
                                reverse.containsKey(b) && reverse.get(b) != a)
                                same = false;
                            mapping.put(a, b);
                            reverse.put(b, a);
                        }
                        if (first.labels[i] < 0 && second.labels[i] >= 0)
                            borderAsNoise++;
                    }
                    if (mapping.size() != first.count || reverse.size() != second.count)
                        same = false;
                    int moved = 0;
                    if (same)
                        for (int i = 0; i < n; i++)
                            if (first.labels[i] >= 0 && mapping.get(first.labels[i]) != second.labels[i])
                                moved++;
                    lines.add(first.name + " " + second.name + " core_partition " +
                              (same ? "same" : "different") + " border_as_noise " + borderAsNoise +
                              " moved " + (same ? Integer.toString(moved) : "-"));
                }
            return lines;
        }
        List<String> opticsSummaryLines() {
            int core = 0, components = 0, singletons = 0, largest = 0, size = 0;
            for (int value : optics.core)
                if (value != Optics.INF)
                    core++;
            for (int point : optics.order) {
                if (optics.reach[point] == Optics.INF) {
                    if (size == 1)
                        singletons++;
                    largest = Math.max(largest, size);
                    components++;
                    size = 0;
                }
                size++;
            }
            if (size == 1)
                singletons++;
            largest = Math.max(largest, size);
            return List.of("optics max_eps " + data.value("OPTICS_MAX_EPS") + " core " + core +
                           " components " + components + " singletons " + singletons + " largest " + largest);
        }
        List<String> sweepLines() {
            List<String> lines = new ArrayList<>(
                List.of("sweep max_eps " + data.value("OPTICS_MAX_EPS"), "eps clusters noise largest"));
            int maximum = data.value("OPTICS_MAX_EPS");
            int[] counts = new int[maximum];
            for (int radius = 1; radius <= maximum; radius++) {
                Setting setting = new Setting("", 1, radius, extract(optics, radius));
                counts[radius - 1] = setting.count;
                int largest = 0;
                for (List<Integer> members : setting.members)
                    largest = Math.max(largest, members.size());
                lines.add(radius + " " + setting.count + " " + setting.noise + " " + largest);
            }
            int bestStart = -1, bestEnd = -1, start = 0;
            while (start < maximum) {
                int end = start;
                while (end + 1 < maximum && counts[end + 1] == counts[start])
                    end++;
                if (counts[start] >= 2 && (bestStart < 0 || end - start > bestEnd - bestStart)) {
                    bestStart = start;
                    bestEnd = end;
                }
                start = end + 1;
            }
            lines.add(bestStart < 0 ? "stable -"
                                    : "stable clusters " + counts[bestStart] + " eps " + (bestStart + 1) +
                                          " " + (bestEnd + 1) + " length " + (bestEnd - bestStart + 1));
            return lines;
        }
        List<String> xiLines() {
            List<String> lines =
                new ArrayList<>(List.of("xi " + data.settings.get("XI")[0] + " min_size " +
                                        data.value("XI_MIN_SIZE") + " steep_areas " + xi.areas.size()));
            for (Area area : xi.areas)
                lines.add(area.kind() + " " + (area.start() + 1) + " " + (area.end() + 1));
            lines.add("xi_clusters " + xi.clusters.size());
            for (int j = 0; j < xi.clusters.size(); j++) {
                Range range = xi.clusters.get(j);
                int valley = Optics.INF;
                for (int i = range.start() + 1; i <= range.end(); i++)
                    valley = Math.min(valley, positions[i]);
                lines.add(j + " start " + (range.start() + 1) + " end " + (range.end() + 1) + " size " +
                          range.size() + " label " + optional(xi.clusterLabels[j]) + " parent " +
                          optional(xi.parents[j]) + " walls " + Report.root(positions[range.start()]) + " " +
                          Report.root(positions[range.end() + 1]) + " valley " + Report.root(valley));
            }
            return lines;
        }
        List<String> outlierLines() {
            List<int[]> outliers = new ArrayList<>();
            for (int i = 0; i < n; i++)
                if (knee.labels[i] < 0) {
                    int nearest = -1, distance = Integer.MAX_VALUE;
                    for (int q = 0; q < n; q++)
                        if (knee.core[q]) {
                            int candidate = GridIndex.distance(points.get(i), points.get(q));
                            if (candidate < distance) {
                                distance = candidate;
                                nearest = q;
                            }
                        }
                    outliers.add(new int[] {i, nearest, distance});
                }
            outliers.sort(
                Comparator.<int[]>comparingInt(row -> row[2]).reversed().thenComparingInt(row -> row[0]));
            List<String> lines =
                new ArrayList<>(List.of("outliers " + knee.name + " count " + outliers.size()));
            for (int[] row : outliers)
                lines.add(points.get(row[0]).id() + " nearest_core " + points.get(row[1]).id() + " cluster " +
                          knee.labels[row[1]] + " dist_sq " + row[2] + " dist " + Report.root(row[2]));
            return lines;
        }
        List<String> gapLines() {
            List<String> lines = new ArrayList<>(List.of("gaps " + knee.name));
            for (int a = 0; a < knee.count; a++)
                for (int b = a + 1; b < knee.count; b++) {
                    int distance = Integer.MAX_VALUE, first = -1, second = -1;
                    for (int p : knee.members.get(a))
                        for (int q : knee.members.get(b)) {
                            int candidate = GridIndex.distance(points.get(p), points.get(q));
                            if (candidate < distance) {
                                distance = candidate;
                                first = p;
                                second = q;
                            }
                        }
                    lines.add(a + " " + b + " dist_sq " + distance + " dist " + Report.root(distance) +
                              " between " + points.get(first).id() + " " + points.get(second).id());
                }
            return lines;
        }
        List<String> contingencyLines() {
            int[][] table = new int[knee.count + 1][xiSetting.count + 1];
            for (int i = 0; i < n; i++)
                table[knee.labels[i] + 1][xiSetting.labels[i] + 1]++;
            List<Integer> columns = new ArrayList<>();
            for (int c = -1; c < xiSetting.count; c++)
                columns.add(c);
            List<String> lines =
                new ArrayList<>(List.of("contingency " + knee.name + " xi", "columns " + joined(columns)));
            for (int r = -1; r < knee.count; r++) {
                String line = Integer.toString(r);
                for (int value : table[r + 1])
                    line += " " + value;
                lines.add(line);
            }
            for (int c = 0; c < xiSetting.count; c++) {
                int best = 0;
                for (int r = 1; r < knee.count; r++)
                    if (table[r + 1][c + 1] > table[best + 1][c + 1])
                        best = r;
                int shared = table[best + 1][c + 1],
                    union = knee.members.get(best).size() + xiSetting.members.get(c).size() - shared;
                lines.add("match " + c + " " + best + " shared " + shared + " jaccard " +
                          Report.fraction(shared, union));
            }
            return lines;
        }
        List<String> ariLines() {
            List<String> lines = new ArrayList<>(List.of("ari"));
            for (int a = 0; a < settings.size(); a++)
                for (int b = a + 1; b < settings.size(); b++) {
                    long[] fraction = ari(settings.get(a).labels, settings.get(b).labels);
                    lines.add(settings.get(a).name + " " + settings.get(b).name + " " +
                              Report.ari(fraction[0], fraction[1]));
                }
            return lines;
        }
        List<String> clustersLines() {
            List<String> names = new ArrayList<>();
            for (Setting setting : settings)
                names.add(setting.name);
            List<List<String>> parts = new ArrayList<>();
            parts.add(List.of("points " + n + " min_pts " + minimum, "settings " + String.join(" ", names)));
            List<String> grid = new ArrayList<>(List.of("grid"));
            for (GridSummary summary : grids.values())
                grid.addAll(summary.lines());
            parts.add(grid);
            for (Setting setting : settings)
                parts.add(settingLines(setting));
            parts.add(hierarchyLines());
            parts.add(comparisonLines());
            parts.add(opticsSummaryLines());
            parts.add(sweepLines());
            parts.add(xiLines());
            parts.add(outlierLines());
            parts.add(gapLines());
            parts.add(contingencyLines());
            parts.add(ariLines());
            return join(parts);
        }
        List<String> clusterMap(Setting setting) {
            int width = data.value("MAP_SIZE", 0), height = data.value("MAP_SIZE", 1);
            boolean[][] occupied = new boolean[height][width];
            int[][] state = new int[height][width];
            for (int[] row : state)
                Arrays.fill(row, -2);
            for (int i = 0; i < n; i++) {
                int row = mapRows[i], column = mapColumns[i], label = setting.labels[i];
                occupied[row][column] = true;
                if (label >= 0) {
                    if (state[row][column] == -2)
                        state[row][column] = label;
                    else if (state[row][column] != label)
                        state[row][column] = -3;
                }
            }
            List<String> rows = new ArrayList<>();
            for (int r = 0; r < height; r++) {
                StringBuilder row = new StringBuilder();
                for (int c = 0; c < width; c++)
                    row.append(!occupied[r][c]     ? ' '
                               : state[r][c] == -2 ? '.'
                               : state[r][c] == -3 ? '*'
                                                   : character(state[r][c]));
                rows.add(row.toString());
            }
            return Report.framed(rows, width);
        }
        List<String> kindMap() {
            int width = data.value("MAP_SIZE", 0), height = data.value("MAP_SIZE", 1);
            int[][] state = new int[height][width];
            for (int[] row : state)
                Arrays.fill(row, -1);
            for (int i = 0; i < n; i++) {
                int kind = knee.labels[i] < 0 ? 0 : knee.core[i] ? 2 : 1;
                state[mapRows[i]][mapColumns[i]] = Math.max(state[mapRows[i]][mapColumns[i]], kind);
            }
            List<String> rows = new ArrayList<>();
            for (int[] cells : state) {
                StringBuilder row = new StringBuilder();
                for (int cell : cells)
                    row.append(cell < 0 ? ' ' : ".+#".charAt(cell));
                rows.add(row.toString());
            }
            return Report.framed(rows, width);
        }
        List<String> kdistPlot() {
            int width = data.value("KDIST_PLOT", 0), height = data.value("KDIST_PLOT", 1);
            int[] heights = new int[width];
            int kneeColumn = 0;
            for (int c = 0; c < width; c++) {
                int first = c * n / width, end = (c + 1) * n / width;
                while (heights[c] < height && (long)(heights[c] + 1) * (heights[c] + 1) * curve.values[0] <=
                                                  (long)height * height * curve.values[first])
                    heights[c]++;
                if (first <= curve.knee && curve.knee < end)
                    kneeColumn = c;
            }
            List<String> rows = new ArrayList<>();
            for (int t = 0; t < height; t++) {
                StringBuilder row = new StringBuilder();
                for (int c = 0; c < width; c++)
                    row.append(height - t <= heights[c] ? '#' : c == kneeColumn ? ':' : ' ');
                rows.add(row.toString());
            }
            List<String> lines =
                new ArrayList<>(List.of("kdist_plot k " + k + " max " + Report.root(curve.values[0]) +
                                        " knee_column " + (kneeColumn + 1)));
            lines.addAll(Report.framed(rows, width));
            return lines;
        }
        List<String> reachabilityLines() {
            int width = data.value("PLOT_WIDTH"), top = 0;
            List<Setting> columns = new ArrayList<>();
            List<String> names = new ArrayList<>();
            for (Setting setting : settings)
                if (setting.kind != 0) {
                    columns.add(setting);
                    names.add(setting.name);
                }
            for (int value : optics.reach)
                if (value != Optics.INF)
                    top = Math.max(top, value);
            List<String> lines =
                new ArrayList<>(List.of("reachability width " + width + " max_reach " + Report.root(top) +
                                        " columns " + String.join(" ", names)));
            for (int position = 0; position < n; position++) {
                int i = optics.order.get(position), value = optics.reach[i];
                StringBuilder labels = new StringBuilder();
                for (Setting setting : columns)
                    labels.append(character(setting.labels[i]));
                String bar;
                if (value == Optics.INF)
                    bar = "-".repeat(width);
                else {
                    int length = 0;
                    while (length < width &&
                           (long)(length + 1) * (length + 1) * top <= (long)width * width * value)
                        length++;
                    bar = "#".repeat(length);
                }
                lines.add(String.format(Locale.ROOT, "%4d %5d %7s %s |%s", position + 1, points.get(i).id(),
                                        Report.root(value), labels, bar));
            }
            return lines;
        }
        List<String> mapsLines() {
            List<List<String>> parts = new ArrayList<>();
            for (Setting setting : settings) {
                List<String> lines = new ArrayList<>(List.of("map " + setting.name + " clusters " +
                                                             setting.count + " noise " + setting.noise));
                lines.addAll(clusterMap(setting));
                String legend = "legend";
                for (int label = 0; label < setting.count; label++)
                    legend += " " + character(label) + "=" + setting.members.get(label).size();
                if (setting.count == 0)
                    legend += " -";
                lines.add(legend);
                parts.add(lines);
            }
            List<String> kinds = new ArrayList<>(List.of("kinds " + knee.name));
            kinds.addAll(kindMap());
            parts.add(kinds);
            parts.add(kdistPlot());
            parts.add(reachabilityLines());
            return join(parts);
        }
    }
    public static void main(String[] args) throws IOException {
        Analysis analysis = new Analysis(new Dataset());
        Files.createDirectories(Path.of("output"));
        Report.write("labels.csv", analysis.labelLines());
        Report.write("optics_order.csv", analysis.opticsLines());
        Report.write("kdist.txt", analysis.kdistLines());
        Report.write("clusters.txt", analysis.clustersLines());
        Report.write("maps.txt", analysis.mapsLines());
    }
}
