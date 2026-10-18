fun main() {
    var firstEight = IntArray(8)
    for (n in 4..8) {
        val positions = IntArray(n)
        val first = IntArray(n)
        var found = false
        fun queens(row: Int): Int {
            if (row == positions.size) {
                if (!found) positions.copyInto(first)
                found = true
                return 1
            }
            var count = 0
            for (column in positions.indices) {
                val safe = (0 until row).all { previous ->
                    positions[previous] != column && kotlin.math.abs(positions[previous] - column) != row - previous
                }
                if (safe) {
                    positions[row] = column
                    count += queens(row + 1)
                }
            }
            return count
        }
        val solutions = queens(0)
        println("N=$n: $solutions solutions")
        if (n == 8) firstEight = first
    }
    for (column in firstEight) println(".".repeat(column) + "Q" + ".".repeat(7 - column))
}
