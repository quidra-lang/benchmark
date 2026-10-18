import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val grid = listOf(".......","..#....","....#..",".#.....","...#.#.",".......")
    for (obstacles in listOf(false,true)) {
        val dp = Array(6) { IntArray(7) }; dp[0][0] = 1
        for (r in 0 until 6) for (c in 0 until 7) {
            if (obstacles && grid[r][c] == '#') { dp[r][c] = 0; continue }
            if (r > 0) dp[r][c] += dp[r - 1][c]
            if (c > 0) dp[r][c] += dp[r][c - 1]
        }
        println("${if (obstacles) "with" else "without"} obstacles: ${dp[5][6]}")
    }
}
