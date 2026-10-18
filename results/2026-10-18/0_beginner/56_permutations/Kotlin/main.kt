import java.math.BigDecimal
import java.math.RoundingMode

fun permute(prefix: String, used: BooleanArray, count: IntArray) {
    if (prefix.length == 4) { count[0]++; println("${count[0]}: $prefix"); return }
    for (i in 0 until 4) if (!used[i]) { used[i] = true; permute(prefix + "ABCD"[i],used,count); used[i] = false }
}
fun main() {
    permute("", BooleanArray(4), IntArray(1))
}
