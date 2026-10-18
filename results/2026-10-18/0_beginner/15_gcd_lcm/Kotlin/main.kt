import java.math.BigDecimal
import java.math.RoundingMode

fun gcd(a: Int, b: Int): Int { var x = a; var y = b; while (y != 0) { val r = x % y; x = y; y = r }; return x }
fun main() {
    for ((a, b) in listOf(48 to 180, 1071 to 462, 7 to 91, 13 to 97, 36288 to 98280)) {
        val g = gcd(a, b)
        println("gcd($a, $b) = $g, lcm($a, $b) = ${a / g * b}")
    }
}
