import java.io.File
data class Polygon(val input: Rings, val rings: Rings)
data class Target(val region: Region, val operands: Pair<Rings, Rings>? = null)
class Rejection(val reason: String) : Exception(reason)
fun integer(text: String): Long? {
    val digits = text.removePrefix("-")
    return if (digits.length in 1..9 && digits.all {
        it in '0'..'9'
    }) text.toLongOrNull() else null
}
fun validName(text: String): Boolean = text.length in 1..16 && text.all {
    it in 'a'..'z' || it in '0'..'9' || it == '_'
}
fun validate(rings: Rings): String? {
    for ((k, r) in rings.withIndex()) {
        val n = r.size
        if (n < 3) return "too_few_vertices ring ${k + 1}"
        val outside = r.firstOrNull {
            it.x < ZERO || it.y < ZERO || it.x > bi(1000) * it.d || it.y > bi(1000) * it.d
        }
        if (outside != null) return "out_of_range ring ${k + 1} $outside"
        val seen = mutableSetOf<Point>()
        for (p in r) if (!seen.add(p)) return "duplicate_vertex ring ${k + 1} $p"
        for (i in r.indices) if (cross(r[(i + n - 1) % n], r[i], r[(i + 1) % n]) == ZERO) return "collinear ring ${k + 1} ${r[i]}"
        for (i in r.indices) for (j in i + 1 until n) if (j != i + 1 && !(i == 0 && j == n - 1)) {
            if (Intersections.touch(r[i], r[(i + 1) % n], r[j], r[(j + 1) % n])) {
                return "self_intersection ring ${k + 1} ${Intersections.segment(r[i], r[(i + 1) % n])} ${Intersections.segment(r[j], r[(j + 1) % n])}"
            }
        }
    }
    for (i in rings.indices) for (j in i + 1 until rings.size) for (e in rings[i].indices) for (f in rings[j].indices) {
        val a = rings[i][e]
        val b = rings[i][(e + 1) % rings[i].size]
        val c = rings[j][f]
        val d = rings[j][(f + 1) % rings[j].size]
        if (Intersections.touch(a, b, c, d)) return "rings_touch rings ${i + 1} ${j + 1} ${Intersections.segment(a, b)} ${Intersections.segment(c, d)}"
    }
    for (k in 1 until rings.size) if (!RingOps.inside(rings[k][0], rings[0])) return "hole_outside ring ${k + 1} ${rings[k][0]}"
    for (i in 1 until rings.size) for (j in i + 1 until rings.size) {
        if (RingOps.inside(rings[j][0], rings[i])) return "hole_in_hole rings ${i + 1} ${j + 1} ${rings[j][0]}"
        if (RingOps.inside(rings[i][0], rings[j])) return "hole_in_hole rings ${i + 1} ${j + 1} ${rings[i][0]}"
    }
    return null
}
fun parseBlock(content: List<Pair<Int, String>>, end: Int): Rings {
    val rings = mutableListOf<Ring>()
    var i = 0
    while (i < content.size) {
        val (line, text) = content[i]
        val a = text.split(' ')
        if (a.size != 2 || !(a[0] == "OUTER" && rings.isEmpty() || a[0] == "HOLE" && rings.isNotEmpty()) ||
        a[1].length !in 1..9 || !a[1].all {
            it in '0'..'9'
        } || a[1].toInt() == 0) throw Rejection("format line $line")
        val n = a[1].toInt()
        i++
        val ring = mutableListOf<Point>()
        repeat(n) {
            if (i == content.size) throw Rejection("format line $end")
            val (at, vertex) = content[i]
            val words = vertex.split(' ')
            if (words.size != 2) throw Rejection("format line $at")
            val x = integer(words[0]) ?: throw Rejection("format line $at")
            val y = integer(words[1]) ?: throw Rejection("format line $at")
            ring.add(Point(x, y))
            i++
        }
        rings.add(ring)
    }
    if (rings.isEmpty()) throw Rejection("format line $end")
    return rings
}
class Polygons {
    val used = mutableSetOf<String>()
    val valid = mutableMapOf<String, Polygon>()
    val rejected = mutableListOf<String>()
    var blocks = 0
    var validBlocks = 0
    fun read() {
        val lines = File("input/polygons.txt").readLines()
        var i = 0
        while (i < lines.size) {
            if (lines[i].isEmpty() || lines[i].startsWith('#')) {
                i++; continue
            }
            val name = lines[i].split(' ')[1]
            val start = i + 1
            i++
            val content = mutableListOf<Pair<Int, String>>()
            while (lines[i] != "END") {
                if (lines[i].isNotEmpty() && !lines[i].startsWith('#')) content.add(Pair(i + 1, lines[i]))
                i++
            }
            val end = i + 1
            i++
            blocks++
            if (!used.add(name)) {
                rejected.add("polygon $name duplicate_name line $start"); continue
            }
            try {
                val input = parseBlock(content, end)
                validate(input)?.let {
                    throw Rejection(it)
                }
                valid[name] = Polygon(input, RingOps.canonical(input))
                validBlocks++
            } catch (e: Rejection) {
                rejected.add("polygon $name ${e.reason}")
            }
        }
    }
    fun get(name: String): Polygon {
        if (name !in used) throw Rejection("unknown_polygon $name")
        return valid[name] ?: throw Rejection("invalid_polygon $name")
    }
}
fun target(text: String, polygons: Polygons, results: Map<Int, Target>): Target {
    if (text.startsWith('@')) {
        val n = text.drop(1)
        if (n.length !in 1..9 || !n.all {
            it in '0'..'9'
        }) throw Rejection("bad_target $text")
        return results[n.toInt()] ?: throw Rejection("bad_target $text")
    }
    return Target(listOf(polygons.get(text).rings))
}
fun general(a: Rings, b: Rings, an: String, bn: String): String? {
    for (r in a) for (p in r) if (b.any {
        p in it
    }) return "shared_vertex $p"
    for (r in a) for (i in r.indices) for (s in b) for (j in s.indices) {
        val u = r[i]
        val v = r[(i + 1) % r.size]
        val w = s[j]
        val z = s[(j + 1) % s.size]
        if (Intersections.overlap(u, v, w, z)) return "overlapping_edges ${Intersections.segment(u, v)} ${Intersections.segment(w, z)}"
    }
    for (side in 0..1) {
        val left = if (side == 0) a else b
        val right = if (side == 0) b else a
        val pn = if (side == 0) an else bn
        val qn = if (side == 0) bn else an
        for (r in left) for (v in r) for (s in right) for (e in s.indices) {
            val u = s[e]
            val w = s[(e + 1) % s.size]
            if (Intersections.on(u, w, v)) return "vertex_on_edge $pn $v $qn ${Intersections.segment(u, w)}"
        }
    }
    return null
}
fun convex(rings: Rings): Boolean = rings.size == 1 && rings[0].indices.all {
    val r = rings[0]
    cross(r[(it + r.size - 1) % r.size], r[it], r[(it + 1) % r.size]) > ZERO
}
fun clip(a: Rings, window: Ring): Rings {
    val result = mutableListOf<Ring>()
    for (ring in a) {
        var list = ring
        for (j in window.indices) {
            val c1 = window[j]
            val c2 = window[(j + 1) % window.size]
            val next = mutableListOf<Point>()
            for (i in list.indices) {
                val prev = list[(i + list.size - 1) % list.size]
                val cur = list[i]
                val pin = cross(c1, c2, prev) > ZERO
                val cin = cross(c1, c2, cur) > ZERO
                if (pin != cin) next.add(Intersections.lineIntersection(prev, cur, c1, c2))
                if (cin) next.add(cur)
            }
            list = next
        }
        val clean = list.indices.filter {
            list[it] != list[(it + list.size - 1) % list.size]
        }.map {
            list[it]
        }
        if (clean.size >= 3) result.add(clean)
    }
    return result
}
fun cyclic(a: Ring, b: Ring): Boolean = a.size == b.size && b.indices.any {
    k -> a.indices.all {
        a[it] == b[(it + k) % b.size]
    }
}
fun locate(region: Region, p: Point): String {
    for ((k, polygon) in region.withIndex()) for ((j, ring) in polygon.withIndex()) if (RingOps.boundary(p, ring)) {
        return if (j == 0) "boundary outer ${k + 1}" else "boundary hole ${k + 1} $j"
    }
    for ((k, polygon) in region.withIndex()) if (RingOps.inside(p, polygon[0]) && polygon.drop(1).none {
        RingOps.inside(p, it)
    }) return "inside polygon ${k + 1}"
    return "outside"
}
fun operandLocation(p: Point, rings: Rings): String = if (rings.any {
    RingOps.boundary(p, it)
}) "boundary" else if (RingOps.interior(p, rings)) "inside" else "outside"
fun convexHull(ring: Ring): Ring {
    val sorted = ring.sortedWith(Comparator {
        a, b -> xCompare(a, b).let {
            if (it != 0) it else yCompare(a, b)
        }
    })
    fun half(points: Ring): Ring {
        val result = mutableListOf<Point>()
        for (p in points) {
            while (result.size >= 2 && cross(result[result.size - 2], result.last(), p) <= ZERO) result.removeAt(result.lastIndex)
            result.add(p)
        }
        return result.dropLast(1)
    }
    return half(sorted) + half(sorted.reversed())
}
fun twiceArea(ring: Ring): BI = ring.indices.fold(ZERO) {
    sum, i -> sum + ring[i].x * ring[(i + 1) % ring.size].y - ring[(i + 1) % ring.size].x * ring[i].y
}
data class Values(val lines: List<String>, val rings: Int, val holes: Int, val vertices: Int, val area: Double)
fun resultValues(region: Region, a: Rings, b: Rings?): Values {
    val rings = region.sumOf {
        it.size
    }
    val holes = rings - region.size
    val vertices = region.flatten().sumOf {
        it.size
    }
    val area = RingOps.totalArea(region)
    val lines = mutableListOf("polygons ${region.size} rings $rings holes $holes vertices $vertices area ${realText(area)}")
    var sx = 0.0
    var sy = 0.0
    var perimeter = 0.0
    val origins = IntArray(3)
    val points = mutableListOf<Point>()
    for ((k, polygon) in region.withIndex()) for ((j, ring) in polygon.withIndex()) {
        val label = if (j == 0) "outer ${k + 1}" else "hole ${k + 1} $j"
        lines.add("$label ${ring.size} ${realText(RingOps.area(ring))} " + ring.joinToString(" "))
        perimeter += RingOps.perimeter(ring)
        for (i in ring.indices) {
            val (x1, y1) = ring[i].real()
            val (x2, y2) = ring[(i + 1) % ring.size].real()
            val c = x1 * y2 - x2 * y1
            sx += (x1 + x2) * c
            sy += (y1 + y2) * c
            val v = ring[i]
            origins[if (a.any {
                v in it
            }) 0 else if (b?.any {
                v in it
            } == true) 1 else 2]++
            points.add(v)
        }
    }
    if (points.isEmpty()) {
        lines.add("bbox none"); lines.add("centroid none")
    }
    else {
        val minX = points.minWithOrNull(Comparator(::xCompare))!!
        val maxX = points.maxWithOrNull(Comparator(::xCompare))!!
        val minY = points.minWithOrNull(Comparator(::yCompare))!!
        val maxY = points.maxWithOrNull(Comparator(::yCompare))!!
        val low = Point(minX.x * minY.d, minY.y * minX.d, minX.d * minY.d)
        val high = Point(maxX.x * maxY.d, maxY.y * maxX.d, maxX.d * maxY.d)
        lines.add("bbox $low $high")
        lines.add("centroid (${realText(sx / (6 * area))},${realText(sy / (6 * area))})")
    }
    lines.add("perimeter ${realText(perimeter)}")
    lines.add("origins a ${origins[0]} b ${origins[1]} crossing ${origins[2]}")
    return Values(lines, rings, holes, vertices, area)
}
fun properties(polygon: Polygon, area: Double): List<String> {
    val orientations = polygon.input.joinToString(" ") {
        if (twiceArea(it) > ZERO) "ccw" else "cw"
    }
    val reflex = polygon.rings.sumOf {
        r -> r.indices.count {
            cross(r[(it + r.size - 1) % r.size], r[it], r[(it + 1) % r.size]) < ZERO
        }
    }
    val hull = convexHull(polygon.rings[0])
    val hullArea = twiceArea(hull).toDouble() / 2
    return listOf("input $orientations", "reflex $reflex", "hull ${hull.size} ${realText(hullArea)} solidity ${realText(area / hullArea, 6)}")
}
val kinds = listOf("UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA", "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER")
fun arguments(a: List<String>): Boolean {
    val expected = when (a[0]) {
        "UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "SNAP" -> 3
        "AREA" -> 2
        "LOCATE" -> 4
        "MOVE", "MIRROR" -> 5
        "ROTATE" -> 6
        "RENDER" -> 8
        else -> return false
    }
    if (a.size != expected) return false
    fun valid(i: Int, low: Long, high: Long): Boolean = integer(a[i])?.let {
        it in low..high
    } ?: false
    return when (a[0]) {
        "LOCATE" -> valid(2, 0, 1000) && valid(3, 0, 1000)
        "RENDER" -> {
            if (!(valid(2, 0, 1000) && valid(3, 0, 1000) && valid(4, 1, 100) && valid(5, 1, 100) && valid(6, 1, 100) && valid(7, 1, 60))) false
            else {
                val v = a.drop(2).map {
                    integer(it)!!
                }; v[0] + v[2] * v[4] <= 1000 && v[1] + v[3] * v[5] <= 1000
            }
        }
        "MOVE" -> valid(2, -1000, 1000) && valid(3, -1000, 1000) && validName(a[4])
        "ROTATE" -> valid(2, 0, 1000) && valid(3, 0, 1000) && valid(4, 1, 3) && validName(a[5])
        "MIRROR" -> a[2] in listOf("x", "y") && valid(3, 0, 1000) && validName(a[4])
        "SNAP" -> validName(a[2])
        else -> true
    }
}
data class Operation(val lines: MutableList<String> = mutableListOf(), var area: String? = null,
var drawing: List<String> = emptyList(), var target: Target? = null, var definition: Pair<String, Polygon>? = null, var crossings: Int = 0)
fun operation(number: Int, text: String, polygons: Polygons, results: Map<Int, Target>): Operation {
    val a = text.split(' ')
    val kind = a[0]
    if (kind !in kinds) throw Rejection("unknown_operation $kind")
    if (!arguments(a)) throw Rejection("bad_arguments")
    val binary = kind in kinds.take(5)
    val defining = kind in listOf("MOVE", "ROTATE", "MIRROR", "SNAP")
    val input = if (binary || kind in listOf("AREA", "MOVE", "ROTATE", "MIRROR")) polygons.get(a[1]) else null
    val b = if (binary) polygons.get(a[2]) else null
    val resolved = if (kind in listOf("LOCATE", "RENDER", "SNAP")) target(a[1], polygons, results) else null
    val newName = if (defining) a.last() else null
    if (newName in polygons.used) throw Rejection("duplicate_name $newName")
    if (kind == "SNAP" && resolved!!.region.size != 1) throw Rejection("not_single ${a[1]}")
    if (kind == "CLIP" && !convex(b!!.rings)) throw Rejection("not_convex ${a[2]}")
    if (binary) general(input!!.rings, b!!.rings, a[1], a[2])?.let {
        throw Rejection(it)
    }
    val op = Operation(mutableListOf("op $number $text"))
    if (kind == "LOCATE") {
        val p = Point(integer(a[2])!!, integer(a[3])!!)
        op.lines.add("location ${locate(resolved!!.region, p)}")
        resolved.operands?.let {
            op.lines.add("operands a ${operandLocation(p, it.first)} b ${operandLocation(p, it.second)}")
        }
        return op
    }
    if (kind == "RENDER") {
        val v = a.drop(2).map {
            integer(it)!!
        }
        val (drawing, counts) = Render.draw(resolved!!.region, resolved.operands, v)
        op.drawing = listOf("render $number ${a[1]} cols ${v[4]} rows ${v[5]} result ${counts[0]} a ${counts[1]} b ${counts[2]} both ${counts[3]}") + drawing
        op.lines.clear()
        return op
    }
    var polygon = input
    if (defining) {
        val inputRings = if (kind == "SNAP") resolved!!.region[0].map {
            r -> r.map {
                it.snapped()
            }
        }
        else input!!.input.map {
            r -> r.map {
                p ->
                var x = p.x
                var y = p.y
                when (kind) {
                    "MOVE" -> {
                        x += bi(integer(a[2])!!); y += bi(integer(a[3])!!)
                    }
                    "ROTATE" -> {
                        val cx = bi(integer(a[2])!!)
                        val cy = bi(integer(a[3])!!)
                        repeat(integer(a[4])!!.toInt()) {
                            val nx = cx - (y - cy); val ny = cy + (x - cx); x = nx; y = ny
                        }
                    }
                    else -> {
                        val c = bi(integer(a[3])!!); if (a[2] == "x") x = bi(2) * c - x else y = bi(2) * c - y
                    }
                }
                Point(x, y)
            }
        }
        if (kind == "SNAP") validate(inputRings)?.let {
            throw Rejection("invalid_result $it")
        }
        else if (inputRings.flatten().any {
            it.x < ZERO || it.y < ZERO || it.x > bi(1000) || it.y > bi(1000)
        }) throw Rejection("out_of_range $newName")
        polygon = Polygon(inputRings, RingOps.canonical(inputRings))
        op.definition = Pair(newName!!, polygon)
    }
    val region: Region
    if (binary) {
        val ar = input!!.rings
        val br = b!!.rings
        val graph = Graph(ar, br)
        val relation = if (graph.ordered.isNotEmpty()) "overlap" else if (graph.na == ar.size && graph.nb == 0) "within"
        else if (graph.nb == br.size && graph.na == 0) "contains" else if (graph.na == 0 && graph.nb == 0) "disjoint" else "overlap"
        val union = graph.result("UNION")
        val intersection = graph.result("INTERSECTION")
        val iou = RingOps.totalArea(intersection) / RingOps.totalArea(union)
        op.crossings = graph.ordered.size
        op.lines.add("relation $relation iou ${realText(iou, 6)}")
        op.lines.add("crossings ${op.crossings}")
        for ((p, enter) in graph.ordered) op.lines.add("crossing $p ${if (enter) "in" else "out"}")
        region = when (kind) {
            "UNION" -> union
            "INTERSECTION", "CLIP" -> intersection
            "DIFFERENCE" -> graph.result("DIFFERENCE")
            else -> (graph.result("DIFFERENCE") + Graph(br, ar).result("DIFFERENCE")).sortedBy {
                it[0][0]
            }
        }
        op.target = Target(region, Pair(ar, br))
    } else {
        region = listOf(polygon!!.rings); op.target = Target(region)
    }
    val operandA = if (binary) input!!.rings else polygon!!.rings
    val values = resultValues(region, operandA, b?.rings)
    op.lines.addAll(values.lines)
    op.area = "$number:${a.joinToString(":")},${values.rings},${values.holes},${values.vertices},${realText(values.area)}"
    if (!binary) op.lines.addAll(properties(polygon!!, values.area))
    if (kind == "CLIP") {
        val clipped = clip(operandA, b!!.rings[0])
        val resultRings = region.flatten()
        val match = resultRings.size == clipped.size && resultRings.all {
            r -> clipped.any {
                cyclic(r, it)
            }
        }
        op.lines.add("crosscheck ${if (match) "match" else "mismatch"} rings ${clipped.size} vertices ${clipped.sumOf { it.size }}")
    }
    return op
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    val polygons = Polygons()
    polygons.read()
    val targets = mutableMapOf<Int, Target>()
    val rejections = polygons.rejected.toMutableList()
    val result = mutableListOf<String>()
    val areas = mutableListOf("operation,rings,holes,vertices,area")
    val drawing = mutableListOf<String>()
    var total = 0
    var succeeded = 0
    var defined = 0
    var crossings = 0
    val counts = Array(kinds.size) {
        IntArray(2)
    }
    for (line in File("input/operations.txt").readLines()) if (line.isNotEmpty() && !line.startsWith('#')) {
        total++
        val kind = line.split(' ')[0]
        val index = kinds.indexOf(kind)
        if (index >= 0) counts[index][0]++
        try {
            val op = operation(total, line, polygons, targets)
            succeeded++
            counts[index][1]++
            crossings += op.crossings
            result.addAll(op.lines)
            op.area?.let {
                areas.add(it)
            }
            drawing.addAll(op.drawing)
            op.target?.let {
                targets[total] = it
            }
            op.definition?.let {
                (name, polygon) -> polygons.used.add(name); polygons.valid[name] = polygon; defined++
            }
        } catch (e: Rejection) {
            rejections.add("op $total ${e.reason}")
        }
    }
    result.add("summary polygons ${polygons.blocks} valid ${polygons.validBlocks} invalid ${polygons.blocks - polygons.validBlocks} defined $defined")
    result.add("summary operations $total succeeded $succeeded rejected ${total - succeeded}")
    result.add("summary crossings $crossings")
    for ((i, kind) in kinds.withIndex()) result.add("kind $kind ${counts[i][0]} ${counts[i][1]}")
    rejections.add(0, "rejections ${rejections.size}")
    write("results.txt", result)
    write("areas.csv", areas)
    write("render.txt", drawing)
    write("rejections.txt", rejections)
}
