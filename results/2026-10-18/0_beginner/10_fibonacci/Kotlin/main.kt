import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    var a = 1; var b = 1; var sum = 0
    val terms = mutableListOf<Int>()
    repeat(30) {
        terms.add(a); sum += a
        val next = a + b; a = b; b = next
    }
    println(terms.joinToString(" "))
    println("sum: $sum")
}
