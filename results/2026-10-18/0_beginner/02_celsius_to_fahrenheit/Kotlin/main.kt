import java.math.BigDecimal
import java.math.RoundingMode

fun main() {
    val temperatures = intArrayOf(-40, -15, -3, 0, 22, 37, 100)
    for (celsius in temperatures) {
        val fahrenheit = celsius * 9.0 / 5.0 + 32
        val formatted = BigDecimal.valueOf(fahrenheit).setScale(1, RoundingMode.HALF_UP).toPlainString()
        println("$celsius C = $formatted F")
    }
}
