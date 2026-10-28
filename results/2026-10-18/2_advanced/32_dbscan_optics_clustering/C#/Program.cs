using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    static char Character(int label) {
        return label < 0    ? '.'
               : label < 26 ? (char)('A' + label)
               : label < 52 ? (char)('a' + label - 26)
                            : '#';
    }
    static string Optional(int value) {
        return value == Optics.INF || value < 0 ? "-" : Convert.ToString(value);
    }
    static string Joined(IEnumerable<int> values) {
        List<string> parts = new();
        foreach (int value in values)
            parts.Add(Convert.ToString(value));
        return string.Join(" ", parts);
    }
    static string Test(bool value) {
        return value ? "ok" : "mismatch";
    }
    static string Condition(bool value) {
        return value ? "ok" : "fail";
    }
    static List<string> Join(List<List<string>> parts) {
        List<string> lines = new();
        foreach (List<string> part in parts) {
            if (lines.Count != 0)
                lines.Add("");
            lines.AddRange(part);
        }
        return lines;
    }
    static int Radius(int value) {
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
    static long Pairs(long count) {
        return count * (count - 1) / 2;
    }
    sealed class Curve {
        public readonly List<int> order = new();
        public readonly int[] values;
        public readonly int knee, eps;
        public readonly long cross;
        public Curve(int[] distances) {
            int count = distances.Length;
            for (int i = 0; i < count; i++)
                order.Add(i);
            order.Sort(Comparer<int>.Create((a, b) => distances[a] != distances[b]
                                                          ? distances[b].CompareTo(distances[a])
                                                          : a.CompareTo(b)));
            values = new int[count];
            for (int i = 0; i < count; i++)
                values[i] = distances[order[i]];
            long maximum = -1;
            int knee = 0;
            for (int i = 0; i < count; i++) {
                long value = Math.Abs((count - 1L) * (values[i] - values[0]) -
                                      (long)(values[count - 1] - values[0]) * i);
                if (value > maximum) {
                    maximum = value;
                    knee = i;
                }
            }
            this.knee = knee;
            cross = maximum;
            eps = Radius(values[knee]);
        }
    }
    sealed class GridSummary {
        public readonly int eps, candidates, pairs, brutePairs;
        public readonly GridIndex grid;
        public readonly int[][] neighborhoods;
        public readonly bool consistent;
        public readonly SortedDictionary<int, int> occupancy = new();
        public GridSummary(List<Point> points, int eps) {
            this.eps = eps;
            grid = new GridIndex(points, eps);
            neighborhoods = new int [points.Count][];
            int candidates = 0, total = 0, bruteTotal = 0;
            bool consistent = true;
            int[] brute = grid.BruteCounts();
            for (int i = 0; i < points.Count; i++) {
                Neighborhood neighbors = grid.Neighborhood(i);
                neighborhoods[i] = neighbors.points;
                candidates += neighbors.candidates;
                total += neighborhoods[i].Length;
                bruteTotal += brute[i];
                if (neighborhoods[i].Length != brute[i])
                    consistent = false;
            }
            this.candidates = candidates;
            pairs = (total - points.Count) / 2;
            brutePairs = (bruteTotal - points.Count) / 2;
            this.consistent = consistent;
            foreach (List<int> cell in grid.cells.Values)
                occupancy[cell.Count] = occupancy.GetValueOrDefault(cell.Count) + 1;
        }
        public List<string> Lines() {
            Cell cell = grid.Busiest();
            List<string> sizes = new();
            foreach (KeyValuePair<int, int> entry in occupancy)
                sizes.Add(entry.Key + ":" + entry.Value);
            return [
                "eps " + eps + " cells " + grid.cells.Count + " busiest " + cell.x + " " + cell.y + " " +
                    grid.cells[cell].Count + " candidates " + candidates + " pairs " + pairs +
                    " brute_pairs " + brutePairs + " " + Test(consistent),
                "  occupancy " + string.Join(" ", sizes)
            ];
        }
    }
    sealed class Setting {
        public readonly string name;
        public readonly int kind, radius, count, noise, coreCount, borderCount;
        public readonly int[] labels;
        public readonly bool[] core;
        public readonly List<List<int>> members = new();
        public Setting(string name, int kind, int radius, Clustering clustering) {
            this.name = name;
            this.kind = kind;
            this.radius = radius;
            labels = clustering.labels;
            core = clustering.core;
            int maximum = -1, noise = 0, coreCount = 0;
            for (int i = 0; i < labels.Length; i++) {
                maximum = Math.Max(maximum, labels[i]);
                if (labels[i] < 0)
                    noise++;
                else if (core[i])
                    coreCount++;
            }
            count = maximum + 1;
            this.noise = noise;
            this.coreCount = coreCount;
            borderCount = labels.Length - noise - coreCount;
            for (int label = 0; label < count; label++)
                members.Add(new());
            for (int i = 0; i < labels.Length; i++)
                if (labels[i] >= 0)
                    members[labels[i]].Add(i);
        }
    }
    static Clustering Extract(Optics optics, int radius) {
        int[] labels = new int[optics.reach.Length];
        Array.Fill(labels, -1);
        bool[] core = new bool[labels.Length];
        int cluster = -1;
        for (int i = 0; i < core.Length; i++)
            core[i] = optics.core[i] <= radius * radius;
        foreach (int i in optics.order) {
            if (optics.reach[i] > radius * radius) {
                if (core[i])
                    labels[i] = ++cluster;
            } else
                labels[i] = cluster;
        }
        return new Clustering(labels, core);
    }
    sealed record Area(string kind, int start, int end);
    record Range(int start, int end) {
        public int Size() {
            return end - start + 1;
        }
    }
    sealed class DownArea {
        public readonly int start, end;
        public int high;
        public DownArea(int start, int end) {
            this.start = start;
            this.end = end;
        }
    }
    sealed class Xi {
        public readonly int[] reach, labels, clusterLabels, parents;
        public readonly bool[] steepUp, steepDown, up, down;
        public readonly int count, minimum, minimumSize;
        public readonly long alpha, beta;
        public readonly List<Area> areas = new();
        public readonly List<Range> clusters = new();
        public Xi(int[] reach, Dataset data) {
            this.reach = reach;
            count = reach.Length - 1;
            minimum = data.Value("MIN_PTS");
            minimumSize = data.Value("XI_MIN_SIZE");
            string[] fraction = data.settings["XI"][0].Split("/");
            int u = int.Parse(fraction[0]), v = int.Parse(fraction[1]);
            alpha = (long)(v - u) * (v - u);
            beta = (long)v * v;
            steepUp = new bool[count];
            steepDown = new bool[count];
            up = new bool[count];
            down = new bool[count];
            for (int i = 0; i < count; i++) {
                bool defined = reach[i] != Optics.INF || reach[i + 1] != Optics.INF;
                steepUp[i] = defined && Xle(reach[i], reach[i + 1]);
                steepDown[i] = defined && Xle(reach[i + 1], reach[i]);
                up[i] = reach[i] < reach[i + 1];
                down[i] = reach[i] > reach[i + 1];
            }
            Scan();
            labels = new int[count];
            Array.Fill(labels, -1);
            clusterLabels = new int[clusters.Count];
            parents = new int[clusters.Count];
            Array.Fill(clusterLabels, -1);
            Array.Fill(parents, -1);
            int next = 0;
            for (int i = 0; i < clusters.Count; i++) {
                Range range = clusters[i];
                bool free = true;
                for (int p = range.start; p <= range.end; p++)
                    if (labels[p] >= 0)
                        free = false;
                if (free) {
                    clusterLabels[i] = next;
                    for (int p = range.start; p <= range.end; p++)
                        labels[p] = next;
                    next++;
                }
            }
            for (int j = 0; j < clusters.Count; j++) {
                Range range = clusters[j];
                int size = int.MaxValue;
                for (int i = 0; i < clusters.Count; i++) {
                    Range other = clusters[i];
                    if (i == j || other.start > range.start || range.end > other.end ||
                        other.Size() < range.Size() || other.Size() == range.Size() && i < j)
                        continue;
                    if (other.Size() < size) {
                        parents[j] = i;
                        size = other.Size();
                    }
                }
            }
        }
        public bool Xle(int a, int b) {
            if (b == Optics.INF)
                return true;
            if (a == Optics.INF)
                return false;
            return beta * a <= alpha * b;
        }
        public int End(int start, bool[] steep, bool[] reverse) {
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
        public void Scan() {
            List<DownArea> downAreas = new();
            int index = 0, mib = 0;
            for (int start = 0; start < count; start++) {
                if (start < index || !steepUp[start] && !steepDown[start])
                    continue;
                for (int i = index; i <= start; i++)
                    mib = Math.Max(mib, reach[i]);
                if (mib == Optics.INF)
                    downAreas.Clear();
                else {
                    List<DownArea> retained = new();
                    foreach (DownArea area in downAreas)
                        if (Xle(mib, reach[area.start])) {
                            area.high = Math.Max(area.high, mib);
                            retained.Add(area);
                        }
                    downAreas = retained;
                }
                if (steepDown[start]) {
                    int end = End(start, steepDown, up);
                    areas.Add(new Area("down", start, end));
                    downAreas.Add(new DownArea(start, end));
                    index = end + 1;
                    mib = reach[index];
                } else {
                    int end = End(start, steepUp, down);
                    areas.Add(new Area("up", start, end));
                    index = end + 1;
                    mib = reach[index];
                    List<Range> candidates = new();
                    foreach (DownArea area in downAreas) {
                        int cs = area.start, ce = end;
                        if (!Xle(area.high, reach[ce + 1]))
                            continue;
                        int top = reach[area.start];
                        if (Xle(reach[ce + 1], top)) {
                            while (cs < area.end && reach[cs + 1] > reach[ce + 1])
                                cs++;
                        } else if (Xle(top, reach[ce + 1])) {
                            while (ce > start && reach[ce - 1] > top)
                                ce--;
                        }
                        if (ce - cs + 1 >= minimumSize && cs <= area.end && ce >= start)
                            candidates.Add(new Range(cs, ce));
                    }
                    candidates.Reverse();
                    clusters.AddRange(candidates);
                }
            }
        }
    }
    static long Turn(Point origin, Point a, Point b) {
        return (long)(a.x - origin.x) * (b.y - origin.y) - (long)(a.y - origin.y) * (b.x - origin.x);
    }
    static List<Point> HalfHull(List<Point> ordered) {
        List<Point> chain = new();
        foreach (Point point in ordered) {
            while (chain.Count >= 2 && Turn(chain[chain.Count - 2], chain[^1], point) <= 0)
                chain.RemoveAt(chain.Count - 1);
            chain.Add(point);
        }
        return chain;
    }
    static List<Point> Hull(List<Point> members) {
        List<Point> ordered = new(members);
        ordered.Sort(Comparer<Point>.Create((a, b) => a.x != b.x ? a.x.CompareTo(b.x) : a.y.CompareTo(b.y)));
        if (ordered.Count <= 2)
            return ordered;
        List<Point> lower = HalfHull(ordered);
        ordered.Reverse();
        List<Point> upper = HalfHull(ordered);
        lower.RemoveAt(lower.Count - 1);
        upper.RemoveAt(upper.Count - 1);
        lower.AddRange(upper);
        return lower;
    }
    static long[] Ari(int[] first, int[] second) {
        int n = first.Length;
        int[] rows = new int[n + 1], columns = new int[n + 1];
        Dictionary<long, int> cells = new();
        for (int i = 0; i < n; i++) {
            int a = first[i] + 1, b = second[i] + 1;
            rows[a]++;
            columns[b]++;
            cells[(long)a * (n + 1) + b] = cells.GetValueOrDefault((long)a * (n + 1) + b) + 1;
        }
        long same = 0, rowPairs = 0, columnPairs = 0;
        foreach (int count in cells.Values)
            same += Pairs(count);
        foreach (int count in rows)
            rowPairs += Pairs(count);
        foreach (int count in columns)
            columnPairs += Pairs(count);
        long total = Pairs(n), numerator = 2 * (total * same - rowPairs * columnPairs),
             denominator = total * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs;
        return denominator == 0 ? new long[] { 1, 1 } : new long[] { numerator, denominator };
    }
    sealed class Analysis {
        public readonly Dataset data;
        public readonly List<Point> points;
        public readonly int n, minimum, k;
        public readonly int[] kdist, mapColumns, mapRows;
        public readonly List<Curve> curves = new();
        public readonly Curve curve;
        public readonly SortedDictionary<int, GridSummary> grids = new();
        public readonly List<Setting> settings = new();
        public readonly Setting knee, xiSetting;
        public readonly Optics optics;
        public readonly int[] positions;
        public readonly Xi xi;
        public Analysis(Dataset data) {
            this.data = data;
            points = data.points;
            n = points.Count;
            minimum = data.Value("MIN_PTS");
            k = minimum - 1;
            int[][] nearest = new int [n][];
            for (int i = 0; i < n; i++) {
                int[] distances = new int[n - 1];
                int position = 0;
                for (int j = 0; j < n; j++)
                    if (j != i)
                        distances[position++] = GridIndex.Distance(points[i], points[j]);
                Array.Sort(distances);
                nearest[i] = distances[..(2 * minimum)];
            }
            for (int j = 0; j < 2 * minimum; j++) {
                int[] distances = new int[n];
                for (int i = 0; i < n; i++)
                    distances[i] = nearest[i][j];
                curves.Add(new Curve(distances));
            }
            curve = curves[k - 1];
            kdist = new int[n];
            for (int i = 0; i < n; i++)
                kdist[i] = nearest[i][k - 1];
            SortedSet<int> radii = new();
            foreach (int value in data.Values("EPS"))
                radii.Add(value);
            radii.Add(curve.eps);
            radii.Add(data.Value("OPTICS_MAX_EPS"));
            foreach (int radius in radii)
                grids[radius] = new GridSummary(points, radius);
            foreach (int radius in data.Values("EPS"))
                AddDbscan("db" + radius, radius);
            knee = AddDbscan("knee" + curve.eps, curve.eps);
            optics = new Optics(points, grids[data.Value("OPTICS_MAX_EPS")].neighborhoods, minimum);
            foreach (int radius in data.Values("EXTRACT_EPS"))
                settings.Add(new Setting("op" + radius, 1, radius, Extract(optics, radius)));
            positions = new int[n + 1];
            for (int i = 0; i < n; i++)
                positions[i] = optics.reach[optics.order[i]];
            positions[n] = Optics.INF;
            xi = new Xi(positions, data);
            int[] labels = new int[n];
            bool[] core = new bool[n];
            for (int i = 0; i < n; i++) {
                labels[optics.order[i]] = xi.labels[i];
                core[i] = optics.core[i] != Optics.INF;
            }
            xiSetting = new Setting("xi", 2, data.Value("OPTICS_MAX_EPS"), new Clustering(labels, core));
            settings.Add(xiSetting);
            int minX = int.MaxValue, minY = int.MaxValue, maxX = 0, maxY = 0;
            foreach (Point point in points) {
                minX = Math.Min(minX, point.x);
                maxX = Math.Max(maxX, point.x);
                minY = Math.Min(minY, point.y);
                maxY = Math.Max(maxY, point.y);
            }
            mapColumns = new int[n];
            mapRows = new int[n];
            for (int i = 0; i < n; i++) {
                mapColumns[i] = (points[i].x - minX) * data.Value("MAP_SIZE", 0) / (maxX - minX + 1);
                mapRows[i] = (maxY - points[i].y) * data.Value("MAP_SIZE", 1) / (maxY - minY + 1);
            }
        }
        public Setting AddDbscan(string name, int radius) {
            Setting setting =
                new Setting(name, 0, radius, Dbscan.Cluster(grids[radius].neighborhoods, minimum));
            settings.Add(setting);
            return setting;
        }
        public List<Setting> DbscanSettings() {
            List<Setting> result = new();
            foreach (Setting setting in settings)
                if (setting.kind == 0)
                    result.Add(setting);
            return result;
        }
        public List<string> LabelLines() {
            List<string> lines = new();
            string header = "id";
            foreach (Setting setting in settings)
                header += "," + setting.name;
            lines.Add(header);
            for (int i = 0; i < n; i++) {
                string line = Convert.ToString(points[i].id);
                foreach (Setting setting in settings)
                    line += "," + setting.labels[i];
                lines.Add(line);
            }
            return lines;
        }
        public List<string> OpticsLines() {
            List<string> lines = new(["order,id,core_sq,reach_sq,reach,predecessor"]);
            for (int position = 0; position < n; position++) {
                int i = optics.order[position];
                lines.Add(
                    (position + 1) + "," + points[i].id + "," + Optional(optics.core[i]) + "," +
                    Optional(optics.reach[i]) + "," + Report.Root(optics.reach[i]) + "," +
                    (optics.predecessor[i] < 0 ? "-" : Convert.ToString(points[optics.predecessor[i]].id)));
            }
            return lines;
        }
        public List<string> KdistLines() {
            List<string> lines = new(["k_distance k " + k + " points " + n, "rank id kdist_sq kdist"]);
            for (int rank = 0; rank < n; rank++)
                lines.Add((rank + 1) + " " + points[curve.order[rank]].id + " " + curve.values[rank] + " " +
                          Report.Root(curve.values[rank]));
            lines.Add("");
            lines.Add("knee rank " + (curve.knee + 1) + " id " + points[curve.order[curve.knee]].id +
                      " kdist_sq " + curve.values[curve.knee] + " kdist " +
                      Report.Root(curve.values[curve.knee]) + " cross " + curve.cross);
            lines.Add("suggested_eps " + curve.eps);
            lines.Add("");
            lines.Add("knee_table");
            for (int j = 0; j < curves.Count; j++) {
                Curve row = curves[j];
                lines.Add("k " + (j + 1) + " rank " + (row.knee + 1) + " id " +
                          points[row.order[row.knee]].id + " kdist_sq " + row.values[row.knee] + " eps " +
                          row.eps);
            }
            lines.Add("");
            lines.Add("core_check");
            foreach (Setting setting in DbscanSettings()) {
                int core = 0, gridCore = 0;
                for (int i = 0; i < n; i++) {
                    if (kdist[i] <= setting.radius * setting.radius)
                        core++;
                    if (setting.core[i])
                        gridCore++;
                }
                lines.Add("eps " + setting.radius + " core " + core + " non_core " + (n - core) +
                          " grid_core " + gridCore + " " + Test(core == gridCore));
            }
            int core = 0;
            bool consistent = true;
            for (int i = 0; i < n; i++)
                if (optics.core[i] != Optics.INF) {
                    core++;
                    if (optics.core[i] != kdist[i])
                        consistent = false;
                }
            lines.Add("optics max_eps " + data.Value("OPTICS_MAX_EPS") + " core " + core + " " +
                      Test(consistent));
            return lines;
        }
        public List<string> ClusterLines(Setting setting, int label) {
            List<Point> members = new();
            int core = 0;
            long sumX = 0, sumY = 0;
            int minX = int.MaxValue, minY = int.MaxValue, maxX = 0, maxY = 0;
            foreach (int i in setting.members[label]) {
                Point point = points[i];
                members.Add(point);
                if (setting.core[i])
                    core++;
                sumX += point.x;
                sumY += point.y;
                minX = Math.Min(minX, point.x);
                minY = Math.Min(minY, point.y);
                maxX = Math.Max(maxX, point.x);
                maxY = Math.Max(maxY, point.y);
            }
            int size = members.Count, medoid = members[0].id;
            long nearest = long.MaxValue;
            foreach (Point point in members) {
                long x = (long)size * point.x - sumX, y = (long)size * point.y - sumY, metric = x * x + y * y;
                if (metric < nearest) {
                    nearest = metric;
                    medoid = point.id;
                }
            }
            int area = (maxX - minX + 1) * (maxY - minY + 1);
            List<Point> hull = Hull(members);
            long doubled = 0;
            int diameter = 0;
            for (int i = 0; i < hull.Count; i++) {
                Point a = hull[i], b = hull[(i + 1) % hull.Count];
                doubled += (long)a.x * b.y - (long)b.x * a.y;
                foreach (Point point in hull)
                    diameter = Math.Max(diameter, GridIndex.Distance(a, point));
            }
            doubled = Math.Abs(doubled);
            return [
                "cluster " + label + " " + Character(label) + " size " + size + " core " + core + " border " +
                    (size - core) + " centroid " + Report.Fraction(sumX, size) + " " +
                    Report.Fraction(sumY, size) + " medoid " + medoid,
                "  bbox " + minX + " " + minY + " " + maxX + " " + maxY + " area " + area + " density " +
                    Report.Fraction(size, area),
                "  hull " + hull.Count + " hull_area " + doubled / 2 + "." + (doubled % 2 == 0 ? 0 : 5) +
                    " diameter_sq " + diameter + " diameter " + Report.Root(diameter)
            ];
        }
        public List<string> CheckLines(Setting setting) {
            bool a = true, b = true, c = true;
            int isolated = 0;
            List<string> ambiguous = new();
            int[][] neighborhoods = grids[setting.radius].neighborhoods;
            for (int i = 0; i < n; i++) {
                if (setting.core[i]) {
                    foreach (int other in neighborhoods[i])
                        if (setting.core[other] && setting.labels[other] != setting.labels[i])
                            a = false;
                } else if (setting.labels[i] >= 0) {
                    bool supported = false;
                    SortedSet<int> others = new();
                    foreach (int other in neighborhoods[i])
                        if (setting.core[other]) {
                            if (setting.labels[other] == setting.labels[i])
                                supported = true;
                            else
                                others.Add(setting.labels[other]);
                        }
                    if (!supported)
                        b = false;
                    if (others.Count != 0)
                        ambiguous.Add("  " + points[i].id + " cluster " + setting.labels[i] + " also " +
                                      Joined(others));
                } else {
                    if (neighborhoods[i].Length == 1)
                        isolated++;
                    foreach (int other in neighborhoods[i])
                        if (setting.core[other])
                            c = false;
                }
            }
            List<string> lines = new([
                "check " + Condition(a) + " " + Condition(b) + " " + Condition(c), "isolated " + isolated,
                "ambiguous " + ambiguous.Count
            ]);
            lines.AddRange(ambiguous);
            return lines;
        }
        public List<string> SettingLines(Setting setting) {
            List<string> lines = new(["setting " + setting.name + " eps " + setting.radius + " clusters " +
                                      setting.count + " noise " + setting.noise + " core " +
                                      setting.coreCount + " border " + setting.borderCount]);
            for (int label = 0; label < setting.count; label++)
                lines.AddRange(ClusterLines(setting, label));
            if (setting.kind == 0)
                lines.AddRange(CheckLines(setting));
            return lines;
        }
        public List<string> HierarchyLines() {
            List<string> lines = new(["hierarchy"]);
            List<Setting> ordered = DbscanSettings();
            ordered = ordered.OrderBy(setting => setting.radius).ToList();
            for (int i = 0; i + 1 < ordered.Count; i++) {
                Setting first = ordered[i], second = ordered[i + 1];
                lines.Add(first.name + " -> " + second.name);
                List<List<int>> incoming = new();
                for (int label = 0; label < second.count; label++)
                    incoming.Add(new());
                for (int label = 0; label < first.count; label++) {
                    int destination = -1;
                    foreach (int point in first.members[label])
                        if (first.core[point]) {
                            destination = second.labels[point];
                            break;
                        }
                    incoming[destination].Add(label);
                }
                for (int label = 0; label < second.count; label++)
                    lines.Add("  " + label + " <- " +
                              (incoming[label].Count == 0 ? "-" : Joined(incoming[label])));
            }
            return lines;
        }
        public List<string> ComparisonLines() {
            List<string> lines = new(["optics_vs_dbscan"]);
            foreach (Setting first in settings)
                if (first.kind == 1) {
                    Setting second = null;
                    foreach (Setting other in DbscanSettings())
                        if (other.radius == first.radius) {
                            second = other;
                            break;
                        }
                    if (second == null)
                        continue;
                    Dictionary<int, int> mapping = new(), reverse = new();
                    bool same = true;
                    int borderAsNoise = 0;
                    for (int i = 0; i < n; i++) {
                        if (first.core[i]) {
                            int a = first.labels[i], b = second.labels[i];
                            if (mapping.ContainsKey(a) && mapping[a] != b ||
                                reverse.ContainsKey(b) && reverse[b] != a)
                                same = false;
                            mapping[a] = b;
                            reverse[b] = a;
                        }
                        if (first.labels[i] < 0 && second.labels[i] >= 0)
                            borderAsNoise++;
                    }
                    if (mapping.Count != first.count || reverse.Count != second.count)
                        same = false;
                    int moved = 0;
                    if (same)
                        for (int i = 0; i < n; i++)
                            if (first.labels[i] >= 0 && mapping[first.labels[i]] != second.labels[i])
                                moved++;
                    lines.Add(first.name + " " + second.name + " core_partition " +
                              (same ? "same" : "different") + " border_as_noise " + borderAsNoise +
                              " moved " + (same ? Convert.ToString(moved) : "-"));
                }
            return lines;
        }
        public List<string> OpticsSummaryLines() {
            int core = 0, components = 0, singletons = 0, largest = 0, size = 0;
            foreach (int value in optics.core)
                if (value != Optics.INF)
                    core++;
            foreach (int point in optics.order) {
                if (optics.reach[point] == Optics.INF) {
                    if (size == 1)
                        singletons++;
                    largest = Math.Max(largest, size);
                    components++;
                    size = 0;
                }
                size++;
            }
            if (size == 1)
                singletons++;
            largest = Math.Max(largest, size);
            return ["optics max_eps " + data.Value("OPTICS_MAX_EPS") + " core " + core + " components " +
                    components + " singletons " + singletons + " largest " + largest];
        }
        public List<string> SweepLines() {
            List<string> lines =
                new(["sweep max_eps " + data.Value("OPTICS_MAX_EPS"), "eps clusters noise largest"]);
            int maximum = data.Value("OPTICS_MAX_EPS");
            int[] counts = new int[maximum];
            for (int radius = 1; radius <= maximum; radius++) {
                Setting setting = new Setting("", 1, radius, Extract(optics, radius));
                counts[radius - 1] = setting.count;
                int largest = 0;
                foreach (List<int> members in setting.members)
                    largest = Math.Max(largest, members.Count);
                lines.Add(radius + " " + setting.count + " " + setting.noise + " " + largest);
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
            lines.Add(bestStart < 0 ? "stable -"
                                    : "stable clusters " + counts[bestStart] + " eps " + (bestStart + 1) +
                                          " " + (bestEnd + 1) + " length " + (bestEnd - bestStart + 1));
            return lines;
        }
        public List<string> XiLines() {
            List<string> lines =
                new(["xi " +
                     data.settings ["XI"]
                     [0] +
                     " min_size " + data.Value("XI_MIN_SIZE") + " steep_areas " + xi.areas.Count]);
            foreach (Area area in xi.areas)
                lines.Add(area.kind + " " + (area.start + 1) + " " + (area.end + 1));
            lines.Add("xi_clusters " + xi.clusters.Count);
            for (int j = 0; j < xi.clusters.Count; j++) {
                Range range = xi.clusters[j];
                int valley = Optics.INF;
                for (int i = range.start + 1; i <= range.end; i++)
                    valley = Math.Min(valley, positions[i]);
                lines.Add(j + " start " + (range.start + 1) + " end " + (range.end + 1) + " size " +
                          range.Size() + " label " + Optional(xi.clusterLabels[j]) + " parent " +
                          Optional(xi.parents[j]) + " walls " + Report.Root(positions[range.start]) + " " +
                          Report.Root(positions[range.end + 1]) + " valley " + Report.Root(valley));
            }
            return lines;
        }
        public List<string> OutlierLines() {
            List<int[]> outliers = new();
            for (int i = 0; i < n; i++)
                if (knee.labels[i] < 0) {
                    int nearest = -1, distance = int.MaxValue;
                    for (int q = 0; q < n; q++)
                        if (knee.core[q]) {
                            int candidate = GridIndex.Distance(points[i], points[q]);
                            if (candidate < distance) {
                                distance = candidate;
                                nearest = q;
                            }
                        }
                    outliers.Add(new int[] { i, nearest, distance });
                }
            outliers.Sort(
                Comparer<int[]>.Create((a, b) => a[2] != b[2] ? b[2].CompareTo(a[2]) : a[0].CompareTo(b[0])));
            List<string> lines = new(["outliers " + knee.name + " count " + outliers.Count]);
            foreach (int[] row in outliers)
                lines.Add(points[row[0]].id + " nearest_core " + points[row[1]].id + " cluster " +
                          knee.labels[row[1]] + " dist_sq " + row[2] + " dist " + Report.Root(row[2]));
            return lines;
        }
        public List<string> GapLines() {
            List<string> lines = new(["gaps " + knee.name]);
            for (int a = 0; a < knee.count; a++)
                for (int b = a + 1; b < knee.count; b++) {
                    int distance = int.MaxValue, first = -1, second = -1;
                    foreach (int p in knee.members[a])
                        foreach (int q in knee.members[b]) {
                            int candidate = GridIndex.Distance(points[p], points[q]);
                            if (candidate < distance) {
                                distance = candidate;
                                first = p;
                                second = q;
                            }
                        }
                    lines.Add(a + " " + b + " dist_sq " + distance + " dist " + Report.Root(distance) +
                              " between " + points[first].id + " " + points[second].id);
                }
            return lines;
        }
        public List<string> ContingencyLines() {
            int[][] table = Enumerable.Range(0, knee.count + 1)
                                .Select(
                                    _ => new int[xiSetting.count + 1])
                                .ToArray();
            for (int i = 0; i < n; i++)
                table[knee.labels[i] + 1][xiSetting.labels[i] + 1]++;
            List<int> columns = new();
            for (int c = -1; c < xiSetting.count; c++)
                columns.Add(c);
            List<string> lines = new(["contingency " + knee.name + " xi", "columns " + Joined(columns)]);
            for (int r = -1; r < knee.count; r++) {
                string line = Convert.ToString(r);
                foreach (int value in table[r + 1])
                    line += " " + value;
                lines.Add(line);
            }
            for (int c = 0; c < xiSetting.count; c++) {
                int best = 0;
                for (int r = 1; r < knee.count; r++)
                    if (table[r + 1][c + 1] > table[best + 1][c + 1])
                        best = r;
                int shared = table[best + 1][c + 1], union
                = knee.members[best].Count + xiSetting.members[c].Count - shared;
                lines.Add("match " + c + " " + best + " shared " + shared + " jaccard " +
                          Report.Fraction(shared, union));
            }
            return lines;
        }
        public List<string> AriLines() {
            List<string> lines = new(["ari"]);
            for (int a = 0; a < settings.Count; a++)
                for (int b = a + 1; b < settings.Count; b++) {
                    long[] fraction = Ari(settings[a].labels, settings[b].labels);
                    lines.Add(settings[a].name + " " + settings[b].name + " " +
                              Report.Ari(fraction[0], fraction[1]));
                }
            return lines;
        }
        public List<string> ClustersLines() {
            List<string> names = new();
            foreach (Setting setting in settings)
                names.Add(setting.name);
            List<List<string>> parts = new();
            parts.Add(["points " + n + " min_pts " + minimum, "settings " + string.Join(" ", names)]);
            List<string> grid = new(["grid"]);
            foreach (GridSummary summary in grids.Values)
                grid.AddRange(summary.Lines());
            parts.Add(grid);
            foreach (Setting setting in settings)
                parts.Add(SettingLines(setting));
            parts.Add(HierarchyLines());
            parts.Add(ComparisonLines());
            parts.Add(OpticsSummaryLines());
            parts.Add(SweepLines());
            parts.Add(XiLines());
            parts.Add(OutlierLines());
            parts.Add(GapLines());
            parts.Add(ContingencyLines());
            parts.Add(AriLines());
            return Join(parts);
        }
        public List<string> ClusterMap(Setting setting) {
            int width = data.Value("MAP_SIZE", 0), height = data.Value("MAP_SIZE", 1);
            bool[][] occupied = Enumerable.Range(0, height)
                                    .Select(
                                        _ => new bool[width])
                                    .ToArray();
            int[][] state = Enumerable.Range(0, height)
                                .Select(
                                    _ => new int[width])
                                .ToArray();
            foreach (int[] row in state)
                Array.Fill(row, -2);
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
            List<string> rows = new();
            for (int r = 0; r < height; r++) {
                StringBuilder row = new StringBuilder();
                for (int c = 0; c < width; c++)
                    row.Append(!occupied[r][c]     ? ' '
                               : state[r][c] == -2 ? '.'
                               : state[r][c] == -3 ? '*'
                                                   : Character(state[r][c]));
                rows.Add(row.ToString());
            }
            return Report.Framed(rows, width);
        }
        public List<string> KindMap() {
            int width = data.Value("MAP_SIZE", 0), height = data.Value("MAP_SIZE", 1);
            int[][] state = Enumerable.Range(0, height)
                                .Select(
                                    _ => new int[width])
                                .ToArray();
            foreach (int[] row in state)
                Array.Fill(row, -1);
            for (int i = 0; i < n; i++) {
                int kind = knee.labels[i] < 0 ? 0 : knee.core[i] ? 2 : 1;
                state[mapRows[i]][mapColumns[i]] = Math.Max(state[mapRows[i]][mapColumns[i]], kind);
            }
            List<string> rows = new();
            foreach (int[] cells in state) {
                StringBuilder row = new StringBuilder();
                foreach (int cell in cells)
                    row.Append(cell < 0 ? ' ' : ".+#"[cell]);
                rows.Add(row.ToString());
            }
            return Report.Framed(rows, width);
        }
        public List<string> KdistPlot() {
            int width = data.Value("KDIST_PLOT", 0), height = data.Value("KDIST_PLOT", 1);
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
            List<string> rows = new();
            for (int t = 0; t < height; t++) {
                StringBuilder row = new StringBuilder();
                for (int c = 0; c < width; c++)
                    row.Append(height - t <= heights[c] ? '#' : c == kneeColumn ? ':' : ' ');
                rows.Add(row.ToString());
            }
            List<string> lines = new(["kdist_plot k " + k + " max " + Report.Root(curve.values[0]) +
                                      " knee_column " + (kneeColumn + 1)]);
            lines.AddRange(Report.Framed(rows, width));
            return lines;
        }
        public List<string> ReachabilityLines() {
            int width = data.Value("PLOT_WIDTH"), top = 0;
            List<Setting> columns = new();
            List<string> names = new();
            foreach (Setting setting in settings)
                if (setting.kind != 0) {
                    columns.Add(setting);
                    names.Add(setting.name);
                }
            foreach (int value in optics.reach)
                if (value != Optics.INF)
                    top = Math.Max(top, value);
            List<string> lines = new(["reachability width " + width + " max_reach " + Report.Root(top) +
                                      " columns " + string.Join(" ", names)]);
            for (int position = 0; position < n; position++) {
                int i = optics.order[position], value = optics.reach[i];
                StringBuilder labels = new StringBuilder();
                foreach (Setting setting in columns)
                    labels.Append(Character(setting.labels[i]));
                string bar;
                if (value == Optics.INF)
                    bar = new string('-', width);
                else {
                    int length = 0;
                    while (length < width &&
                           (long)(length + 1) * (length + 1) * top <= (long)width * width * value)
                        length++;
                    bar = new string('#', length);
                }
                lines.Add(string.Format(CultureInfo.InvariantCulture, "{0,4} {1,5} {2,7} {3} |{4}",
                                        position + 1, points[i].id, Report.Root(value), labels, bar));
            }
            return lines;
        }
        public List<string> MapsLines() {
            List<List<string>> parts = new();
            foreach (Setting setting in settings) {
                List<string> lines =
                    new(["map " + setting.name + " clusters " + setting.count + " noise " + setting.noise]);
                lines.AddRange(ClusterMap(setting));
                string legend = "legend";
                for (int label = 0; label < setting.count; label++)
                    legend += " " + Character(label) + "=" + setting.members[label].Count;
                if (setting.count == 0)
                    legend += " -";
                lines.Add(legend);
                parts.Add(lines);
            }
            List<string> kinds = new(["kinds " + knee.name]);
            kinds.AddRange(KindMap());
            parts.Add(kinds);
            parts.Add(KdistPlot());
            parts.Add(ReachabilityLines());
            return Join(parts);
        }
    }
    public static void Main(string[] args) {
        Analysis analysis = new Analysis(new Dataset());
        Directory.CreateDirectory(Path.Combine("output"));
        Report.Write("labels.csv", analysis.LabelLines());
        Report.Write("optics_order.csv", analysis.OpticsLines());
        Report.Write("kdist.txt", analysis.KdistLines());
        Report.Write("clusters.txt", analysis.ClustersLines());
        Report.Write("maps.txt", analysis.MapsLines());
    }
}
