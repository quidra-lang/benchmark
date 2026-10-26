fun underThousand(n: Int): String {
    val ones = listOf("zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen")
    val tens = listOf("", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")
    val parts = mutableListOf<String>()
    if (n >= 100) parts.add(ones[n / 100] + " hundred")
    val remainder = n % 100
    if (remainder >= 20) {
        parts.add(tens[remainder / 10] + if (remainder % 10 > 0) "-" + ones[remainder % 10] else "")
    } else if (remainder > 0) {
        parts.add(ones[remainder])
    }
    return parts.joinToString(" ")
}

fun main() {
    for (n in intArrayOf(0, 13, 40, 100, 568, 71000, 300019, 999999)) {
        val parts = mutableListOf<String>()
        if (n == 0) parts.add("zero")
        if (n >= 1000) parts.add(underThousand(n / 1000) + " thousand")
        if (n % 1000 > 0) parts.add(underThousand(n % 1000))
        println("$n: ${parts.joinToString(" ")}")
    }
}
