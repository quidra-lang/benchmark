import kotlin.math.exp
import kotlin.math.ln

class TrainingCounts(sequences: List<IntArray>, labels: IntArray, val classCount: Int, val vocabularySize: Int) {
    val documentTotal = sequences.size
    val documents = LongArray(classCount)
    val occurrences = Array(classCount) { LongArray(vocabularySize) }
    val containing = Array(classCount) { LongArray(vocabularySize) }
    val totals = LongArray(classCount)
    val termTotals = LongArray(vocabularySize)
    val total: Long

    init {
        for (i in sequences.indices) {
            val c = labels[i]
            documents[c]++
            for (term in sequences[i]) occurrences[c][term]++
            for (term in firstOccurrences(sequences[i])) containing[c][term]++
        }
        var sum = 0L
        for (c in 0 until classCount) {
            for (t in 0 until vocabularySize) { totals[c] += occurrences[c][t]; termTotals[t] += occurrences[c][t] }
            sum += totals[c]
        }
        total = sum
    }
}

class Prediction {
    val label: Int
    val score: Double
    val ranking: IntArray
    val scores: DoubleArray
    val probabilities: DoubleArray
    val normalizer: Double
    val margin: Double

    constructor(values: DoubleArray, posterior: Boolean) {
        scores = values
        ranking = values.indices.sortedWith(compareByDescending<Int> { values[it] }.thenBy { it }).toIntArray()
        label = ranking[0]
        margin = values[label] - values[ranking[1]]
        probabilities = DoubleArray(values.size)
        var sum = 0.0
        if (posterior) {
            for (c in values.indices) { probabilities[c] = exp(values[c] - values[label]); sum += probabilities[c] }
            for (c in values.indices) probabilities[c] /= sum
        }
        normalizer = sum
        score = if (posterior) probabilities[label] else values[label]
    }

    constructor(winner: Int, value: Double) {
        label = winner
        score = value
        ranking = IntArray(0)
        scores = DoubleArray(0)
        probabilities = DoubleArray(0)
        normalizer = 0.0
        margin = 0.0
    }
}

class NaiveBayes(val kind: Int, val priors: DoubleArray, val base: DoubleArray, val weights: Array<DoubleArray>) {
    fun predict(sequence: IntArray): Prediction {
        val terms = if (kind == 1) firstOccurrences(sequence) else sequence
        val scores = DoubleArray(weights.size)
        for (c in weights.indices) {
            var score = base[c]
            for (term in terms) score += weights[c][term]
            scores[c] = score + priors[c]
        }
        return Prediction(scores, true)
    }

    companion object {
        fun smoothedLog(count: Long, total: Long, alpha: Int, outcomes: Int): Double =
            ln((100 * count + alpha).toDouble() / (100 * total + alpha.toLong() * outcomes))

        fun smoothedLog(count: Double, total: Double, alpha: Int, outcomes: Int): Double =
            ln((100 * count + alpha) / (100 * total + alpha.toDouble() * outcomes))

        fun train(kind: Int, counts: TrainingCounts, alpha: Int): NaiveBayes {
            val size = counts.vocabularySize
            val priors = DoubleArray(counts.classCount)
            val base = DoubleArray(counts.classCount)
            val weights = Array(counts.classCount) { DoubleArray(size) }
            for (c in 0 until counts.classCount) {
                priors[c] = ln(counts.documents[c].toDouble() / counts.documentTotal)
                for (t in 0 until size) {
                    if (kind == 0) weights[c][t] = smoothedLog(counts.occurrences[c][t], counts.totals[c], alpha, size)
                    else if (kind == 1) {
                        val present = smoothedLog(counts.containing[c][t], counts.documents[c], alpha, 2)
                        val absent = smoothedLog(counts.documents[c] - counts.containing[c][t], counts.documents[c], alpha, 2)
                        base[c] += absent
                        weights[c][t] = present - absent
                    } else weights[c][t] = -smoothedLog(counts.termTotals[t] - counts.occurrences[c][t], counts.total - counts.totals[c], alpha, size)
                }
            }
            return NaiveBayes(kind, priors, base, weights)
        }
    }
}
