import kotlin.math.abs

fun fillPolygons(sequences: List<List<Point>>, rule: String, clip: Rectangle): Set<Point> {
    val edges = sequences.flatMap { vertices -> vertices.mapIndexedNotNull { index, start -> val end = vertices[(index + 1) % vertices.size]; if (start.y == end.y) null else start to end } }
    val pixels = mutableSetOf<Point>()
    for (y in clip.y0..clip.y1) {
        val crossings = edges.mapNotNull { (a, b) ->
            if (y < minOf(a.y, b.y) || y >= maxOf(a.y, b.y)) null
            else { var d = b.y - a.y; var n = 2 * a.x * d + (2 * y + 1 - 2 * a.y) * (b.x - a.x); if (d < 0) { d = -d; n = -n }; floorDivide(n - d, 2 * d) + 1 to if (b.y > a.y) 1 else -1 }
        }.sortedWith(compareBy<Pair<Int, Int>> { it.first }.thenBy { it.second })
        var count = 0; var winding = 0; var index = 0
        for (x in clip.x0..clip.x1) { while (index < crossings.size && crossings[index].first <= x) { count++; winding += crossings[index].second; index++ }; if (if (rule == "evenodd") count % 2 == 1 else winding != 0) pixels += Point(x, y) }
    }
    return pixels
}
fun fillShape(center: Point, points: Set<Point>, clip: Rectangle): Set<Point> {
    val extents = mutableMapOf<Int, Int>(); val pixels = mutableSetOf<Point>()
    for (point in points) extents[point.y] = maxOf(extents[point.y] ?: 0, abs(point.x))
    for ((dy, extent) in extents) { val y = center.y + dy; if (y in clip.y0..clip.y1) for (x in maxOf(clip.x0, center.x - extent)..minOf(clip.x1, center.x + extent)) pixels += Point(x, y) }
    return pixels
}
fun floodFill(layer: Layer, seed: Point, clip: Rectangle): Set<Point> {
    val target = layer.colorAt(seed); val pixels = mutableSetOf(seed); val pending = ArrayDeque<Point>(); pending.addLast(seed)
    while (pending.isNotEmpty()) { val point = pending.removeLast(); for (neighbor in listOf(Point(point.x + 1, point.y), Point(point.x - 1, point.y), Point(point.x, point.y + 1), Point(point.x, point.y - 1))) if (clip.contains(neighbor) && neighbor !in pixels && layer.colorAt(neighbor) == target) { pixels += neighbor; pending.addLast(neighbor) } }
    return pixels
}
