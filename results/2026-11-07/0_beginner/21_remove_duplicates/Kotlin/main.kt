fun main() {
    val values = intArrayOf(12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9)
    val unique = values.distinct()
    println(unique.joinToString(" "))
    println("removed: ${values.size - unique.size}")
}
