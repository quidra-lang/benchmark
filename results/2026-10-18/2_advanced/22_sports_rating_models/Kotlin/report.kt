import java.io.File
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

class Fraction(originalNumerator: Long, originalDenominator: Long = 1) : Comparable<Fraction> {
    val numerator: Long
    val denominator: Long
    constructor(numerator: Int, denominator: Int = 1) : this(numerator.toLong(), denominator.toLong())
    constructor(numerator: Long, denominator: Int) : this(numerator, denominator.toLong())
    init {
        var n = originalNumerator
        var d = originalDenominator
        if (d < 0) { n = -n; d = -d }
        var first = abs(n)
        var second = d
        while (second != 0L) { val remainder = first % second; first = second; second = remainder }
        numerator = n / first
        denominator = d / first
    }
    fun add(other: Fraction) = Fraction(numerator * other.denominator + other.numerator * denominator, denominator * other.denominator)
    fun subtract(other: Fraction) = Fraction(numerator * other.denominator - other.numerator * denominator, denominator * other.denominator)
    fun multiply(value: Int) = Fraction(numerator * value, denominator)
    fun divide(value: Int) = Fraction(numerator, denominator * value)
    fun real() = numerator.toDouble() / denominator
    override fun compareTo(other: Fraction) = (numerator * other.denominator).compareTo(other.numerator * denominator)
    override fun toString() = "$numerator/$denominator"
}
object Report {
    private fun scale(places: Int): Long { var scale = 1L; repeat(places) { scale *= 10 }; return scale }
    fun comparison(value: Double, places: Int): Fraction { val scale = scale(places); return Fraction((value * scale).roundToLong(), scale) }
    fun fixed(value: Double, places: Int = 4): String {
        val text = String.format(Locale.ROOT, "%.${places}f", value)
        return if (text.startsWith('-') && text.toDouble() == 0.0) text.substring(1) else text
    }
    fun fixed(value: Fraction): String {
        val magnitude = abs(value.numerator)
        var whole = magnitude / value.denominator
        var remainder = magnitude % value.denominator
        var decimals = 0L
        repeat(4) {
            remainder *= 10
            decimals = decimals * 10 + remainder / value.denominator
            remainder %= value.denominator
        }
        if (2 * remainder >= value.denominator) decimals++
        if (decimals == 10000L) { whole++; decimals = 0 }
        val sign = if (value.numerator < 0 && (whole != 0L || decimals != 0L)) "-" else ""
        return sign + whole + "." + decimals.toString().padStart(4, '0')
    }
    fun fractionWithReal(value: Fraction) = "$value ${fixed(value)}"
    fun write(name: String, lines: List<String>) = File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
}
