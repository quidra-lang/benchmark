import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for (start in longArrayOf(1,6,27,97,871)) {
        var n = start; var maximum = n; var steps = 0
        while (n != 1L) { n = if (n % 2 == 0L) n / 2 else 3 * n + 1; steps++; maximum = maxOf(maximum, n) }
        println("$start: steps=$steps max=$maximum")
    }
}
