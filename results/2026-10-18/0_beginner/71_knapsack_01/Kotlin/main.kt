import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val names = listOf("tent", "stove", "lantern", "rope", "camera", "blanket", "water")
    val weights = intArrayOf(10,3,2,3,5,5,6)
    val values = intArrayOf(120,65,45,20,90,85,100)
    val dp = Array(8) { IntArray(21) }
    for (i in 1..7) {
        for (capacity in 0..20) {
            dp[i][capacity] = dp[i - 1][capacity]
            if (weights[i - 1] <= capacity) {
                dp[i][capacity] = maxOf(dp[i][capacity], dp[i - 1][capacity - weights[i - 1]] + values[i - 1])
            }
        }
    }
    val chosen = BooleanArray(7)
    var capacity = 20
    var totalWeight = 0
    for (i in 7 downTo 1) {
        if (dp[i][capacity] != dp[i - 1][capacity]) {
            chosen[i - 1] = true
            capacity -= weights[i - 1]
            totalWeight += weights[i - 1]
        }
    }
    val items = names.filterIndexed { i,_ -> chosen[i] }
    println("max value: ${dp[7][20]}")
    println("total weight: $totalWeight")
    println("items: ${items.joinToString(" ")}")
}
