import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for (seconds in intArrayOf(0, 59, 3725, 45296, 86400, 312047)) {
        val parts = listOf(seconds / 3600, seconds / 60 % 60, seconds % 60)
        println("$seconds seconds = " + parts.joinToString(":") { it.toString().padStart(2, '0') })
    }
}
