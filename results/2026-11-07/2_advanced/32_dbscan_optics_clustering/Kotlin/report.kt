import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import kotlin.math.abs
import kotlin.math.sqrt

object Report {
    fun gcd(a: Long, b: Long): Long {
        var first = abs(a);
        var second = b;
        while (second != 0L) {
            val old = second;
            second = first % second;
            first = old
        };
        return first
    }
    fun fraction(numerator: Long, denominator: Long): String {
        val divisor = gcd(numerator, denominator);
        return "${numerator / divisor}/${denominator / divisor}"
    }
    fun fraction(numerator: Int, denominator: Int): String = fraction(numerator.toLong(), denominator.toLong())
    fun root(value: Int): String = if (value == Optics.INF) "-" else String.format(Locale.ROOT, "%.3f", sqrt(value.toDouble()))
    fun ari(numerator: Long, denominator: Long): String {
        var value = String.format(Locale.ROOT, "%.4f", numerator.toDouble() / denominator);
        if (value == "-0.0000") value = "0.0000";
        return "${fraction(numerator, denominator)} $value"
    }
    fun framed(rows: List<String>, width: Int): List<String> {
        val border = "+" + "-".repeat(width) + "+";
        return listOf(border) + rows.map {
            "|$it|"
        }
        + border
    }
    fun write(name: String, lines: List<String>) {
        Files.writeString(Path.of("output", name), if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
    }
}
