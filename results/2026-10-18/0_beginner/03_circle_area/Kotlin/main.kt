import java.util.Locale

fun main() {
    val radii = intArrayOf(3, 7, 12, 25, 41)
    val pi = 3.141592653589793
    for (radius in radii) {
        val area = pi * radius * radius
        val circumference = 2 * pi * radius
        println("r=%d area=%.3f circumference=%.3f".format(Locale.ROOT, radius, area, circumference))
    }
}
