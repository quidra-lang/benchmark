import java.util.Locale

fun main() {
    var state = 42L
    val free = IntArray(2)
    var arrival = 0
    var totalWait = 0
    var maxWait = 0
    for (customer in 1..20) {
        state = state * 48271 % 2147483647
        arrival += (state % 5).toInt() + 1
        state = state * 48271 % 2147483647
        val service = (state % 7).toInt() + 2
        val teller = if (free[0] <= free[1]) 0 else 1
        val start = maxOf(arrival, free[teller])
        val end = start + service
        val wait = start - arrival
        free[teller] = end
        totalWait += wait
        maxWait = maxOf(maxWait, wait)
        println("customer $customer: arrive=$arrival start=$start end=$end teller=${teller + 1} wait=$wait")
    }
    println("average wait: %.2f".format(Locale.ROOT, totalWait / 20.0))
    println("max wait: $maxWait")
    println("last departure: ${free.max()}")
}
