fun main() {
    val arrays = listOf(
        listOf(3, -5, 8, -2, 6, -9, 4, 1, -7, 5, -3, 2),
        listOf(-4, 7, -1, 3, -8, 10, -2, 5, -6, -2, 9, -12, 4, -1),
        listOf(-6, -3, 5, -1, -4, 3, -9, 2, 3, -1, 4, -5, 1, 6, -2),
    )
    for (values in arrays) {
        var current = values[0]
        var best = current
        var start = 0
        var bestStart = 0
        var bestEnd = 0
        for (i in 1 until values.size) {
            if (current < 0) {
                current = values[i]
                start = i
            } else {
                current += values[i]
            }
            if (current > best) {
                best = current
                bestStart = start
                bestEnd = i
            }
        }
        println("max sum $best at [$bestStart, $bestEnd]")
    }
}
