import java.io.File
import kotlin.math.abs

object Report {
    fun decimal(value: Rational, digits: Int): String {
        var scale = 1L
        repeat(digits) { scale *= 10 }
        val scaled = (2 * scale * abs(value.numerator) + value.denominator) / (2 * value.denominator)
        val sign = if (value.numerator < 0 && scaled > 0) "-" else ""
        return sign + (scaled / scale) + "." + (scaled % scale).toString().padStart(digits, '0')
    }
    fun hullArea(doubled: Long) = "${doubled / 2}.${if (doubled % 2 == 0L) "0" else "5"}"
    fun write(files: Map<String, List<String>>) {
        File("output").mkdirs()
        for ((name, lines) in files) File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
    }
}
