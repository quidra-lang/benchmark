import kotlin.math.abs

fun bresenham(start: Point, end: Point): List<Point> {
    var x = start.x; var y = start.y; val dx = abs(end.x - start.x); val dy = -abs(end.y - start.y); val sx = if (start.x < end.x) 1 else -1; val sy = if (start.y < end.y) 1 else -1
    var error = dx + dy; val points = mutableListOf<Point>()
    while (true) { points += Point(x, y); if (x == end.x && y == end.y) return points; val doubled = 2 * error; if (doubled >= dy) { error += dy; x += sx }; if (doubled <= dx) { error += dx; y += sy } }
}
fun expandSquare(point: Point, width: Int): List<Point> { val low = -((width - 1) / 2); return (low until low + width).flatMap { y -> (low until low + width).map { Point(point.x + it, point.y + y) } } }
fun circlePoints(radius: Int): Set<Point> {
    val result = mutableSetOf<Point>(); var a = radius; var b = 0; var error = 1 - radius
    while (a >= b) { result += listOf(Point(a, b), Point(b, a), Point(-b, a), Point(-a, b), Point(-a, -b), Point(-b, -a), Point(b, -a), Point(a, -b)); b++; if (error < 0) error += 2 * b + 1 else { a--; error += 2 * (b - a) + 1 } }
    return result
}
fun ellipsePoints(rx: Int, ry: Int): Set<Point> {
    val rx2 = rx * rx; val ry2 = ry * ry; var x = 0; var y = ry
    val points = mutableSetOf(Point(0, ry), Point(0, -ry))
    fun addQuadrants() { points += listOf(Point(x, y), Point(-x, y), Point(x, -y), Point(-x, -y)) }
    while (ry2 * x < rx2 * y) { val decision = 4 * ry2 * (x + 1) * (x + 1) + rx2 * (2 * y - 1) * (2 * y - 1) - 4 * rx2 * ry2; x++; if (decision >= 0) y--; addQuadrants() }
    while (y > 0) { val decision = ry2 * (2 * x + 1) * (2 * x + 1) + 4 * rx2 * (y - 1) * (y - 1) - 4 * rx2 * ry2; y--; if (decision <= 0) x++; addQuadrants() }
    return points
}
fun bezierPoints(controls: List<Point>, segments: Int): List<Point> {
    val degree = controls.size - 1; val scale = if (degree == 2) segments * segments else segments * segments * segments
    return (0..segments).map { index -> val rest = segments - index; val weights = if (degree == 2) listOf(rest * rest, 2 * index * rest, index * index) else listOf(rest * rest * rest, 3 * index * rest * rest, 3 * index * index * rest, index * index * index); Point(roundRatio(weights.indices.sumOf { weights[it] * controls[it].x }, scale), roundRatio(weights.indices.sumOf { weights[it] * controls[it].y }, scale)) }
}
