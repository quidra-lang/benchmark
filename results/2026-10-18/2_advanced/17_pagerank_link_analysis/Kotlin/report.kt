import java.io.File
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

object Report {
    fun fixed(value: Double, places: Int = 6): String {
        val text = String.format(Locale.ROOT, "%.${places}f", value)
        return if (text.startsWith('-') && text.toDouble() == 0.0) text.substring(1) else text
    }
    fun scaled(value: Double, places: Int = 6) = (value * (if (places == 4) 10000 else 1000000)).roundToLong()
    fun fraction(numerator: Long, denominator: Long): String {
        var first = abs(numerator)
        var second = denominator
        while (second != 0L) { val remainder = first % second; first = second; second = remainder }
        val a = numerator / first
        val b = denominator / first
        return "$a/$b ${fixed(a.toDouble() / b, 4)}"
    }
    fun fraction(numerator: Int, denominator: Int) = fraction(numerator.toLong(), denominator.toLong())
    fun write(files: Map<String, List<String>>) {
        File("output").mkdirs()
        for ((name, lines) in files) File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
    }
}
