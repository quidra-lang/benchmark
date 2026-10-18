import java.math.BigDecimal
import java.math.RoundingMode

fun fixed(value: Double): String =
    BigDecimal.valueOf(value).setScale(3, RoundingMode.HALF_UP).toPlainString()

fun main() {
    val radii = intArrayOf(3, 7, 12, 25, 41)
    val pi = 3.141592653589793
    for (radius in radii) {
        val area = pi * radius * radius
        val circumference = 2 * pi * radius
        println("r=$radius area=${fixed(area)} circumference=${fixed(circumference)}")
    }
}
