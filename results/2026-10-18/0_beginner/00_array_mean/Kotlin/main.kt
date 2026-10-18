import java.math.BigDecimal
import java.math.RoundingMode

fun main() {
    val values = intArrayOf(48, 73, 56, 91, 35, 62, 84)
    val mean = values.sum().toDouble() / values.size
    println(BigDecimal.valueOf(mean).setScale(2, RoundingMode.HALF_UP).toPlainString())
}
