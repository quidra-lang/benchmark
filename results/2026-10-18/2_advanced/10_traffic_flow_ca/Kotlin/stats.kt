fun gcd(first: Long, second: Long): Long { var a = first; var b = second; while (b != 0L) { val remainder = a % b; a = b; b = remainder }; return a }
fun decimal(numerator: Number, denominator: Number, places: Int): String {
    val a = numerator.toLong(); val b = denominator.toLong()
    if (b == 0L) return "-"
    var scale = 1L
    repeat(places) { scale *= 10L }
    val value = (2L * a * scale + b) / (2L * b)
    return "${value / scale}.${(value % scale).toString().padStart(places, '0')}"
}
fun fraction(numerator: Number, denominator: Number): String { val a = numerator.toLong(); val b = denominator.toLong(); if (b == 0L) return "-"; val divisor = gcd(a, b); return "${a / divisor}/${b / divisor}" }
fun percentile(times: List<Int>, q: Int): Int = times[(q * times.size + 99) / 100 - 1]
fun histogram(times: List<Int>, width: Long): List<String> {
    val first = times.first() / width
    val counts = IntArray((times.last() / width - first + 1).toInt())
    times.forEach { counts[(it / width - first).toInt()]++ }
    val maximum = counts.max()
    return counts.mapIndexed { index, count -> val low = (first + index) * width; val stars = (80 * count + maximum) / (2 * maximum); "  $low-${low + width - 1} $count" + if (stars == 0) "" else " " + "*".repeat(stars) }
}
