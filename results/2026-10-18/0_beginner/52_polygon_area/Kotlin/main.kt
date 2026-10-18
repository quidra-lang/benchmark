import java.math.BigDecimal
import java.math.RoundingMode

fun fixed(x: Double, places: Int): String = BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString()
fun main() {
    val polygons = listOf(listOf(0 to 0,5 to 0,6 to 4,1 to 3),listOf(2 to 1,0 to 4,3 to 7,7 to 6,8 to 2),listOf(0 to 0,8 to 0,8 to 6,5 to 6,4 to 3,3 to 6,0 to 6))
    for ((k,vertices) in polygons.withIndex()) {
        var cross = 0; var perimeter = 0.0
        for (i in vertices.indices) { val (x,y) = vertices[i]; val (nx,ny) = vertices[(i + 1) % vertices.size]; cross += x * ny - nx * y; val dx = x - nx; val dy = y - ny; perimeter += kotlin.math.sqrt((dx * dx + dy * dy).toDouble()) }
        println("polygon ${k + 1}: area=${fixed(kotlin.math.abs(cross) / 2.0,1)} perimeter=${fixed(perimeter,3)}")
    }
}
