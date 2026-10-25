fun regionCode(point: Point, clip: Rectangle): Int = (if (point.x < clip.x0) 1 else 0) or (if (point.x > clip.x1) 2 else 0) or (if (point.y < clip.y0) 4 else 0) or (if (point.y > clip.y1) 8 else 0)
fun clipSegment(start: Point, end: Point, clip: Rectangle): Pair<Point, Point>? {
    var p = start; var q = end
    while (true) {
        val first = regionCode(p, clip); val second = regionCode(q, clip)
        if (first == 0 && second == 0) return p to q
        if ((first and second) != 0) return null
        val code = if (first != 0) first else second; val a = if (first != 0) p else q; val b = if (first != 0) q else p
        val point = if ((code and 4) != 0) Point(a.x + roundRatio((b.x - a.x) * (clip.y0 - a.y), b.y - a.y), clip.y0)
            else if ((code and 8) != 0) Point(a.x + roundRatio((b.x - a.x) * (clip.y1 - a.y), b.y - a.y), clip.y1)
            else if ((code and 2) != 0) Point(clip.x1, a.y + roundRatio((b.y - a.y) * (clip.x1 - a.x), b.x - a.x))
            else Point(clip.x0, a.y + roundRatio((b.y - a.y) * (clip.x0 - a.x), b.x - a.x))
        if (first != 0) p = point else q = point
    }
}
fun clipPolygon(vertices: List<Point>, clip: Rectangle): List<Point> {
    var current = vertices
    for ((axis, limit, minimum) in listOf(Triple(0, clip.x0, true), Triple(0, clip.x1 + 1, false), Triple(1, clip.y0, true), Triple(1, clip.y1 + 1, false))) {
        fun inside(point: Point): Boolean { val value = if (axis == 0) point.x else point.y; return if (minimum) value >= limit else value <= limit }
        fun intersection(start: Point, end: Point): Point = if (axis == 0) Point(limit, start.y + roundRatio((limit - start.x) * (end.y - start.y), end.x - start.x)) else Point(start.x + roundRatio((limit - start.y) * (end.x - start.x), end.y - start.y), limit)
        val output = mutableListOf<Point>()
        for ((index, end) in current.withIndex()) { val start = current[(index + current.size - 1) % current.size]; if (inside(end)) { if (!inside(start)) output += intersection(start, end); output += end } else if (inside(start)) output += intersection(start, end) }
        current = output
    }
    return current
}
