import java.util.Locale

data class Point(val x: Int, val y: Int)
fun cross(o: Point, a: Point, b: Point): Int =
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
fun chain(points: List<Point>): MutableList<Point> {
    val result = mutableListOf<Point>()
    for (point in points) {
        while (result.size >= 2 && cross(result[result.size - 2],result.last(),point) <= 0) {
            result.removeLast()
        }
        result.add(point)
    }
    return result
}
fun main() {
    val points = listOf(Point(3,2),
        Point(-6,1),
        Point(8,4),
        Point(0,0),
        Point(-3,7),
        Point(4,-3),
        Point(1,-5),
        Point(-2,1),
        Point(5,6),
        Point(-6,-2),
        Point(2,-2),
        Point(7,-1),
        Point(-3,4),
        Point(2,8),
        Point(-6,3)).sortedWith(compareBy<Point> { it.x }.thenBy { it.y })
    val lower = chain(points)
    val upper = chain(points.reversed())
    lower.removeLast()
    upper.removeLast()
    lower.addAll(upper)
    var crossSum = 0
    println("hull: ${lower.size} points")
    for (i in lower.indices) {
        val a = lower[i]
        val b = lower[(i + 1) % lower.size]
        println("(${a.x}, ${a.y})")
        crossSum += a.x * b.y - b.x * a.y
    }
    println("area: %.1f".format(Locale.ROOT, crossSum / 2.0))
}
