fun main() {
    val days = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    val counts = intArrayOf(7, 12, 4, 15, 9, 18, 11)
    for (i in days.indices) {
        val count = counts[i]
        println("${days[i]} | ${"*".repeat(count)} $count")
    }
}
