import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max

object Logistic {
    fun score(weights: DoubleArray, vector: DoubleArray): Double {
        var total = 0.0;
        for (j in weights.indices) total += weights[j] * vector[j];
        return total
    }
    fun probability(score: Double): Double {
        if (score >= 0) return 1 / (1 + exp(-score));
        val exponential = exp(score);
        return exponential / (1 + exponential)
    }
    fun loss(score: Double, target: Int): Double = max(score, 0.0) - target * score + ln(1 + exp(-abs(score)))
    fun average(weights: DoubleArray, vectors: Array<DoubleArray>, targets: IntArray): Double {
        var total = 0.0;
        for (i in vectors.indices) total += loss(score(weights, vectors[i]), targets[i]);
        return total / vectors.size
    }
    fun penalty(weights: DoubleArray): Double {
        var total = 0.0;
        for (j in 1 until weights.size) total += weights[j] * weights[j];
        return total
    }
    fun objective(weights: DoubleArray, vectors: Array<DoubleArray>, targets: IntArray, lambda: Double): Double = average(weights,
         vectors, targets) + lambda * penalty(weights) / 2
    fun gradient(weights: DoubleArray, vectors: Array<DoubleArray>, targets: IntArray, lambda: Double): DoubleArray {
        val totals = DoubleArray(weights.size)
        for (i in vectors.indices) {
            val error = probability(score(weights, vectors[i])) - targets[i];
            for (j in totals.indices) totals[j] += error * vectors[i][j]
        }
        for (j in totals.indices) {
            totals[j] /= vectors.size;
            if (j != 0) totals[j] += lambda * weights[j]
        }
        return totals
    }
    fun hessian(weights: DoubleArray, vectors: Array<DoubleArray>, lambda: Double): Array<DoubleArray> {
        val size = weights.size;
        val totals = Array(size) {
            DoubleArray(size)
        }
        for (vector in vectors) {
            val probability = probability(score(weights, vector));
            val variance = probability * (1 - probability);
            for (j in 0 until size) for (k in 0..j) totals[j][k] += variance * vector[j] * vector[k]
        }
        for (j in 0 until size) for (k in 0..j) {
            var value = totals[j][k] / vectors.size;
            if (j == k && j >= 1) value += lambda;
            totals[j][k] = value;
            totals[k][j] = value
        }
        return totals
    }
}
