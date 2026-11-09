fun gain(samples: List<Long>, numerator: Long, denominator: Long): ClipResult { val counter = ClipCounter(); return ClipResult(samples.map { counter.saturate(rdiv(it * numerator, denominator)) }, counter.count) }
fun mix(tracks: List<List<Long>>, weights: List<Long>, denominator: Long): ClipResult {
    val counter = ClipCounter()
    val result = List(tracks.maxOf { it.size }) { index -> var total = 0L; for (track in tracks.indices) if (index < tracks[track].size) total += weights[track] * tracks[track][index]; counter.saturate(rdiv(total, denominator)) }
    return ClipResult(result, counter.count)
}
fun delay(samples: List<Long>, count: Int) = List(count) { 0L } + samples
fun echo(samples: List<Long>, delay: Int, numerator: Long, denominator: Long, tail: Int): ClipResult {
    val output = (samples + List(tail) { 0L }).toMutableList()
    val counter = ClipCounter()
    for (index in delay until output.size) output[index] = counter.saturate(output[index] + rdiv(numerator * output[index - delay], denominator))
    return ClipResult(output, counter.count)
}
fun resampledLength(length: Int, oldRate: Long, newRate: Long) = ((length - 1).toLong() * newRate / oldRate + 1L).toInt()
fun resample(samples: List<Long>, oldRate: Long, newRate: Long) = List(resampledLength(samples.size, oldRate, newRate)) { index ->
    val position = (index.toLong() * oldRate / newRate).toInt()
    val fraction = index.toLong() * oldRate % newRate
    samples[position] + if (fraction == 0L) 0L else rdiv((samples[position + 1] - samples[position]) * fraction, newRate)
}
fun fade(samples: List<Long>, fadeIn: Int, fadeOut: Int): List<Long> {
    val output = samples.toMutableList()
    for (index in 0 until fadeIn) output[index] = rdiv(output[index] * index.toLong(), fadeIn.toLong())
    for (index in samples.size - fadeOut until samples.size) output[index] = rdiv(output[index] * (samples.size - 1 - index).toLong(), fadeOut.toLong())
    return output
}
