import java.math.BigDecimal
import java.math.RoundingMode

fun fixed(x: Double, places: Int): String = BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString()
fun main() {
    for ((a,b,c) in listOf(Triple(1,-3,-10),Triple(-2,5,4),Triple(3,1,-2),Triple(4,-12,9),Triple(1,2,5),Triple(-2,3,-4))) {
        val d = b * b - 4 * a * c; val prefix = "$a $b $c: "
        if (d > 0) {
            val first = (-b + kotlin.math.sqrt(d.toDouble())) / (2 * a); val second = (-b - kotlin.math.sqrt(d.toDouble())) / (2 * a)
            println(prefix + "x1 = ${fixed(maxOf(first,second),4)}, x2 = ${fixed(minOf(first,second),4)}")
        } else if (d == 0) println(prefix + "x = ${fixed(-b / (2.0 * a),4)}")
        else {
            val p = fixed(-b / (2.0 * a),4); val q = fixed(kotlin.math.sqrt(-d.toDouble()) / (2 * kotlin.math.abs(a)),4)
            println(prefix + "x = $p + ${q}i, $p - ${q}i")
        }
    }
}
