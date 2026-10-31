fun main() {
    val coins = intArrayOf(1, 5, 6, 9)
    for (amount in intArrayOf(8, 11, 15, 22, 33, 40)) {
        val minimum = IntArray(amount + 1) { amount + 1 }
        val ways = IntArray(amount + 1)
        minimum[0] = 0
        ways[0] = 1
        for (value in 1..amount) {
            for (coin in coins) {
                if (coin <= value) minimum[value] = minOf(minimum[value], minimum[value - coin] + 1)
            }
        }
        for (coin in coins) {
            for (value in coin..amount) ways[value] += ways[value - coin]
        }
        var remaining = amount
        var greedy = 0
        for (coin in coins.reversed()) {
            while (remaining >= coin) {
                remaining -= coin
                greedy++
            }
        }
        println("$amount: min=${minimum[amount]} greedy=$greedy ways=${ways[amount]}")
    }
}
