import java.math.BigDecimal
import java.math.RoundingMode

fun mergeSort(values: IntArray, l: Int, r: Int): Int {
    if (l == r) return 0
    val m = (l + r) / 2
    var inversions = mergeSort(values,l,m)
    inversions += mergeSort(values,m + 1,r)
    val merged = mutableListOf<Int>()
    var i = l
    var j = m + 1
    while (i <= m && j <= r) {
        if (values[i] < values[j]) merged.add(values[i++])
        else {
            merged.add(values[j++])
            inversions += m - i + 1
        }
    }
    while (i <= m) merged.add(values[i++])
    while (j <= r) merged.add(values[j++])
    for (k in merged.indices) values[l + k] = merged[k]
    println("merge [$l..$r]: ${merged.joinToString(" ")}")
    return inversions
}
fun main() {
    val values = intArrayOf(47,12,85,33,6,71,29,58,90,14)
    val inversions = mergeSort(values,0,values.lastIndex)
    println("sorted: ${values.joinToString(" ")}")
    println("inversions: $inversions")
}
