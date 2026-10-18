fun main() {
    var state = 12345L
    val counts = IntArray(13)
    repeat(1000) {
        var sum = 0
        repeat(2) {
            state = state * 48271 % 2147483647
            sum += (state % 6).toInt() + 1
        }
        counts[sum]++
    }
    var best = 2
    for (sum in 2..12) {
        println("$sum: ${counts[sum]}")
        if (counts[sum] > counts[best]) best = sum
    }
    println("most frequent: $best")
}
