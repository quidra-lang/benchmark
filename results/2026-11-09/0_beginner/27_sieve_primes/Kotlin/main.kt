fun main() {
    val limit = 200
    val prime = BooleanArray(limit + 1) { true }
    prime[0] = false
    prime[1] = false
    for (p in 2..limit)
        if (prime[p])
            for (m in 2 * p..limit step p) prime[m] = false
    val primes = (2..limit).filter { prime[it] }
    println("count: ${primes.size}")
    for (row in primes.chunked(10)) println(row.joinToString(" "))
}
