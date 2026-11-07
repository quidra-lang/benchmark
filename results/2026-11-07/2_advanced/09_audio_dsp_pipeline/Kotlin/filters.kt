fun fir(samples: List<Long>, divisor: Long, taps: List<Long>): ClipResult {
    val counter = ClipCounter()
    val output = samples.indices.map { index -> var total = 0L; for (tap in 0 until minOf(taps.size, index + 1)) total += taps[tap] * samples[index - tap]; counter.saturate(floorDivide(total, divisor)) }
    return ClipResult(output, counter.count)
}
fun biquad(samples: List<Long>, sections: List<List<Long>>): ClipResult {
    val counter = ClipCounter()
    var current = samples
    for (section in sections) {
        val output = mutableListOf<Long>()
        var u1 = 0L
        var u2 = 0L
        var v1 = 0L
        var v2 = 0L
        for (input in current) {
            val value = counter.saturate(floorDivide(section[0] * input + section[1] * u1 + section[2] * u2 - section[3] * v1 - section[4] * v2, 16384L))
            output += value
            u2 = u1; u1 = input; v2 = v1; v1 = value
        }
        current = output
    }
    return ClipResult(current, counter.count)
}
fun movingAverage(samples: List<Long>, width: Int): List<Long> {
    var total = 0L
    return samples.mapIndexed { index, value -> total += value; if (index >= width) total -= samples[index - width]; rdiv(total, width.toLong()) }
}
fun dcBlock(samples: List<Long>, numerator: Long, denominator: Long): ClipResult {
    val counter = ClipCounter()
    var previousInput = 0L
    var previousOutput = 0L
    val output = samples.map { value -> previousOutput = counter.saturate(value - previousInput + rdiv(numerator * previousOutput, denominator)); previousInput = value; previousOutput }
    return ClipResult(output, counter.count)
}
