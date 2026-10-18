import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val n = 5
    for (row in 1 until 2 * n) {
        val i = if (row <= n) row else 2 * n - row
        println(" ".repeat(n - i) + "*".repeat(2 * i - 1))
    }
}
