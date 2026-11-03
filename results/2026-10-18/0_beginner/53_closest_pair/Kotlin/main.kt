import java.util.Locale
import kotlin.math.sqrt

fun main() {
    val points = listOf(
        12 to -7, -33 to 25, 41 to 18, -8 to -44, 27 to 39, -46 to -12, 5 to 14, 36 to -29,
        -19 to 47, -2 to 3,
    )
    var minimum = Int.MAX_VALUE
    var maximum = -1
    var minI = 0
    var minJ = 0
    var maxI = 0
    var maxJ = 0
    for (i in points.indices) {
        for (j in i + 1 until points.size) {
            val dx = points[i].first - points[j].first
            val dy = points[i].second - points[j].second
            val distance = dx * dx + dy * dy
            if (distance < minimum) {
                minimum = distance
                minI = i
                minJ = j
            }
            if (distance > maximum) {
                maximum = distance
                maxI = i
                maxJ = j
            }
        }
    }
    println("closest: P%d P%d %.4f".format(Locale.ROOT, minI, minJ, sqrt(minimum.toDouble())))
    println("farthest: P%d P%d %.4f".format(Locale.ROOT, maxI, maxJ, sqrt(maximum.toDouble())))
}
