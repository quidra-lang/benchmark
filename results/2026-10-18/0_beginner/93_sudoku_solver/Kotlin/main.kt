import java.math.BigDecimal
import java.math.RoundingMode

fun solve(board: Array<IntArray>, placements: LongArray): Boolean {
    for (r in 0 until 9) {
        for (c in 0 until 9) {
            if (board[r][c] != 0) continue
            for (digit in 1..9) {
                var valid = true
                for (i in 0 until 9) {
                    if (board[r][i] == digit || board[i][c] == digit ||
                        board[r / 3 * 3 + i / 3][c / 3 * 3 + i % 3] == digit) valid = false
                }
                if (!valid) continue
                board[r][c] = digit
                placements[0]++
                if (solve(board,placements)) return true
                board[r][c] = 0
            }
            return false
        }
    }
    return true
}
fun main() {
    val rows = listOf("800025000", "070080005", "260400070", "000001900", "010000040",
        "600200000", "900010000", "700000004", "020000036")
    val board = Array(9) { r -> IntArray(9) { c -> rows[r][c] - '0' } }
    val placements = longArrayOf(0)
    solve(board,placements)
    for (row in board) println(row.joinToString(" "))
    println("placements: ${placements[0]}")
}
