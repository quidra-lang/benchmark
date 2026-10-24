private class Problem(val text: String) : RuntimeException(text)

private fun fail(text: String): Nothing = throw Problem("error: $text")

private fun names(values: List<String>) = values.sorted().joinToString(" ").ifEmpty {
    "none"
}

private fun decimal(numerator: Long, denominator: Long): String {
    val v = numerator * 100 / denominator
    return "${v / 100}.${(v % 100).toString().padStart(2, '0')}"
}

private data class Rect(val name: String, val layer: String, val x1: Int, val y1: Int, val x2: Int, val y2: Int) {
    val width get() = x2 - x1
    val height get() = y2 - y1
    val area get() = width.toLong() * height
    override fun toString() = "($x1,$y1)-($x2,$y2)"

    fun contains(b: Rect) = x1 <= b.x1 && y1 <= b.y1 && x2 >= b.x2 && y2 >= b.y2

    fun margins(b: Rect) = listOf(b.x1 - x1, b.y1 - y1, x2 - b.x2, y2 - b.y2)

    fun moved(dx: Int, dy: Int) = copy(x1 = x1 + dx, y1 = y1 + dy, x2 = x2 + dx, y2 = y2 + dy)

    fun checkBounds() {
        if (listOf(x1, y1, x2, y2).any {
            it !in -10000..10000
        }) fail("out of bounds")
    }
}

private data class Relation(val common: Rect) {
    val ox = common.width
    val oy = common.height
    val kind = if (ox > 0 && oy > 0) 0 else if (ox >= 0 && oy >= 0 && ox + oy > 0) 1 else if (ox == 0 && oy == 0) 2 else 3
    val gap = maxOf(0, -ox, -oy)
    val direction = if (kind == 2) "corner" else if (ox < 0 && oy < 0) "diagonal" else if (ox < 0) "x" else "y"
}

private fun relation(a: Rect, b: Rect) = Relation(Rect("", "", maxOf(a.x1, b.x1), maxOf(a.y1, b.y1), minOf(a.x2, b.x2), minOf(a.y2, b.y2)))

private fun connected(a: Rect, b: Rect) = relation(a, b).kind <= 1

private fun bbox(rs: List<Rect>) = Rect("", "", rs.minOf {
    it.x1
}, rs.minOf {
    it.y1
}, rs.maxOf {
    it.x2
}, rs.maxOf {
    it.y2
})

private class Grid(rs: List<Rect>) {
    val xs = rs.flatMap {
        listOf(it.x1, it.x2)
    }.distinct().sorted()
    val ys = rs.flatMap {
        listOf(it.y1, it.y2)
    }.distinct().sorted()
    val nx = xs.size - 1
    val ny = ys.size - 1
    val count = Array(ny) {
        y -> IntArray(nx) {
            x -> rs.count {
                it.x1 <= xs[x] && it.x2 > xs[x] && it.y1 <= ys[y] && it.y2 > ys[y]
            }
        }
    }

    fun area(k: Int = 1, window: Rect? = null): Long {
        var sum = 0L
        for (y in 0 until ny) for (x in 0 until nx) if (count[y][x] >= k) {
            val w = maxOf(0, minOf(xs[x + 1], window?.x2 ?: xs[x + 1]) - maxOf(xs[x], window?.x1 ?: xs[x]))
            val h = maxOf(0, minOf(ys[y + 1], window?.y2 ?: ys[y + 1]) - maxOf(ys[y], window?.y1 ?: ys[y]))
            sum += w.toLong() * h
        }
        return sum
    }

    fun perimeter(): Long {
        var sum = 0L
        for (y in 0 until ny) for (x in 0 until nx) if (count[y][x] > 0) {
            if (x == 0 || count[y][x - 1] == 0) sum += ys[y + 1] - ys[y]
            if (x + 1 == nx || count[y][x + 1] == 0) sum += ys[y + 1] - ys[y]
            if (y == 0 || count[y - 1][x] == 0) sum += xs[x + 1] - xs[x]
            if (y + 1 == ny || count[y + 1][x] == 0) sum += xs[x + 1] - xs[x]
        }
        return sum
    }

    fun empty(): Rect? {
        var best: Rect? = null
        for (bottom in 0 until ny) {
            val free = BooleanArray(nx) {
                true
            }
            for (top in bottom until ny) {
                for (x in 0 until nx) free[x] = free[x] && count[top][x] == 0
                var x = 0
                while (x < nx) {
                    if (!free[x]) {
                        x++
                        continue
                    }
                    val start = x
                    while (x < nx && free[x]) x++
                    val r = Rect("", "", xs[start], ys[bottom], xs[x], ys[top + 1])
                    val old = best
                    if (old == null || r.area > old.area || r.area == old.area && (r.x1 < old.x1 || r.x1 == old.x1 && (r.y1 < old.y1 || r.y1 == old.y1 && r.width < old.width))) best = r
                }
            }
        }
        return best
    }

    fun holes(): List<Pair<Long, Rect>> {
        val seen = Array(ny) {
            BooleanArray(nx)
        }
        val result = mutableListOf<Triple<Int, Int, Pair<Long, Rect>>>()
        for (y in 0 until ny) for (x in 0 until nx) {
            if (count[y][x] > 0 || seen[y][x]) continue
            val queue = ArrayDeque<Pair<Int, Int>>()
            queue.add(x to y)
            seen[y][x] = true
            var boundary = false
            var area = 0L
            var x1 = xs[x]
            var y1 = ys[y]
            var x2 = xs[x + 1]
            var y2 = ys[y + 1]
            var ax = xs[x]
            var ay = ys[y]
            while (queue.isNotEmpty()) {
                val (cx, cy) = queue.removeFirst()
                boundary = boundary || cx == 0 || cy == 0 || cx == nx - 1 || cy == ny - 1
                area += (xs[cx + 1] - xs[cx]).toLong() * (ys[cy + 1] - ys[cy])
                x1 = minOf(x1, xs[cx])
                y1 = minOf(y1, ys[cy])
                x2 = maxOf(x2, xs[cx + 1])
                y2 = maxOf(y2, ys[cy + 1])
                if (ys[cy] < ay || ys[cy] == ay && xs[cx] < ax) {
                    ax = xs[cx]
                    ay = ys[cy]
                }
                for ((dx, dy) in listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)) {
                    val xx = cx + dx
                    val yy = cy + dy
                    if (xx in 0 until nx && yy in 0 until ny && !seen[yy][xx] && count[yy][xx] == 0) {
                        seen[yy][xx] = true
                        queue.add(xx to yy)
                    }
                }
            }
            if (!boundary) result.add(Triple(ay, ax, area to Rect("", "", x1, y1, x2, y2)))
        }
        return result.sortedWith(compareBy<Triple<Int, Int, Pair<Long, Rect>>> {
            it.first
        }.thenBy {
            it.second
        }).map {
            it.third
        }
    }

    fun pieces(): List<Rect> {
        var active = mutableMapOf<Pair<Int, Int>, Rect>()
        val result = mutableListOf<Rect>()
        for (y in 0 until ny) {
            val next = mutableMapOf<Pair<Int, Int>, Rect>()
            var x = 0
            while (x < nx) {
                if (count[y][x] == 0) {
                    x++
                    continue
                }
                val start = x
                while (x < nx && count[y][x] > 0) x++
                val key = xs[start] to xs[x]
                next[key] = active[key]?.copy(y2 = ys[y + 1]) ?: Rect("", "", xs[start], ys[y], xs[x], ys[y + 1])
            }
            for ((key, r) in active) if (key !in next) result.add(r)
            active = next
        }
        result.addAll(active.values)
        return result.sortedWith(compareBy<Rect> {
            it.y1
        }.thenBy {
            it.x1
        })
    }
}

private data class Violation(val a: Rect, val b: Rect, val relation: Relation)

private fun spacing(rs: List<Rect>, s: Int): List<Violation> {
    val found = mutableListOf<Violation>()
    for (i in rs.indices) for (j in i + 1 until rs.size) {
        val r = relation(rs[i], rs[j])
        if (r.kind == 2 || r.kind == 3 && r.gap < s) found.add(Violation(rs[i], rs[j], r))
    }
    return found.sortedWith(compareBy<Violation> {
        it.relation.gap
    }.thenBy {
        it.a.name
    }.thenBy {
        it.b.name
    })
}

private fun violationText(v: Violation) = "${v.a.name} ${v.b.name} gap ${v.relation.gap} ${v.relation.direction}"

private fun nets(rs: List<Rect>): List<List<Rect>> {
    val seen = mutableSetOf<String>()
    val groups = mutableListOf<List<Rect>>()
    for (r in rs) if (seen.add(r.name)) {
        val queue = mutableListOf(r)
        var i = 0
        while (i < queue.size) {
            val a = queue[i++]
            for (b in rs) if (b.name !in seen && connected(a, b)) {
                seen.add(b.name)
                queue.add(b)
            }
        }
        groups.add(queue.sortedBy {
            it.name
        })
    }
    return groups
}

private data class RuleKey(val kind: String, val inner: String, val outer: String) : Comparable<RuleKey> {
    override fun compareTo(other: RuleKey) = compareValuesBy(this, other, {
        it.kind
    }, {
        it.inner
    }, {
        it.outer
    })
}

private class Layout {
    var rectangles = sortedMapOf<String, Rect>()
    val history = mutableListOf<Pair<Map<String, Rect>, String>>()
    val rules = sortedMapOf<RuleKey, Int>()

    fun get(name: String) = rectangles[name] ?: fail("unknown rectangle $name")

    fun layer(name: String): List<Rect> = rectangles.values.filter {
        it.layer == name
    }

    fun checkedLayer(name: String) = layer(name).also {
        if (it.isEmpty()) fail("no rectangles on $name")
    }

    fun command(line: String): List<String> {
        val w = line.split(' ')
        val c = w[0]

        fun n(i: Int) = w[i].toInt()
        val out = mutableListOf<String>()
        if (c in setOf("ADD", "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE")) {
            val next = rectangles.toSortedMap()
            val name = w[1]
            val r: Rect
            when (c) {
                "ADD" -> {
                    if (name in rectangles) fail("duplicate rectangle $name")
                    r = Rect(name, w[2], n(3), n(4), n(5), n(6))
                    if (r.width <= 0 || r.height <= 0) fail("invalid rectangle")
                    r.checkBounds()
                    next[name] = r
                    out.add("added $name ${r.layer} $r")
                }
                "COPY" -> {
                    val old = get(name)
                    if (w[2] in rectangles) fail("duplicate rectangle ${w[2]}")
                    r = old.moved(n(3), n(4)).copy(name = w[2])
                    r.checkBounds()
                    next[r.name] = r
                    out.add("copied $name to ${r.name} $r")
                }
                "MOVE" -> {
                    r = get(name).moved(n(2), n(3))
                    r.checkBounds()
                    next[name] = r
                    out.add("moved $name to $r")
                }
                "RESIZE" -> {
                    val old = get(name)
                    if (n(2) <= 0 || n(3) <= 0) fail("invalid size")
                    r = old.copy(x2 = old.x1 + n(2), y2 = old.y1 + n(3))
                    r.checkBounds()
                    next[name] = r
                    out.add("resized $name to $r")
                }
                "SPLIT" -> {
                    val old = get(name)
                    if (w[4] in rectangles) fail("duplicate rectangle ${w[4]}")
                    val p = n(3)
                    val x = w[2] == "x"
                    if (p <= (if (x) old.x1 else old.y1) || p >= (if (x) old.x2 else old.y2)) fail("cut outside $name")
                    r = if (x) old.copy(x2 = p) else old.copy(y2 = p)
                    val other = if (x) old.copy(name = w[4], x1 = p) else old.copy(name = w[4], y1 = p)
                    next[name] = r
                    next[other.name] = other
                    out.add("split $name at ${w[2]}=$p: $name $r, ${other.name} $other")
                }
                "LAYER" -> {
                    val old = get(name)
                    if (old.layer == w[2]) fail("already on ${w[2]}")
                    r = old.copy(layer = w[2])
                    next[name] = r
                    out.add("layer $name ${old.layer} -> ${r.layer}")
                } else -> {
                    get(name)
                    next.remove(name)
                    out.add("deleted $name")
                }
            }
            history.add(rectangles.toMap() to line)
            rectangles = next
            return out
        }
        when (c) {
            "UNDO" -> {
                if (history.isEmpty()) fail("nothing to undo")
                val (old, text) = history.removeAt(history.lastIndex)
                rectangles = old.toSortedMap()
                return listOf("undo: $text")
            }
            "LIST" -> return listOf("rectangles: ${rectangles.size}") + rectangles.values.map {
                "${it.name} ${it.layer} $it ${it.width}x${it.height}"
            }
            "INFO" -> {
                val a = get(w[1])
                val others = rectangles.values.filter {
                    it.name != a.name
                }
                out.add("${a.name} ${a.layer} $a ${a.width}x${a.height} area ${a.area}")
                for ((label, kind) in listOf("overlaps" to 0, "touches" to 1, "corners" to 2)) out.add("$label: " + names(others.filter {
                    it.layer == a.layer && relation(a, it).kind == kind
                }.map {
                    it.name
                }))
                out.add("encloses: " + names(others.filter {
                    a.contains(it)
                }.map {
                    it.name
                }))
                out.add("enclosed by: " + names(others.filter {
                    it.contains(a)
                }.map {
                    it.name
                }))
                return out
            }
            "LAYERS" -> {
                val layers = rectangles.values.map {
                    it.layer
                }.toSortedSet()
                out.add("layers: ${layers.size}")
                for (l in layers) {
                    val rs = layer(l)
                    out.add("$l: ${rs.size} rectangles, area ${Grid(rs).area()}, nets ${nets(rs).size}")
                }
                return out
            }
            "INTERSECT", "ADJACENT", "ENCLOSE", "PATH" -> {
                val a = get(w[1])
                val b = get(w[2])
                if (a.name == b.name) fail("same rectangle ${a.name}")
                val r = relation(a, b)
                val common = r.common
                if (c == "INTERSECT") return listOf("intersect ${a.name} ${b.name}: " + when (r.kind) {
                    0 -> "$common area ${common.area}"
                    1 -> "segment $common length ${r.ox + r.oy}"
                    2 -> "point (${common.x1},${common.y1})"
                    else -> "none, gap ${r.gap}"
                })
                if (c == "ADJACENT") {
                    val d = if (r.ox == 0) {
                        if (a.x2 == common.x1) "west" else "east"
                    } else if (a.y2 == common.y1) "south" else "north"
                    return listOf("adjacent ${a.name} ${b.name}: " + when (r.kind) {
                        0 -> "overlapping"
                        1 -> "${a.name} is $d of ${b.name}, edge $common, length ${r.ox + r.oy}"
                        2 -> "corner only at (${common.x1},${common.y1})"
                        else -> "not adjacent"
                    })
                }
                if (c == "ENCLOSE") {
                    val m = a.margins(b)
                    return listOf("enclose ${a.name} ${b.name}: " + (if (m.all {
                        it >= 0
                    }) "yes" else "no") + ", margins left ${m[0]} bottom ${m[1]} right ${m[2]} top ${m[3]}" + if (a.contains(b)) ", min ${m.minOrNull()}" else "")
                }
                if (a.layer != b.layer) fail("different layers")
                val previous = mutableMapOf<String, String>()
                val seen = mutableSetOf(a.name)
                val queue = mutableListOf(a)
                var at = 0
                val rs = layer(a.layer)
                while (at < queue.size) {
                    val p = queue[at++]
                    for (q in rs) if (q.name !in seen && connected(p, q)) {
                        seen.add(q.name)
                        previous[q.name] = p.name
                        queue.add(q)
                    }
                }
                if (b.name !in seen) return listOf("path ${a.name} ${b.name}: none")
                val path = mutableListOf(b.name)
                while (path.last() != a.name) path.add(previous.getValue(path.last()))
                path.reverse()
                return listOf("path ${a.name} ${b.name}: ${path.joinToString(" -> ")} (${path.size - 1} steps)")
            }
            "AT" -> {
                val x = n(1)
                val y = n(2)
                val found = rectangles.values.filter {
                    x in it.x1..it.x2 && y in it.y1..it.y2
                }.map {
                    val xx = x == it.x1 || x == it.x2
                    val yy = y == it.y1 || y == it.y2
                    "${it.name} ${it.layer} " + if (xx && yy) "corner" else if (xx || yy) "edge" else "inside"
                }
                return listOf("at ($x,$y): " + found.joinToString(", ").ifEmpty {
                    "none"
                })
            }
            "NEAREST" -> {
                val a = get(w[1])
                val b = layer(a.layer).filter {
                    it.name != a.name
                }.minWithOrNull(compareBy<Rect> {
                    relation(a, it).gap
                }.thenBy {
                    it.name
                })
                return listOf("nearest ${a.name}: " + if (b == null) "none" else "${b.name} gap ${relation(a, b).gap}")
            }
            "OVERLAPS" -> {
                val rs = if (w.size == 2) checkedLayer(w[1]) else rectangles.values.toList()
                val found = mutableListOf<Triple<Rect, Rect, Rect>>()
                for (i in rs.indices) for (j in i + 1 until rs.size) if (rs[i].layer == rs[j].layer) {
                    val r = relation(rs[i], rs[j])
                    if (r.kind == 0) found.add(Triple(rs[i], rs[j], r.common))
                }
                found.sortWith(compareBy<Triple<Rect, Rect, Rect>> {
                    it.first.layer
                }.thenBy {
                    it.first.name
                }.thenBy {
                    it.second.name
                })
                out.add("overlaps " + (if (w.size == 1) "all layers" else w[1]) + ": ${found.size}")
                for ((a, b, r) in found) out.add((if (w.size == 1) "${a.layer} " else "") + "${a.name} ${b.name} $r area ${r.area}")
                return out
            }
            "RULE" -> {
                val kind = w[1].lowercase()
                if (kind == "enclose" && w[2] == w[3]) fail("same layer ${w[2]}")
                val key = RuleKey(kind, w[2], if (kind == "enclose") w[3] else "")
                val v = n(if (kind == "enclose") 4 else 3)
                rules[key] = v
                return listOf("rule $kind ${w[2]}" + (if (kind == "enclose") " ${w[3]}" else "") + " $v")
            }
            "CHECK" -> {
                if (rules.isEmpty()) fail("no rules")
                var total = 0
                for ((rule, v) in rules) {
                    val found = mutableListOf<String>()
                    val rs = layer(rule.inner)
                    when (rule.kind) {
                        "spacing" -> found.addAll(spacing(rs, v).map(::violationText))
                        "width" -> for (r in rs) if (minOf(r.width, r.height) < v) found.add("${r.name} width ${minOf(r.width, r.height)}")
                        else -> {
                            val outer = layer(rule.outer)
                            for (r in rs) {
                                val best = outer.maxOfOrNull {
                                    it.margins(r).minOrNull()!!
                                }
                                if (best == null || best < v) found.add("${r.name} best margin ${best ?: "none"}")
                            }
                        }
                    }
                    total += found.size
                    out.add("${rule.kind} ${rule.inner}" + (if (rule.kind == "enclose") " ${rule.outer}" else "") + " $v: ${found.size} violations")
                    out.addAll(found)
                }
                out.add("check: $total violations in ${rules.size} rules")
                return out
            }
        }
        val rs = checkedLayer(if (c == "COVER") w[2] else w[1])
        val l = rs[0].layer
        val g = Grid(rs)
        val b = bbox(rs)
        when (c) {
            "AREA" -> return listOf("area $l: ${g.area()}")
            "COVER" -> return listOf("cover $l >= ${w[1]}: ${g.area(n(1))}")
            "PERIMETER" -> return listOf("perimeter $l: ${g.perimeter()}")
            "NETS" -> {
                val groups = nets(rs)
                out.add("nets $l: ${groups.size}")
                for ((i, group) in groups.withIndex()) out.add("net ${i + 1}: ${names(group.map { it.name })} area ${Grid(group).area()}")
                return out
            }
            "DRC" -> {
                val violations = spacing(rs, n(2))
                return listOf("drc $l spacing ${w[2]}: ${violations.size} violations") + violations.map(::violationText)
            }
            "BBOX" -> return listOf("bbox $l: $b ${b.width}x${b.height}, ${rs.size} rectangles, density ${decimal(100 * g.area(), b.area)}%")
            "DENSITY" -> {
                val size = n(2)
                val cols = (b.width + size - 1) / size
                val rows = (b.height + size - 1) / size
                if (cols > 20 || rows > 20) fail("too many windows")
                val values = Array(rows) {
                    y -> LongArray(cols) {
                        x -> val xx = b.x1 + x * size
                        val yy = b.y1 + y * size
                        g.area(window = Rect("", "", xx, yy, xx + size, yy + size))
                    }
                }
                val denominator = size.toLong() * size
                out.add("density $l window $size: ${cols}x$rows")
                for (y in rows - 1 downTo 0) out.add(values[y].joinToString(" ") {
                    (100 * it / denominator).toString()
                })
                var minX = 0
                var minY = 0
                var maxX = 0
                var maxY = 0
                for (y in 0 until rows) for (x in 0 until cols) {
                    if (values[y][x] < values[minY][minX]) {
                        minX = x
                        minY = y
                    }
                    if (values[y][x] > values[maxY][maxX]) {
                        maxX = x
                        maxY = y
                    }
                }
                out.add("min ${decimal(100 * values[minY][minX], denominator)}% at (${b.x1 + minX * size},${b.y1 + minY * size})")
                out.add("max ${decimal(100 * values[maxY][maxX], denominator)}% at (${b.x1 + maxX * size},${b.y1 + maxY * size})")
                return out
            }
            "RENDER" -> {
                val r = Rect("", "", n(2), n(3), n(4), n(5))
                if (r.width <= 0 || r.height <= 0) fail("invalid window")
                if (r.width > 60 || r.height > 40) fail("window too large")
                out.add("render $l $r")
                for (y in r.y2 - 1 downTo r.y1) out.add((r.x1 until r.x2).map {
                    x -> val count = rs.count {
                        it.x1 <= x && x < it.x2 && it.y1 <= y && y < it.y2
                    }
                    if (count == 0) '.' else if (count >= 10) '*' else ('0'.code + count).toChar()
                }.joinToString(""))
                return out
            }
            "EMPTY" -> {
                val empty = g.empty()
                return listOf("empty $l: " + if (empty == null) "none" else "$empty area ${empty.area}")
            }
            "HOLES" -> {
                val holes = g.holes()
                return listOf("holes $l: ${holes.size}") + holes.mapIndexed {
                    i, (area, r) -> "hole ${i + 1}: area $area, bbox $r"
                }
            }
            "MERGE" -> {
                val pieces = g.pieces()
                return listOf("merge $l: ${pieces.size} pieces") + pieces.map {
                    it.toString()
                }
            }
        }
        return emptyList()
    }
}

fun main() {
    val layout = Layout()
    repeat(readLine()!!.toInt()) {
        val line = readLine()!!
        try {
            layout.command(line).forEach(::println)
        } catch (e: Problem) {
            println(e.text)
        }
    }
}
