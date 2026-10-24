import java.util.Locale

fun main() {
    for ((a,b,c) in listOf(Triple(1,-3,-10),Triple(-2,5,4),Triple(3,1,-2),Triple(4,-12,9),Triple(1,2,5),Triple(-2,3,-4))) {
        val d = b * b - 4 * a * c
        val prefix = "$a $b $c: "
        if (d > 0) {
            val first = (-b + kotlin.math.sqrt(d.toDouble())) / (2 * a)
            val second = (-b - kotlin.math.sqrt(d.toDouble())) / (2 * a)
            println((prefix + "x1 = %.4f, x2 = %.4f").format(Locale.ROOT, maxOf(first, second), minOf(first, second)))
        } else if (d == 0) println((prefix + "x = %.4f").format(Locale.ROOT, -b / (2.0 * a)))
        else {
            val p = -b / (2.0 * a)
            val q = kotlin.math.sqrt(-d.toDouble()) / (2 * kotlin.math.abs(a))
            println((prefix + "x = %.4f + %.4fi, %.4f - %.4fi").format(Locale.ROOT, p, q, p, q))
        }
    }
}
