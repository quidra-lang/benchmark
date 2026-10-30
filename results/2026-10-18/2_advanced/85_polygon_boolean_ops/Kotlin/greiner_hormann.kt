data class Crossing(val point: Point, val ar: Int, val ae: Int, val br: Int, val be: Int, val t: Fraction, val u: Fraction)
data class Node(val point: Point, val crossing: Int? = null, val enter: Boolean = false)

class Graph(a: Rings, b: Rings) {
    val nodes = List(2) { mutableListOf<List<Node>>() }
    val locations: List<MutableList<Pair<Int, Int>>>
    val ordered = mutableListOf<Pair<Point, Boolean>>()
    val order = mutableListOf<Int>()
    val na = a.count { RingOps.interior(it[0], b) }
    val nb = b.count { RingOps.interior(it[0], a) }
    init {
        val crossings = mutableListOf<Crossing>()
        for ((ar, r) in a.withIndex()) for (ae in r.indices) for ((br, q) in b.withIndex()) for (be in q.indices) {
            val found = Intersections.crossing(r[ae], r[(ae + 1) % r.size], q[be], q[(be + 1) % q.size])
            if (found != null) crossings.add(Crossing(found.first, ar, ae, br, be, found.second, found.third))
        }
        locations = List(crossings.size) { mutableListOf(Pair(0, 0), Pair(0, 0)) }
        for ((side, pair) in listOf(Pair(a, b), Pair(b, a)).withIndex()) {
            val (p, q) = pair
            for ((ri, ring) in p.withIndex()) {
                val list = mutableListOf<Node>()
                var inside = RingOps.interior(ring[0], q)
                for (edge in ring.indices) {
                    list.add(Node(ring[edge]))
                    val on = crossings.indices.filter {
                        if (side == 0) crossings[it].ar == ri && crossings[it].ae == edge else crossings[it].br == ri && crossings[it].be == edge
                    }.sortedBy { if (side == 0) crossings[it].t else crossings[it].u }
                    for (id in on) {
                        locations[id][side] = Pair(ri, list.size)
                        list.add(Node(crossings[id].point, id, !inside))
                        if (side == 0) { order.add(id); ordered.add(Pair(crossings[id].point, !inside)) }
                        inside = !inside
                    }
                }
                nodes[side].add(list)
            }
        }
    }
    fun result(kind: String): Region {
        val inverted = if (kind == "UNION") listOf(true, true) else if (kind == "DIFFERENCE") listOf(true, false) else listOf(false, false)
        val visited = BooleanArray(locations.size)
        val rings = mutableListOf<Ring>()
        for (start in order) if (!visited[start]) {
            var side = 0
            var id = start
            val points = mutableListOf<Point>()
            while (true) {
                val (ri, index) = locations[id][side]
                val list = nodes[side][ri]
                val node = list[index]
                visited[id] = true
                points.add(node.point)
                val forward = node.enter != inverted[side]
                var next = index
                do {
                    next = if (forward) (next + 1) % list.size else (next + list.size - 1) % list.size
                    if (list[next].crossing == null) points.add(list[next].point)
                } while (list[next].crossing == null)
                val found = list[next].crossing!!
                if (found == start) break
                id = found
                side = 1 - side
            }
            rings.add(points)
        }
        for (side in 0..1) {
            val other = nodes[1 - side].map { list -> list.map { it.point } }
            for (list in nodes[side]) if (list.none { it.crossing != null } && RingOps.interior(list[0].point, other) != inverted[side]) {
                rings.add(list.map { it.point })
            }
        }
        return RingOps.assemble(rings)
    }
}
