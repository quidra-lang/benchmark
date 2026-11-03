import java.io.File
import java.util.Locale
import kotlin.math.floor

object Report {
    fun real(value: Double): String {
        val text = String.format(Locale.ROOT, "%.4f", value)
        return if (text == "-0.0000") "0.0000" else text
    }
    fun pValue(numerator: Long, denominator: Long): String {
        val (first, second) = Tests.reducedFraction(numerator, denominator)
        return "$first/$second ${real(first.toDouble() / second)}"
    }
    fun pValue(numerator: Int, denominator: Int): String = pValue(numerator.toLong(), denominator.toLong())
    fun numberList(numbers: List<Int>): String = if (numbers.isEmpty()) "none" else numbers.sorted().joinToString(" ")
    fun binNumber(value: Double, low: Double, high: Double, bins: Int): Int = minOf(floor(bins * (value - low) / (high - low)).toInt(), bins - 1) + 1
    fun bar(count: Int, top: Int): String = "#".repeat((40 * count + top - 1) / top)
    fun writeFiles(files: Map<String, List<String>>) {
        File("output").mkdirs()
        for ((name, lines) in files) File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
    }
}
