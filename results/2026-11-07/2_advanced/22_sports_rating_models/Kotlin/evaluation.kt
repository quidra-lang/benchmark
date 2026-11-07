import kotlin.math.exp
import kotlin.math.ln

data class Link(val alpha: Double, val beta: Double)
object Evaluation {
    fun sigma(value: Double) = 1 / (1 + exp(-value))
    fun fitLink(features: DoubleArray, matches: List<Match>, iterations: Long): Link {
        var alpha = 0.0
        var beta = 0.0
        for (iteration in 0L until iterations) {
            var g0 = 0.0
            var g1 = 0.0
            var h00 = 0.0
            var h01 = 0.0
            var h11 = 0.0
            for (i in features.indices) {
                val z = features[i]
                val p = sigma(alpha + beta * z)
                val w = p * (1 - p)
                val delta = matches[i].result - p
                g0 += delta; g1 += delta * z; h00 += w; h01 += w * z; h11 += w * z * z
            }
            val determinant = h00 * h11 - h01 * h01
            val nextAlpha = alpha + (h11 * g0 - h01 * g1) / determinant
            val nextBeta = beta + (h00 * g1 - h01 * g0) / determinant
            alpha = nextAlpha
            beta = nextBeta
        }
        return Link(alpha, beta)
    }
    fun logLoss(p: Double, resultTwice: Int) = when (resultTwice) { 2 -> -ln(p); 0 -> -ln(1 - p); else -> -(ln(p) / 2 + ln(1 - p) / 2) }
    fun brier(p: Double, resultTwice: Int): Double { val difference = p - resultTwice / 2.0; return difference * difference }
    fun correctnessTwice(p: Double, resultTwice: Int) = when { resultTwice == 1 -> 1; p > 0.5 && resultTwice == 2 || p < 0.5 && resultTwice == 0 -> 2; else -> 0 }
    private fun averageRanksTwice(values: Array<Fraction>) = IntArray(values.size) { i -> 2 * values.count { it > values[i] } + values.count { it.compareTo(values[i]) == 0 } + 1 }
    fun kendall(first: Array<Fraction>, second: Array<Fraction>): Fraction {
        val count = first.size
        var concordant = 0
        var discordant = 0
        for (t in 0 until count) for (u in t + 1 until count) {
            val a = first[t].compareTo(first[u]).compareTo(0)
            val b = second[t].compareTo(second[u]).compareTo(0)
            if (a * b > 0) concordant++ else if (a * b < 0) discordant++
        }
        return Fraction(concordant - discordant, count * (count - 1) / 2)
    }
    fun spearman(first: Array<Fraction>, second: Array<Fraction>): Fraction {
        val count = first.size
        val a = averageRanksTwice(first)
        val b = averageRanksTwice(second)
        var squares = 0L
        for (i in 0 until count) { val difference = (a[i] - b[i]).toLong(); squares += difference * difference }
        return Fraction(1).subtract(Fraction(6 * squares, 4L * count * (count * count - 1)))
    }
}
