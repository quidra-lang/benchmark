import kotlin.math.ln
import kotlin.math.sqrt

class Rocchio(sequences: List<IntArray>, labels: IntArray, classes: Int, frequencies: IntArray) {
    private val idf = DoubleArray(frequencies.size) { ln(sequences.size.toDouble() / frequencies[it]) }
    private val centroids = Array(classes) { DoubleArray(idf.size) }
    private val lengths = DoubleArray(classes)

    init {
        val documents = IntArray(classes)
        for (i in sequences.indices) {
            val c = labels[i]
            documents[c]++
            val vector = vector(sequences[i])
            val length = vectorLength(vector)
            if (length > 0) for (t in idf.indices) centroids[c][t] += vector[t] / length
        }
        for (c in 0 until classes) {
            for (t in idf.indices) centroids[c][t] /= documents[c]
            lengths[c] = vectorLength(centroids[c])
        }
    }

    private fun vector(sequence: IntArray): DoubleArray {
        val counts = IntArray(idf.size)
        for (term in sequence) counts[term]++
        return DoubleArray(idf.size) { counts[it] * idf[it] }
    }

    private fun vectorLength(values: DoubleArray): Double {
        var total = 0.0
        for (value in values) total += value * value
        return sqrt(total)
    }

    fun predict(sequence: IntArray): Prediction {
        val vector = vector(sequence)
        val length = vectorLength(vector)
        val scores = DoubleArray(centroids.size)
        for (c in centroids.indices) {
            if (length > 0 && lengths[c] > 0) {
                var product = 0.0
                for (t in idf.indices) product += vector[t] * centroids[c][t]
                scores[c] = product / (length * lengths[c])
            }
        }
        return Prediction(scores, false)
    }
}
