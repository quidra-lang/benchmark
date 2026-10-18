import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val a = arrayOf(intArrayOf(3,-2,5,1), intArrayOf(-4,7,0,6), intArrayOf(2,9,-8,-3))
    val b = arrayOf(intArrayOf(1,4), intArrayOf(-5,2), intArrayOf(6,-1), intArrayOf(0,7))
    for (i in 0 until 3) {
        val row = (0 until 2).map { j -> (0 until 4).sumOf { k -> a[i][k] * b[k][j] } }
        println(row.joinToString("") { it.toString().padStart(5) })
    }
}
