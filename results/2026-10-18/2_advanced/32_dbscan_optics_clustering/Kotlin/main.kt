import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import kotlin.math.abs

private fun character(label: Int): Char = if (label < 0) '.' else if (label < 26) ('A'.code + label).toChar() else if (label < 52) ('a'.code + label - 26).toChar() else '#'
private fun optional(value: Int): String = if (value == Optics.INF || value < 0) "-" else value.toString()
private fun test(value: Boolean): String = if (value) "ok" else "mismatch"
private fun condition(value: Boolean): String = if (value) "ok" else "fail"
private fun join(parts: List<List<String>>): List<String> {
    val lines = mutableListOf<String>();
    for (part in parts) {
        if (lines.isNotEmpty()) lines.add("");
        lines.addAll(part)
    };
    return lines
}
private fun radius(value: Int): Int {
    var low = 1;
    var high = 46341;
    while (low < high) {
        val middle = (low + high) / 2;
        if (middle.toLong() * middle >= value) high = middle else low = middle + 1
    };
    return low
}
private fun pairs(count: Long): Long = count * (count - 1) / 2
private class Curve(distances: IntArray) {
    val order = distances.indices.sortedWith(compareByDescending<Int> {
        distances[it]
    }.thenBy {
        it
    })
    val values = IntArray(distances.size) {
        distances[order[it]]
    }
    val knee: Int;
    val eps: Int;
    val cross: Long
    init {
        val count = distances.size;
        var maximum = -1L;
        var knee = 0
        for (i in 0 until count) {
            val value = abs((count - 1L) * (values[i] - values[0]) - (values[count - 1] - values[0]).toLong() * i);
            if (value > maximum) {
                maximum = value;
                knee = i
            }
        }
        this.knee = knee;
        cross = maximum;
        eps = radius(values[knee])
    }
}
private class GridSummary(points: List<Point>, val eps: Int) {
    val grid = GridIndex(points, eps)
    val neighborhoods = Array(points.size) {
        IntArray(0)
    }
    val candidates: Int;
    val pairs: Int;
    val brutePairs: Int;
    val consistent: Boolean
    val occupancy = grid.cells.values.groupingBy {
        it.size
    }.eachCount().toSortedMap()
    init {
        var candidates = 0;
        var total = 0;
        var bruteTotal = 0;
        var consistent = true;
        val brute = grid.bruteCounts()
        for (i in points.indices) {
            val neighbors = grid.neighborhood(i);
            neighborhoods[i] = neighbors.points;
            candidates += neighbors.candidates;
            total += neighborhoods[i].size;
            bruteTotal += brute[i];
            if (neighborhoods[i].size != brute[i]) consistent = false
        }
        this.candidates = candidates;
        pairs = (total - points.size) / 2;
        brutePairs = (bruteTotal - points.size) / 2;
        this.consistent = consistent
    }
    fun lines(): List<String> {
        val cell = grid.busiest();
        return listOf("eps $eps cells ${grid.cells.size} busiest ${cell.x} ${cell.y} ${grid.cells.getValue(cell).size} candidates $candidates pairs $pairs brute_pairs $brutePairs ${test(consistent)}", "  occupancy " + occupancy.entries.joinToString(" ") {
            "${it.key}:${it.value}"
        })
    }
}
private class Setting(val name: String, val kind: Int, val radius: Int, clustering: Clustering) {
    val labels = clustering.labels;
    val core = clustering.core
    val count = labels.max() + 1
    val noise = labels.count {
        it < 0
    }
    val coreCount = labels.indices.count {
        labels[it] >= 0 && core[it]
    }
    val borderCount = labels.size - noise - coreCount
    val members = List(count) {
        mutableListOf<Int>()
    }
    init {
        for (i in labels.indices) if (labels[i] >= 0) members[labels[i]].add(i)
    }
}
private fun extract(optics: Optics, radius: Int): Clustering {
    val labels = IntArray(optics.reach.size) {
        -1
    };
    val core = BooleanArray(labels.size) {
        optics.core[it] <= radius * radius
    };
    var cluster = -1
    for (i in optics.order) if (optics.reach[i] > radius * radius) {
        if (core[i]) labels[i] = ++cluster
    } else labels[i] = cluster
    return Clustering(labels, core)
}
private data class Area(val kind: String, val start: Int, val end: Int)
private data class Range(val start: Int, val end: Int) {
    val size get() = end - start + 1
}
private class DownArea(val start: Int, val end: Int) {
    var high = 0
}
private class Xi(val reach: IntArray, data: Dataset) {
    val count = reach.size - 1;
    val minimum = data.value("MIN_PTS");
    val minimumSize = data.value("XI_MIN_SIZE")
    val alpha: Long;
    val beta: Long
    val steepUp = BooleanArray(count);
    val steepDown = BooleanArray(count);
    val up = BooleanArray(count);
    val down = BooleanArray(count)
    val areas = mutableListOf<Area>();
    val clusters = mutableListOf<Range>()
    val labels: IntArray;
    val clusterLabels: IntArray;
    val parents: IntArray
    init {
        val fraction = data.settings.getValue("XI")[0].split("/");
        val u = fraction[0].toInt();
        val v = fraction[1].toInt();
        alpha = (v - u).toLong() * (v - u);
        beta = v.toLong() * v
        for (i in 0 until count) {
            val defined = reach[i] != Optics.INF || reach[i + 1] != Optics.INF;
            steepUp[i] = defined && xle(reach[i], reach[i + 1]);
            steepDown[i] = defined && xle(reach[i + 1], reach[i]);
            up[i] = reach[i] < reach[i + 1];
            down[i] = reach[i] > reach[i + 1]
        }
        scan();
        labels = IntArray(count) {
            -1
        };
        clusterLabels = IntArray(clusters.size) {
            -1
        };
        parents = IntArray(clusters.size) {
            -1
        };
        var next = 0
        for ((i, range) in clusters.withIndex()) if ((range.start..range.end).all {
            labels[it] < 0
        }) {
            clusterLabels[i] = next;
            for (p in range.start..range.end) labels[p] = next;
            next++
        }
        for ((j, range) in clusters.withIndex()) {
            var size = Int.MAX_VALUE;
            for ((i, other) in clusters.withIndex()) {
                if (i == j || other.start > range.start || range.end > other.end || other.size < range.size || other.size == range.size && i < j) continue;
                if (other.size < size) {
                    parents[j] = i;
                    size = other.size
                }
            }
        }
    }
    fun xle(a: Int, b: Int): Boolean {
        if (b == Optics.INF) return true;
        if (a == Optics.INF) return false;
        return beta * a <= alpha * b
    }
    fun extend(start: Int, steep: BooleanArray, reverse: BooleanArray): Int {
        var end = start;
        var flat = 0;
        for (i in start until count) if (steep[i]) {
            end = i;
            flat = 0
        } else if (reverse[i]) break else if (++flat > minimum) break;
        return end
    }
    fun scan() {
        var downAreas = mutableListOf<DownArea>();
        var index = 0;
        var mib = 0
        for (start in 0 until count) {
            if (start < index || !steepUp[start] && !steepDown[start]) continue
            for (i in index..start) mib = maxOf(mib, reach[i])
            if (mib == Optics.INF) downAreas.clear() else {
                downAreas = downAreas.filter {
                    xle(mib, reach[it.start])
                }.toMutableList();
                for (area in downAreas) area.high = maxOf(area.high, mib)
            }
            if (steepDown[start]) {
                val end = extend(start, steepDown, up);
                areas.add(Area("down", start, end));
                downAreas.add(DownArea(start, end));
                index = end + 1;
                mib = reach[index]
            }
            else {
                val end = extend(start, steepUp, down);
                areas.add(Area("up", start, end));
                index = end + 1;
                mib = reach[index];
                val candidates = mutableListOf<Range>()
                for (area in downAreas) {
                    var cs = area.start;
                    var ce = end;
                    if (!xle(area.high, reach[ce + 1])) continue;
                    val top = reach[area.start];
                    if (xle(reach[ce + 1], top)) {
                        while (cs < area.end && reach[cs + 1] > reach[ce + 1]) cs++
                    } else if (xle(top, reach[ce + 1])) {
                        while (ce > start && reach[ce - 1] > top) ce--
                    };
                    if (ce - cs + 1 >= minimumSize && cs <= area.end && ce >= start) candidates.add(Range(cs, ce))
                }
                clusters.addAll(candidates.asReversed())
            }
        }
    }
}
private fun turn(origin: Point, a: Point, b: Point): Long = (a.x - origin.x).toLong() * (b.y - origin.y) - (a.y - origin.y).toLong() * (b.x - origin.x)
private fun halfHull(ordered: List<Point>): MutableList<Point> {
    val chain = mutableListOf<Point>();
    for (point in ordered) {
        while (chain.size >= 2 && turn(chain[chain.size - 2], chain.last(), point) <= 0) chain.removeAt(chain.lastIndex);
        chain.add(point)
    };
    return chain
}
private fun hull(members: List<Point>): List<Point> {
    val ordered = members.sortedWith(compareBy<Point> {
        it.x
    }.thenBy {
        it.y
    });
    if (ordered.size <= 2) return ordered;
    val lower = halfHull(ordered);
    val upper = halfHull(ordered.asReversed());
    lower.removeAt(lower.lastIndex);
    upper.removeAt(upper.lastIndex);
    return lower + upper
}
private fun ari(first: IntArray, second: IntArray): LongArray {
    val n = first.size;
    val rows = IntArray(n + 1);
    val columns = IntArray(n + 1);
    val cells = mutableMapOf<Long, Int>()
    for (i in 0 until n) {
        val a = first[i] + 1;
        val b = second[i] + 1;
        rows[a]++;
        columns[b]++;
        val key = a.toLong() * (n + 1) + b;
        cells[key] = cells.getOrDefault(key, 0) + 1
    }
    var same = 0L;
    var rowPairs = 0L;
    var columnPairs = 0L
    for (count in cells.values) same += pairs(count.toLong());
    for (count in rows) rowPairs += pairs(count.toLong());
    for (count in columns) columnPairs += pairs(count.toLong())
    val total = pairs(n.toLong());
    val numerator = 2 * (total * same - rowPairs * columnPairs);
    val denominator = total * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs
    return if (denominator == 0L) longArrayOf(1, 1) else longArrayOf(numerator, denominator)
}
private class Analysis(val data: Dataset) {
    val points = data.points;
    val n = points.size;
    val minimum = data.value("MIN_PTS");
    val k = minimum - 1
    val kdist = IntArray(n);
    val mapColumns = IntArray(n);
    val mapRows = IntArray(n)
    val curves = mutableListOf<Curve>();
    val curve: Curve;
    val grids = sortedMapOf<Int, GridSummary>();
    val settings = mutableListOf<Setting>()
    val knee: Setting;
    val xiSetting: Setting;
    val optics: Optics;
    val positions: IntArray;
    val xi: Xi
    init {
        val nearest = Array(n) {
            IntArray(0)
        }
        for (i in 0 until n) {
            val distances = IntArray(n - 1);
            var position = 0;
            for (j in 0 until n) if (j != i) distances[position++] = GridIndex.distance(points[i], points[j]);
            distances.sort();
            nearest[i] = distances.copyOf(2 * minimum)
        }
        for (j in 0 until 2 * minimum) curves.add(Curve(IntArray(n) {
            nearest[it][j]
        }))
        curve = curves[k - 1];
        for (i in 0 until n) kdist[i] = nearest[i][k - 1]
        val radii = (data.values("EPS").toList() + curve.eps + data.value("OPTICS_MAX_EPS")).toSortedSet()
        for (radius in radii) grids[radius] = GridSummary(points, radius)
        for (radius in data.values("EPS")) addDbscan("db$radius", radius)
        knee = addDbscan("knee${curve.eps}", curve.eps);
        optics = Optics(points, grids.getValue(data.value("OPTICS_MAX_EPS")).neighborhoods, minimum)
        for (radius in data.values("EXTRACT_EPS")) settings.add(Setting("op$radius", 1, radius, extract(optics, radius)))
        positions = IntArray(n + 1) {
            if (it == n) Optics.INF else optics.reach[optics.order[it]]
        };
        xi = Xi(positions, data)
        val labels = IntArray(n);
        val core = BooleanArray(n) {
            optics.core[it] != Optics.INF
        };
        for (i in 0 until n) labels[optics.order[i]] = xi.labels[i]
        xiSetting = Setting("xi", 2, data.value("OPTICS_MAX_EPS"), Clustering(labels, core));
        settings.add(xiSetting)
        val minX = points.minOf {
            it.x
        };
        val minY = points.minOf {
            it.y
        };
        val maxX = points.maxOf {
            it.x
        };
        val maxY = points.maxOf {
            it.y
        }
        for (i in 0 until n) {
            mapColumns[i] = (points[i].x - minX) * data.value("MAP_SIZE", 0) / (maxX - minX + 1);
            mapRows[i] = (maxY - points[i].y) * data.value("MAP_SIZE", 1) / (maxY - minY + 1)
        }
    }
    fun addDbscan(name: String, radius: Int): Setting {
        val setting = Setting(name, 0, radius, Dbscan.cluster(grids.getValue(radius).neighborhoods, minimum));
        settings.add(setting);
        return setting
    }
    fun dbscanSettings(): List<Setting> = settings.filter {
        it.kind == 0
    }
    fun labelLines(): List<String> {
        val lines = mutableListOf("id," + settings.joinToString(",") {
            it.name
        })
        for (i in 0 until n) lines.add(points[i].id.toString() + "," + settings.joinToString(",") {
            it.labels[i].toString()
        })
        return lines
    }
    fun opticsLines(): List<String> {
        val lines = mutableListOf("order,id,core_sq,reach_sq,reach,predecessor")
        for ((position, i) in optics.order.withIndex()) lines.add("${position + 1},${points[i].id},${optional(optics.core[i])},${optional(optics.reach[i])},${Report.root(optics.reach[i])},${if (optics.predecessor[i] < 0) "-" else points[optics.predecessor[i]].id.toString()}")
        return lines
    }
    fun kdistLines(): List<String> {
        val lines = mutableListOf("k_distance k $k points $n", "rank id kdist_sq kdist")
        for (rank in 0 until n) lines.add("${rank + 1} ${points[curve.order[rank]].id} ${curve.values[rank]} ${Report.root(curve.values[rank])}")
        lines.add("");
        lines.add("knee rank ${curve.knee + 1} id ${points[curve.order[curve.knee]].id} kdist_sq ${curve.values[curve.knee]} kdist ${Report.root(curve.values[curve.knee])} cross ${curve.cross}");
        lines.add("suggested_eps ${curve.eps}");
        lines.add("");
        lines.add("knee_table")
        for ((j, row) in curves.withIndex()) lines.add("k ${j + 1} rank ${row.knee + 1} id ${points[row.order[row.knee]].id} kdist_sq ${row.values[row.knee]} eps ${row.eps}")
        lines.add("");
        lines.add("core_check")
        for (setting in dbscanSettings()) {
            val core = kdist.count {
                it <= setting.radius * setting.radius
            };
            val gridCore = setting.core.count {
                it
            };
            lines.add("eps ${setting.radius} core $core non_core ${n - core} grid_core $gridCore ${test(core == gridCore)}")
        }
        val core = optics.core.count {
            it != Optics.INF
        };
        val consistent = (0 until n).all {
            optics.core[it] == Optics.INF || optics.core[it] == kdist[it]
        }
        lines.add("optics max_eps ${data.value("OPTICS_MAX_EPS")} core $core ${test(consistent)}")
        return lines
    }
    fun clusterLines(setting: Setting, label: Int): List<String> {
        val members = setting.members[label].map {
            points[it]
        };
        val core = setting.members[label].count {
            setting.core[it]
        };
        var sumX = 0L;
        var sumY = 0L
        for (point in members) {
            sumX += point.x;
            sumY += point.y
        }
        val minX = members.minOf {
            it.x
        };
        val minY = members.minOf {
            it.y
        };
        val maxX = members.maxOf {
            it.x
        };
        val maxY = members.maxOf {
            it.y
        };
        val size = members.size
        var medoid = members.first().id;
        var nearest = Long.MAX_VALUE
        for (point in members) {
            val x = size.toLong() * point.x - sumX;
            val y = size.toLong() * point.y - sumY;
            val metric = x * x + y * y;
            if (metric < nearest) {
                nearest = metric;
                medoid = point.id
            }
        }
        val area = (maxX - minX + 1) * (maxY - minY + 1);
        val hull = hull(members);
        var doubled = 0L;
        var diameter = 0
        for (i in hull.indices) {
            val a = hull[i];
            val b = hull[(i + 1) % hull.size];
            doubled += a.x.toLong() * b.y - b.x.toLong() * a.y;
            for (point in hull) diameter = maxOf(diameter, GridIndex.distance(a, point))
        }
        doubled = abs(doubled)
        return listOf("cluster $label ${character(label)} size $size core $core border ${size - core} centroid ${Report.fraction(sumX, size.toLong())} ${Report.fraction(sumY, size.toLong())} medoid $medoid", "  bbox $minX $minY $maxX $maxY area $area density ${Report.fraction(size, area)}", "  hull ${hull.size} hull_area ${doubled / 2}.${if (doubled % 2 == 0L) 0 else 5} diameter_sq $diameter diameter ${Report.root(diameter)}")
    }
    fun checkLines(setting: Setting): List<String> {
        var a = true;
        var b = true;
        var c = true;
        var isolated = 0;
        val ambiguous = mutableListOf<String>();
        val neighborhoods = grids.getValue(setting.radius).neighborhoods
        for (i in 0 until n) {
            if (setting.core[i]) {
                for (other in neighborhoods[i]) if (setting.core[other] && setting.labels[other] != setting.labels[i]) a = false
            }
            else if (setting.labels[i] >= 0) {
                var supported = false;
                val others = sortedSetOf<Int>();
                for (other in neighborhoods[i]) if (setting.core[other]) {
                    if (setting.labels[other] == setting.labels[i]) supported = true else others.add(setting.labels[other])
                };
                if (!supported) b = false;
                if (others.isNotEmpty()) ambiguous.add("  ${points[i].id} cluster ${setting.labels[i]} also ${others.joinToString(" ")}")
            }
            else {
                if (neighborhoods[i].size == 1) isolated++;
                for (other in neighborhoods[i]) if (setting.core[other]) c = false
            }
        }
        return listOf("check ${condition(a)} ${condition(b)} ${condition(c)}", "isolated $isolated", "ambiguous ${ambiguous.size}") + ambiguous
    }
    fun settingLines(setting: Setting): List<String> {
        val lines = mutableListOf("setting ${setting.name} eps ${setting.radius} clusters ${setting.count} noise ${setting.noise} core ${setting.coreCount} border ${setting.borderCount}")
        for (label in 0 until setting.count) lines.addAll(clusterLines(setting, label))
        if (setting.kind == 0) lines.addAll(checkLines(setting))
        return lines
    }
    fun hierarchyLines(): List<String> {
        val lines = mutableListOf("hierarchy");
        val ordered = dbscanSettings().sortedBy {
            it.radius
        }
        for (i in 0 until ordered.size - 1) {
            val first = ordered[i];
            val second = ordered[i + 1];
            lines.add("${first.name} -> ${second.name}");
            val incoming = List(second.count) {
                mutableListOf<Int>()
            };
            for (label in 0 until first.count) {
                val point = first.members[label].first {
                    first.core[it]
                };
                incoming[second.labels[point]].add(label)
            };
            for (label in 0 until second.count) lines.add("  $label <- ${if (incoming[label].isEmpty()) "-" else incoming[label].joinToString(" ")}")
        }
        return lines
    }
    fun comparisonLines(): List<String> {
        val lines = mutableListOf("optics_vs_dbscan")
        for (first in settings.filter {
            it.kind == 1
        }) {
            val second = dbscanSettings().firstOrNull {
                it.radius == first.radius
            }
            ?: continue;
            val mapping = mutableMapOf<Int, Int>();
            val reverse = mutableMapOf<Int, Int>();
            var same = true;
            var borderAsNoise = 0
            for (i in 0 until n) {
                if (first.core[i]) {
                    val a = first.labels[i];
                    val b = second.labels[i];
                    if (mapping.containsKey(a) && mapping[a] != b || reverse.containsKey(b) && reverse[b] != a) same = false;
                    mapping[a] = b;
                    reverse[b] = a
                };
                if (first.labels[i] < 0 && second.labels[i] >= 0) borderAsNoise++
            }
            if (mapping.size != first.count || reverse.size != second.count) same = false
            val moved = if (same) (0 until n).count {
                first.labels[it] >= 0 && mapping.getValue(first.labels[it]) != second.labels[it]
            } else 0
            lines.add("${first.name} ${second.name} core_partition ${if (same) "same" else "different"} border_as_noise $borderAsNoise moved ${if (same) moved.toString() else "-"}")
        }
        return lines
    }
    fun opticsSummaryLines(): List<String> {
        val core = optics.core.count {
            it != Optics.INF
        };
        var components = 0;
        var singletons = 0;
        var largest = 0;
        var size = 0
        for (point in optics.order) {
            if (optics.reach[point] == Optics.INF) {
                if (size == 1) singletons++;
                largest = maxOf(largest, size);
                components++;
                size = 0
            };
            size++
        }
        if (size == 1) singletons++;
        largest = maxOf(largest, size)
        return listOf("optics max_eps ${data.value("OPTICS_MAX_EPS")} core $core components $components singletons $singletons largest $largest")
    }
    fun sweepLines(): List<String> {
        val maximum = data.value("OPTICS_MAX_EPS");
        val lines = mutableListOf("sweep max_eps $maximum", "eps clusters noise largest");
        val counts = IntArray(maximum)
        for (radius in 1..maximum) {
            val setting = Setting("", 1, radius, extract(optics, radius));
            counts[radius - 1] = setting.count;
            val largest = setting.members.maxOfOrNull {
                it.size
            }
            ?: 0;
            lines.add("$radius ${setting.count} ${setting.noise} $largest")
        }
        var bestStart = -1;
        var bestEnd = -1;
        var start = 0
        while (start < maximum) {
            var end = start;
            while (end + 1 < maximum && counts[end + 1] == counts[start]) end++;
            if (counts[start] >= 2 && (bestStart < 0 || end - start > bestEnd - bestStart)) {
                bestStart = start;
                bestEnd = end
            };
            start = end + 1
        }
        lines.add(if (bestStart < 0) "stable -" else "stable clusters ${counts[bestStart]} eps ${bestStart + 1} ${bestEnd + 1} length ${bestEnd - bestStart + 1}")
        return lines
    }
    fun xiLines(): List<String> {
        val lines = mutableListOf("xi ${data.settings.getValue("XI")[0]} min_size ${data.value("XI_MIN_SIZE")} steep_areas ${xi.areas.size}")
        for (area in xi.areas) lines.add("${area.kind} ${area.start + 1} ${area.end + 1}")
        lines.add("xi_clusters ${xi.clusters.size}")
        for ((j, range) in xi.clusters.withIndex()) {
            var valley = Optics.INF;
            for (i in range.start + 1..range.end) valley = minOf(valley, positions[i]);
            lines.add("$j start ${range.start + 1} end ${range.end + 1} size ${range.size} label ${optional(xi.clusterLabels[j])} parent ${optional(xi.parents[j])} walls ${Report.root(positions[range.start])} ${Report.root(positions[range.end + 1])} valley ${Report.root(valley)}")
        }
        return lines
    }
    fun outlierLines(): List<String> {
        val outliers = mutableListOf<IntArray>()
        for (i in 0 until n) if (knee.labels[i] < 0) {
            var nearest = -1;
            var distance = Int.MAX_VALUE;
            for (q in 0 until n) if (knee.core[q]) {
                val candidate = GridIndex.distance(points[i], points[q]);
                if (candidate < distance) {
                    distance = candidate;
                    nearest = q
                }
            };
            outliers.add(intArrayOf(i, nearest, distance))
        }
        outliers.sortWith(compareByDescending<IntArray> {
            it[2]
        }.thenBy {
            it[0]
        });
        val lines = mutableListOf("outliers ${knee.name} count ${outliers.size}")
        for (row in outliers) lines.add("${points[row[0]].id} nearest_core ${points[row[1]].id} cluster ${knee.labels[row[1]]} dist_sq ${row[2]} dist ${Report.root(row[2])}")
        return lines
    }
    fun gapLines(): List<String> {
        val lines = mutableListOf("gaps ${knee.name}")
        for (a in 0 until knee.count) for (b in a + 1 until knee.count) {
            var distance = Int.MAX_VALUE;
            var first = -1;
            var second = -1;
            for (p in knee.members[a]) for (q in knee.members[b]) {
                val candidate = GridIndex.distance(points[p], points[q]);
                if (candidate < distance) {
                    distance = candidate;
                    first = p;
                    second = q
                }
            };
            lines.add("$a $b dist_sq $distance dist ${Report.root(distance)} between ${points[first].id} ${points[second].id}")
        }
        return lines
    }
    fun contingencyLines(): List<String> {
        val table = Array(knee.count + 1) {
            IntArray(xiSetting.count + 1)
        };
        for (i in 0 until n) table[knee.labels[i] + 1][xiSetting.labels[i] + 1]++
        val lines = mutableListOf("contingency ${knee.name} xi", "columns " + (-1 until xiSetting.count).joinToString(" "))
        for (r in -1 until knee.count) lines.add("$r ${table[r + 1].joinToString(" ")}")
        for (c in 0 until xiSetting.count) {
            var best = 0;
            for (r in 1 until knee.count) if (table[r + 1][c + 1] > table[best + 1][c + 1]) best = r;
            val shared = table[best + 1][c + 1];
            val union = knee.members[best].size + xiSetting.members[c].size - shared;
            lines.add("match $c $best shared $shared jaccard ${Report.fraction(shared, union)}")
        }
        return lines
    }
    fun ariLines(): List<String> {
        val lines = mutableListOf("ari")
        for (a in settings.indices) for (b in a + 1 until settings.size) {
            val fraction = ari(settings[a].labels, settings[b].labels);
            lines.add("${settings[a].name} ${settings[b].name} ${Report.ari(fraction[0], fraction[1])}")
        }
        return lines
    }
    fun clustersLines(): List<String> {
        val parts = mutableListOf<List<String>>(listOf("points $n min_pts $minimum", "settings " + settings.joinToString(" ") {
            it.name
        }));
        val grid = mutableListOf("grid")
        for (summary in grids.values) grid.addAll(summary.lines())
        parts.add(grid);
        for (setting in settings) parts.add(settingLines(setting));
        parts.add(hierarchyLines());
        parts.add(comparisonLines());
        parts.add(opticsSummaryLines());
        parts.add(sweepLines());
        parts.add(xiLines());
        parts.add(outlierLines());
        parts.add(gapLines());
        parts.add(contingencyLines());
        parts.add(ariLines())
        return join(parts)
    }
    fun clusterMap(setting: Setting): List<String> {
        val width = data.value("MAP_SIZE", 0);
        val height = data.value("MAP_SIZE", 1);
        val occupied = Array(height) {
            BooleanArray(width)
        };
        val state = Array(height) {
            IntArray(width) {
                -2
            }
        }
        for (i in 0 until n) {
            val row = mapRows[i];
            val column = mapColumns[i];
            val label = setting.labels[i];
            occupied[row][column] = true;
            if (label >= 0) {
                if (state[row][column] == -2) state[row][column] = label else if (state[row][column] != label) state[row][column] = -3
            }
        }
        val rows = (0 until height).map {
            r -> CharArray(width) {
                c -> if (!occupied[r][c]) ' ' else if (state[r][c] == -2) '.' else if (state[r][c] == -3) '*' else character(state[r][c])
            }.concatToString()
        }
        return Report.framed(rows, width)
    }
    fun kindMap(): List<String> {
        val width = data.value("MAP_SIZE", 0);
        val height = data.value("MAP_SIZE", 1);
        val state = Array(height) {
            IntArray(width) {
                -1
            }
        }
        for (i in 0 until n) {
            val kind = if (knee.labels[i] < 0) 0 else if (knee.core[i]) 2 else 1;
            state[mapRows[i]][mapColumns[i]] = maxOf(state[mapRows[i]][mapColumns[i]], kind)
        }
        val rows = state.map {
            cells -> CharArray(width) {
                if (cells[it] < 0) ' ' else ".+#"[cells[it]]
            }.concatToString()
        }
        return Report.framed(rows, width)
    }
    fun kdistPlot(): List<String> {
        val width = data.value("KDIST_PLOT", 0);
        val height = data.value("KDIST_PLOT", 1);
        val heights = IntArray(width);
        var kneeColumn = 0
        for (c in 0 until width) {
            val first = c * n / width;
            val end = (c + 1) * n / width;
            while (heights[c] < height && (heights[c] + 1).toLong() * (heights[c] + 1) * curve.values[0] <= height.toLong() * height * curve.values[first]) heights[c]++;
            if (first <= curve.knee && curve.knee < end) kneeColumn = c
        }
        val rows = (0 until height).map {
            t -> CharArray(width) {
                c -> if (height - t <= heights[c]) '#' else if (c == kneeColumn) ':' else ' '
            }.concatToString()
        }
        return listOf("kdist_plot k $k max ${Report.root(curve.values[0])} knee_column ${kneeColumn + 1}") + Report.framed(rows, width)
    }
    fun reachabilityLines(): List<String> {
        val width = data.value("PLOT_WIDTH");
        val top = optics.reach.filter {
            it != Optics.INF
        }.max();
        val columns = settings.filter {
            it.kind != 0
        }
        val lines = mutableListOf("reachability width $width max_reach ${Report.root(top)} columns " + columns.joinToString(" ") {
            it.name
        })
        for ((position, i) in optics.order.withIndex()) {
            val value = optics.reach[i];
            val labels = columns.joinToString("") {
                character(it.labels[i]).toString()
            }
            val bar = if (value == Optics.INF) "-".repeat(width) else {
                var length = 0;
                while (length < width && (length + 1).toLong() * (length + 1) * top <= width.toLong() * width * value) length++;
                "#".repeat(length)
            }
            lines.add(String.format(Locale.ROOT, "%4d %5d %7s %s |%s", position + 1, points[i].id, Report.root(value), labels, bar))
        }
        return lines
    }
    fun mapsLines(): List<String> {
        val parts = mutableListOf<List<String>>()
        for (setting in settings) {
            val lines = mutableListOf("map ${setting.name} clusters ${setting.count} noise ${setting.noise}");
            lines.addAll(clusterMap(setting));
            lines.add(if (setting.count == 0) "legend -" else "legend " + (0 until setting.count).joinToString(" ") {
                "${character(it)}=${setting.members[it].size}"
            });
            parts.add(lines)
        }
        parts.add(listOf("kinds ${knee.name}") + kindMap());
        parts.add(kdistPlot());
        parts.add(reachabilityLines())
        return join(parts)
    }
}
fun main() {
    val analysis = Analysis(Dataset());
    Files.createDirectories(Path.of("output"))
    Report.write("labels.csv", analysis.labelLines());
    Report.write("optics_order.csv", analysis.opticsLines());
    Report.write("kdist.txt", analysis.kdistLines());
    Report.write("clusters.txt", analysis.clustersLines());
    Report.write("maps.txt", analysis.mapsLines())
}
