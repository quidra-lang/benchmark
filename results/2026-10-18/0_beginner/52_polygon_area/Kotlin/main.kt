import java.util.Locale

fun main() {
    val polygons = listOf(listOf(0 to 0,5 to 0,6 to 4,1 to 3),listOf(2 to 1,0 to 4,3 to 7,7 to 6,8 to 2),listOf(0 to 0,8 to 0,8 to 6,5 to 6,4 to 3,3 to 6,0 to 6))
    for ((k,vertices) in polygons.withIndex()) {
        var cross = 0
        var perimeter = 0.0
        for (i in vertices.indices) {
            val (x,y) = vertices[i]
            val (nx,ny) = vertices[(i + 1) % vertices.size]
            cross += x * ny - nx * y
            val dx = x - nx
            val dy = y - ny
            perimeter += kotlin.math.sqrt((dx * dx + dy * dy).toDouble())
        }
        println("polygon %d: area=%.1f perimeter=%.3f".format(Locale.ROOT, k + 1, kotlin.math.abs(cross) / 2.0, perimeter))
    }
}
