import java.math.BigDecimal
import java.math.RoundingMode

fun queens(positions: IntArray, row: Int, first: IntArray, found: BooleanArray): Int {
    if (row == positions.size) {
        if (!found[0]) positions.copyInto(first)
        found[0] = true
        return 1
    }
    var count = 0
    for (column in positions.indices) {
        var safe = true
        for (previous in 0 until row) {
            if (positions[previous] == column || kotlin.math.abs(positions[previous] - column) == row - previous) {
                safe = false
                break
            }
        }
        if (safe) {
            positions[row] = column
            count += queens(positions,row + 1,first,found)
        }
    }
    return count
}
fun main() {
    var firstEight = IntArray(8)
    for (n in 4..8) {
        val positions = IntArray(n)
        val first = IntArray(n)
        val found = booleanArrayOf(false)
        val solutions = queens(positions,0,first,found)
        println("N=$n: $solutions solutions")
        if (n == 8) firstEight = first
    }
    for (column in firstEight) println(".".repeat(column) + "Q" + ".".repeat(7 - column))
}
