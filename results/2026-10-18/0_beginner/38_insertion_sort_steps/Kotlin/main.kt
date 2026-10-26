fun main() {
    val values = intArrayOf(52, 17, 38, 9, 61, 38, 24, 45)
    var total = 0
    for (i in 1 until values.size) {
        val value = values[i]
        var j = i - 1
        var shifts = 0
        while (j >= 0 && values[j] > value) {
            values[j + 1] = values[j]
            j--
            shifts++
        }
        values[j + 1] = value
        total += shifts
        println("i=$i shifts=$shifts: ${values.joinToString(" ")}")
    }
    println("total shifts: $total")
}
