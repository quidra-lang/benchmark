import java.util.Locale

fun main() {
    val values = intArrayOf(48, 73, 56, 91, 35, 62, 84)
    println("%.2f".format(Locale.ROOT, values.average()))
}
