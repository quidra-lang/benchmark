fun energy(samples: List<Long>) = samples.sumOf { it * it }
fun integerSqrt(value: Long): Long {
    var low = 0L
    var high = value + 1L
    while (high - low > 1L) { val middle = (low + high) / 2L; if (middle <= value / middle) low = middle else high = middle }
    return low
}
fun rms(samples: List<Long>) = integerSqrt(energy(samples) / samples.size.toLong())
fun zeroCrossings(samples: List<Long>) = samples.zipWithNext().count { (first, second) -> (first < 0L) != (second < 0L) }.toLong()
fun countClipped(samples: List<Long>) = samples.count { it == -32768L || it == 32767L }.toLong()
fun crestFraction(samples: List<Long>): String {
    val denominator = energy(samples)
    if (denominator == 0L) return "none"
    val numerator = peak(samples) * peak(samples) * samples.size.toLong()
    var first = numerator
    var second = denominator
    while (second != 0L) { val remainder = first % second; first = second; second = remainder }
    return "${numerator / first}/${denominator / first}"
}
fun autocorrelation(samples: List<Long>, lag: Int): Long { var total = 0L; for (index in 0 until samples.size - lag) total += samples[index] * samples[index + lag]; return total }
fun pitchLag(samples: List<Long>, low: Int, high: Int): Int? {
    var lag = low
    var value = autocorrelation(samples, low)
    for (candidate in low + 1..high) { val correlation = autocorrelation(samples, candidate); if (correlation > value) { lag = candidate; value = correlation } }
    return if (value > 0L) lag else null
}
