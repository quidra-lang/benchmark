import java.util.Locale

fun main() {
    for (n in longArrayOf(0, 7, 999, 1000, -456789, 3141592, 9876543210)) {
        println("%,d".format(Locale.US, n))
    }
}
