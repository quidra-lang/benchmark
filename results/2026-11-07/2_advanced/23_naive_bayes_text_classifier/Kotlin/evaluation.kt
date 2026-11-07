import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

fun realText(value: Double): String {
    val text = String.format(Locale.ROOT, "%.4f", value)
    return if (text == "-0.0000") "0.0000" else text
}

fun rounded(value: Double): Long = (value * 10000).roundToLong()
fun proportionText(numerator: Long, denominator: Long): String = "$numerator/$denominator ${realText(numerator.toDouble() / denominator)}"
fun proportionText(numerator: Int, denominator: Int): String = proportionText(numerator.toLong(), denominator.toLong())

fun fractionText(numerator: Long, denominator: Long): String {
    if (denominator == 0L) return "- -"
    var a = abs(numerator)
    var b = denominator
    while (b != 0L) { val remainder = a % b; a = b; b = remainder }
    return proportionText(numerator / a, denominator / a)
}

class Evaluation(classes: Int, truths: IntArray, predictions: IntArray) {
    val matrix = Array(classes) { IntArray(classes) }
    val total = truths.size
    val correct: Int
    val microF1: Double
    val macroF1: Double

    init {
        for (i in truths.indices) matrix[truths[i]][predictions[i]]++
        var hits = 0
        var sum = 0.0
        var scored = 0
        for (c in 0 until classes) {
            hits += matrix[c][c]
            val denominator = predictedCount(c) + support(c)
            if (denominator > 0) { sum += (2 * matrix[c][c]).toDouble() / denominator; scored++ }
        }
        correct = hits
        microF1 = correct.toDouble() / total
        macroF1 = sum / scored
    }

    private fun support(label: Int): Int = matrix[label].sum()
    private fun predictedCount(label: Int): Int = matrix.sumOf { it[label] }

    fun lines(names: List<String>): List<String> {
        val lines = mutableListOf("true\\predicted " + names.joinToString(" "))
        for (c in names.indices) lines.add(names[c] + " " + matrix[c].joinToString(" "))
        for (c in names.indices) {
            val hits = matrix[c][c].toLong()
            val predicted = predictedCount(c).toLong()
            val support = support(c).toLong()
            lines.add("class ${names[c]} precision ${fractionText(hits, predicted)} recall ${fractionText(hits, support)} f1 ${fractionText(2 * hits, predicted + support)} support $support")
        }
        lines.add("micro_f1 ${realText(microF1)} macro_f1 ${realText(macroF1)}")
        return lines
    }
}
