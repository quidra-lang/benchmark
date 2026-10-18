import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for (n in longArrayOf(0,7,999,1000,-456789,3141592,9876543210)) {
        val groups = kotlin.math.abs(n).toString().reversed().chunked(3).joinToString(",").reversed()
        println((if (n < 0) "-" else "") + groups)
    }
}
