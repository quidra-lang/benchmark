import java.io.File
import java.util.Locale
import kotlin.math.abs

object Report {
    fun real(value: Double): String {
        val text = String.format(Locale.ROOT, "%.4f", value)
        return if (text == "-0.0000") "0.0000" else text
    }
    fun reals(values: DoubleArray) = values.joinToString(" ") { real(it) }
    fun fourDecimal(value: Double) = real(value).toDouble()
    fun amount(cents: Long): String {
        val absolute = abs(cents)
        return (if (cents < 0) "-" else "") + (absolute / 100) + "." + (absolute % 100).toString().padStart(2, '0')
    }
    fun amount(cents: Int) = amount(cents.toLong())
    fun writeFiles(files: Map<String, List<String>>) {
        File("output").mkdirs()
        for ((name, lines) in files) File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
    }
}
