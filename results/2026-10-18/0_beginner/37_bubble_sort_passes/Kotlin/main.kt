fun main() {
    val values = intArrayOf(27, 64, 13, 88, 41, 5, 72, 36)
    var swaps = 0
    for (p in 1..7) {
        var changed = false
        for (j in 0..7 - p) {
            if (values[j] > values[j + 1]) {
                val temp = values[j]
                values[j] = values[j + 1]
                values[j + 1] = temp
                changed = true
                swaps++
            }
        }
        println("pass $p: ${values.joinToString(" ")}")
        if (!changed) break
    }
    println("swaps: $swaps")
}
