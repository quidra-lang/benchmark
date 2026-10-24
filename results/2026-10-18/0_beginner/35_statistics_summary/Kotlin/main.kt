import java.util.Locale

fun main() {
    val values = intArrayOf(72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71)
    val mean = values.average()
    var squared = 0.0
    for (value in values) {
        val difference = value - mean
        squared += difference * difference
    }
    val sorted = values.sorted()
    val counts = values.toList().groupingBy { it }.eachCount()
    val mode = counts.keys.minWith(compareByDescending<Int> { counts[it]!! }.thenBy { it })
    println("mean: %.3f".format(Locale.ROOT, mean))
    println("median: ${sorted[values.size / 2]}")
    println("mode: $mode")
    println("range: ${sorted.last() - sorted.first()}")
    println("stdev: %.3f".format(Locale.ROOT, kotlin.math.sqrt(squared / values.size)))
}
