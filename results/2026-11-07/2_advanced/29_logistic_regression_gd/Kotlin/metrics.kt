import java.util.Locale

data class Fraction(val numerator: Long, val denominator: Long) {
    val value get() = numerator.toDouble() / denominator
    override fun toString(): String {
        val divisor = Metrics.gcd(numerator, denominator);
        return "${numerator / divisor}/${denominator / divisor} ${Metrics.ratio(numerator, denominator)}"
    }
}
data class RocPoint(val threshold: Double, val tp: Int, val fp: Int)
data class Confusion(val tp: Int, val fp: Int, val tn: Int, val fn: Int) {
    val correct get() = tp + tn
}
object Metrics {
    fun gcd(a: Long, b: Long): Long {
        var first = a;
        var second = b;
        while (second != 0L) {
            val old = second;
            second = first % second;
            first = old
        };
        return first
    }
    fun fixed(value: Double, places: Int): String {
        val text = String.format(Locale.ROOT, "%.${places}f", value);
        return if (text.startsWith("-") && text.toDouble() == 0.0) text.drop(1) else text
    }
    fun ratio(numerator: Long, denominator: Long): String {
        if (denominator == 0L) return "-";
        val rounded = (20000 * numerator + denominator) / (2 * denominator);
        return "${rounded / 10000}.${(rounded % 10000).toString().padStart(4, '0')}"
    }
    fun ratio(numerator: Int, denominator: Int): String = ratio(numerator.toLong(), denominator.toLong())
    fun confusion(probabilities: DoubleArray, targets: IntArray, threshold: Double): Confusion {
        var tp = 0;
        var fp = 0;
        var tn = 0;
        var fn = 0
        for (i in probabilities.indices) if (probabilities[i] >= threshold) {
            if (targets[i] == 1) tp++ else fp++
        } else if (targets[i] == 0) tn++ else fn++
        return Confusion(tp, fp, tn, fn)
    }
    fun order(scores: DoubleArray, reverse: Boolean): List<Int> = if (reverse) scores.indices.sortedWith(compareByDescending<Int> {
        scores[it]
    }.thenBy {
        it
    }) else scores.indices.sortedWith(compareBy<Int> {
        scores[it]
    }.thenBy {
        it
    })
    fun auc(scores: DoubleArray, targets: IntArray): Fraction {
        val order = order(scores, false);
        val positives = targets.sum();
        var ranks = 0L;
        var start = 0
        while (start < order.size) {
            var end = start;
            while (end + 1 < order.size && scores[order[end + 1]] == scores[order[start]]) end++;
            for (position in start..end) if (targets[order[position]] == 1) ranks += start + end + 2;
            start = end + 1
        }
        return Fraction(ranks - positives.toLong() * (positives + 1), 2L * positives * (targets.size - positives))
    }
    fun roc(probabilities: DoubleArray, targets: IntArray): List<RocPoint> {
        val order = order(probabilities, true);
        val points = mutableListOf<RocPoint>();
        var tp = 0;
        var fp = 0
        for ((position, i) in order.withIndex()) {
            if (targets[i] == 1) tp++ else fp++;
            if (position + 1 == order.size || probabilities[order[position + 1]] != probabilities[i]) points.add(RocPoint(probabilities[i], tp, fp))
        }
        return points
    }
}
