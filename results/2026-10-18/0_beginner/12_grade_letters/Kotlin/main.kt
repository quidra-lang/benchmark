fun main() {
    val grades = listOf("A", "B", "C", "D", "F")
    val counts = IntArray(5)
    for (score in intArrayOf(78, 90, 100, 59, 80, 85, 89, 70, 45, 93)) {
        val index = when {
            score >= 90 -> 0
            score >= 80 -> 1
            score >= 70 -> 2
            score >= 60 -> 3
            else -> 4
        }
        counts[index]++
        println("$score: ${grades[index]}")
    }
    for (i in grades.indices) println("${grades[i]}: ${counts[i]}")
}
