fun main() {
    val rows = listOf("800025000", "070080005", "260400070", "000001900", "010000040",
        "600200000", "900010000", "700000004", "020000036")
    val board = Array(9) { r -> IntArray(9) { c -> rows[r][c] - '0' } }
    var placements = 0L
    fun solve(): Boolean {
        for (r in 0 until 9) {
            for (c in 0 until 9) {
                if (board[r][c] != 0) continue
                for (digit in 1..9) {
                    val valid = (0 until 9).all { i ->
                        board[r][i] != digit && board[i][c] != digit &&
                            board[r / 3 * 3 + i / 3][c / 3 * 3 + i % 3] != digit
                    }
                    if (!valid) continue
                    board[r][c] = digit
                    placements++
                    if (solve()) return true
                    board[r][c] = 0
                }
                return false
            }
        }
        return true
    }
    solve()
    for (row in board) println(row.joinToString(" "))
    println("placements: $placements")
}
