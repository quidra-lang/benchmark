import kotlin.math.abs

fun envelope(samples: List<Long>, attack: Long, release: Long): List<Long> {
    var level = 0L
    return samples.map { value -> val magnitude = minOf(abs(value), 32767L); val coefficient = if (magnitude > level) attack else release; level += rdiv((magnitude - level) * coefficient, 32768L); level }
}
fun normalize(samples: List<Long>, target: Long): Pair<List<Long>, Long> { val sourcePeak = peak(samples); return (if (sourcePeak == 0L) samples.toList() else samples.map { rdiv(it * target, sourcePeak) }) to sourcePeak }
fun gate(samples: List<Long>, threshold: Long, hold: Int): Pair<List<Long>, Long> {
    var lastLoud = -1
    var muted = 0L
    val output = samples.mapIndexed { index, value -> if (abs(value) >= threshold) lastLoud = index; if (lastLoud >= 0 && index - lastLoud <= hold) value else { muted++; 0L } }
    return output to muted
}
data class Compression(val samples: List<Long>, val minGain: Long, val reduced: Long)
fun compress(samples: List<Long>, threshold: Long, ratioNum: Long, ratioDen: Long, attack: Long, release: Long): Compression {
    val levels = envelope(samples, attack, release)
    var gain = 32768L
    var minGain = gain
    var reduced = 0L
    val output = samples.mapIndexed { index, value ->
        val level = levels[index]
        val target = if (level > threshold) rdiv((threshold + rdiv((level - threshold) * ratioDen, ratioNum)) * 32768L, level) else 32768L
        gain = if (target < gain) target else gain + rdiv((target - gain) * release, 32768L)
        minGain = minOf(minGain, gain)
        if (gain < 32768L) reduced++
        rdiv(value * gain, 32768L)
    }
    return Compression(output, minGain, reduced)
}
