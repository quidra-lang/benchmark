import java.math.BigDecimal
import java.math.RoundingMode

fun fixed(x: Double, places: Int): String = BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString()
fun main() {
    val values = intArrayOf(72,85,64,90,85,58,77,85,69,93,71)
    val mean = values.sum().toDouble() / values.size; var squared = 0.0
    for (value in values) { val difference = value - mean; squared += difference * difference }
    val sorted = values.sorted(); val counts = values.toList().groupingBy { it }.eachCount()
    val mode = counts.keys.sortedWith(compareByDescending<Int> { counts[it]!! }.thenBy { it }).first()
    println("mean: ${fixed(mean, 3)}")
    println("median: ${sorted[values.size / 2]}")
    println("mode: $mode")
    println("range: ${sorted.last() - sorted.first()}")
    println("stdev: ${fixed(kotlin.math.sqrt(squared / values.size), 3)}")
}
