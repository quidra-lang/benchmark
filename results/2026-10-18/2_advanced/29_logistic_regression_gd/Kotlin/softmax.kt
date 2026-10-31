import kotlin.math.exp
import kotlin.math.ln

data class SoftCheckpoint(val iteration: Int, val weights: Array<DoubleArray>)
object Softmax {
    fun shifted(weights: Array<DoubleArray>, vector: DoubleArray): DoubleArray {
        val scores = weights.map {
            Logistic.score(it, vector)
        }.toDoubleArray();
        val maximum = scores.max();
        return DoubleArray(scores.size) {
            scores[it] - maximum
        }
    }
    fun total(shifted: DoubleArray): Double {
        var total = 0.0;
        for (value in shifted) total += exp(value);
        return total
    }
    fun probabilities(weights: Array<DoubleArray>, vector: DoubleArray): DoubleArray {
        val shifted = shifted(weights, vector);
        val total = total(shifted);
        return DoubleArray(shifted.size) {
            exp(shifted[it]) / total
        }
    }
    fun prediction(probabilities: DoubleArray): Int = probabilities.indices.maxBy {
        probabilities[it]
    }
    fun loss(weights: Array<DoubleArray>, vector: DoubleArray, label: Int): Double {
        val shifted = shifted(weights, vector);
        return ln(total(shifted)) - shifted[label]
    }
    fun average(weights: Array<DoubleArray>, vectors: Array<DoubleArray>, labels: IntArray): Double {
        var total = 0.0;
        for (i in vectors.indices) total += loss(weights, vectors[i], labels[i]);
        return total / vectors.size
    }
    fun objective(weights: Array<DoubleArray>, vectors: Array<DoubleArray>, labels: IntArray, lambda: Double): Double {
        var total = 0.0;
        for (row in weights) for (j in 1 until row.size) total += row[j] * row[j];
        return average(weights, vectors, labels) + lambda * total / 2
    }
    fun gradient(weights: Array<DoubleArray>, vectors: Array<DoubleArray>, labels: IntArray, lambda: Double): Array<DoubleArray> {
        val classes = weights.size;
        val size = weights[0].size;
        val totals = Array(classes) {
            DoubleArray(size)
        }
        for (i in vectors.indices) {
            val probabilities = probabilities(weights, vectors[i]);
            for (k in 0 until classes) {
                val error = probabilities[k] - if (labels[i] == k) 1.0 else 0.0;
                for (j in 0 until size) totals[k][j] += error * vectors[i][j]
            }
        }
        for (k in 0 until classes) for (j in 0 until size) {
            totals[k][j] /= vectors.size;
            if (j >= 1) totals[k][j] += lambda * weights[k][j]
        }
        return totals
    }
    fun train(vectors: Array<DoubleArray>, labels: IntArray, classes: Int, lambda: Double, rate: Double, iterations: Int): List<SoftCheckpoint> {
        var weights = Array(classes) {
            DoubleArray(vectors[0].size)
        };
        val checkpoints = mutableListOf(SoftCheckpoint(0, weights))
        for (t in 1..iterations) {
            val gradient = gradient(weights, vectors, labels, lambda);
            weights = Array(classes) {
                k -> DoubleArray(weights[k].size) {
                    j -> weights[k][j] - rate * gradient[k][j]
                }
            };
            if (t % 100 == 0) checkpoints.add(SoftCheckpoint(t, weights))
        }
        return checkpoints
    }
}
