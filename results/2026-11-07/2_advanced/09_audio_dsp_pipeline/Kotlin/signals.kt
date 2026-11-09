import java.io.File
import kotlin.math.abs

class AudioSignal(val name: String, val rate: Long, val samples: List<Long>, val origin: String = "input", val ingredients: List<AudioSignal> = emptyList())
data class ClipResult(val samples: List<Long>, val clipped: Long)
class ClipCounter {
    var count = 0L
    fun saturate(value: Long): Long { val limited = value.coerceIn(-32768L, 32767L); if (limited != value) count++; return limited }
}
fun floorDivide(numerator: Long, denominator: Long) = Math.floorDiv(numerator, denominator)
fun rdiv(numerator: Long, denominator: Long) = floorDivide(2L * numerator + denominator, 2L * denominator)
fun peak(samples: List<Long>) = samples.maxOf { abs(it) }
fun readSignals(): List<AudioSignal> {
    val lines = File("input/signals.txt").readLines()
    val result = mutableListOf<AudioSignal>()
    var index = 0
    while (index < lines.size) {
        val header = lines[index++].split(' ')
        val count = header[3].toInt()
        val samples = mutableListOf<Long>()
        while (samples.size < count) samples += lines[index++].split(' ').map(String::toLong)
        result += AudioSignal(header[1], header[2].toLong(), samples)
    }
    return result
}
fun formatSignal(signal: AudioSignal) = listOf("SIGNAL ${signal.name} ${signal.rate} ${signal.samples.size}") + signal.samples.chunked(16).map { it.joinToString(" ") }
fun impulse(count: Int, position: Int, amplitude: Long) = List(count) { if (it == position) amplitude else 0L }
fun step(count: Int, position: Int, amplitude: Long) = List(count) { if (it >= position) amplitude else 0L }
fun noise(count: Int, seed: Long): List<Long> { var state = seed; return List(count) { state = 48271L * state % 2147483647L; state % 65536L - 32768L } }
