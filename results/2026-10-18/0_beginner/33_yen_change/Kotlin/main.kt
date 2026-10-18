fun main() {
    val denominations = intArrayOf(10000,5000,1000,500,100,50,10,5,1)
    for (amount in intArrayOf(3780,15420,99999,506,48263)) {
        var remaining = amount
        var total = 0
        val parts = mutableListOf<String>()
        for (face in denominations) {
            val count = remaining / face
            remaining %= face
            total += count
            if (count > 0) parts.add("${face}x$count")
        }
        println("$amount yen: ${parts.joinToString(" ")} ($total pieces)")
    }
}
