import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val pairs = listOf("kitten" to "sitting", "flaw" to "lawn", "listen" to "silent",
        "intention" to "execution", "algorithm" to "altruistic")
    for ((a,b) in pairs) {
        val dp = Array(a.length + 1) { IntArray(b.length + 1) }
        for (i in 0..a.length) dp[i][0] = i
        for (j in 0..b.length) dp[0][j] = j
        for (i in 1..a.length) {
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                dp[i][j] = minOf(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost)
            }
        }
        println("$a -> $b: ${dp[a.length][b.length]}")
    }
}
