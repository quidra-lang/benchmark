import kotlin.math.sqrt

typealias Ring = List<Point>
typealias Rings = List<Ring>
typealias Region = List<Rings>

object RingOps {
    fun inside(p: Point, ring: Ring): Boolean {
        var odd = false
        for (i in ring.indices) {
            val a = ring[i]
            val b = ring[(i + 1) % ring.size]
            if ((a.y * p.d > p.y * a.d) != (b.y * p.d > p.y * b.d)) {
                val lo = if (yCompare(a, b) < 0) a else b
                val hi = if (yCompare(a, b) < 0) b else a
                if (cross(lo, hi, p) > ZERO) odd = !odd
            }
        }
        return odd
    }
    fun interior(p: Point, rings: Rings): Boolean = rings.count { inside(p, it) } % 2 == 1
    fun boundary(p: Point, ring: Ring): Boolean = ring.indices.any { Intersections.on(ring[it], ring[(it + 1) % ring.size], p) }
    fun rotate(ring: Ring): Ring {
        val i = ring.indexOf(ring.minOrNull()!!)
        return ring.drop(i) + ring.take(i)
    }
    fun ccw(ring: Ring): Boolean = cross(ring.last(), ring[0], ring[1]) > ZERO
    fun reverse(ring: Ring): Ring = listOf(ring[0]) + ring.drop(1).reversed()
    fun canonical(input: Rings): Rings {
        val rings = input.mapIndexed { i, r -> rotate(r).let { if (ccw(it) == (i == 0)) it else reverse(it) } }
        return listOf(rings[0]) + rings.drop(1).sortedBy { it[0] }
    }
    fun assemble(input: Rings): Region {
        val rings = input.map(::rotate).toMutableList()
        val depths = rings.indices.map { i -> rings.indices.count { it != i && inside(rings[i][0], rings[it]) } }
        for (i in rings.indices) if (ccw(rings[i]) != (depths[i] % 2 == 0)) rings[i] = reverse(rings[i])
        return rings.indices.filter { depths[it] % 2 == 0 }.sortedBy { rings[it][0] }.map { i ->
            listOf(rings[i]) + rings.indices.filter { depths[it] == depths[i] + 1 && inside(rings[it][0], rings[i]) }
                .sortedBy { rings[it][0] }.map { rings[it] }
        }
    }
    fun area(ring: Ring): Double {
        var sum = 0.0
        for (i in ring.indices) {
            val (x, y) = ring[i].real()
            val (u, v) = ring[(i + 1) % ring.size].real()
            sum += x * v - u * y
        }
        return sum / 2
    }
    fun perimeter(ring: Ring): Double {
        var sum = 0.0
        for (i in ring.indices) {
            val (x, y) = ring[i].real()
            val (u, v) = ring[(i + 1) % ring.size].real()
            val dx = u - x
            val dy = v - y
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum
    }
    fun totalArea(region: Region): Double {
        var sum = 0.0
        for (polygon in region) for (ring in polygon) sum += area(ring)
        return sum
    }
}
