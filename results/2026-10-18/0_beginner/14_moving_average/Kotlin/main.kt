import java.util.Locale

fun main() {
    val sales = intArrayOf(120, 135, 98, 143, 160, 152, 171, 149, 188, 176)
    for (i in 2 until sales.size) {
        val average = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0
        println("day %d: %.2f".format(Locale.ROOT, i + 1, average))
    }
}
