fun main() {
    val prime = BooleanArray(201) { true }
    prime[0] = false
    prime[1] = false
    for (p in 2..200)
        if (prime[p])
            for (m in 2 * p..200 step p) prime[m] = false
    val primes = (2..200).filter { prime[it] }
    println("count: ${primes.size}")
    for (row in primes.chunked(10)) println(row.joinToString(" "))
}
