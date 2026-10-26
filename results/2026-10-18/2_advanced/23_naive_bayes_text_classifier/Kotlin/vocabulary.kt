data class RankedTerm(val term: String, val frequency: Int, val score: Double, val bestClass: Int)

class Vocabulary(sequences: List<List<String>>, labels: IntArray, classes: Int, minDf: Int, requestedSize: Int) {
    val termCount: Int
    val candidateCount: Int
    val ranking: List<RankedTerm>
    val terms: List<String>
    val frequencies: IntArray
    val index: Map<String, Int>
    val size: Int get() = terms.size

    init {
        val counts = sortedMapOf<String, IntArray>()
        val classSizes = IntArray(classes)
        for (i in sequences.indices) {
            classSizes[labels[i]]++
            for (term in sequences[i].toSet()) counts.getOrPut(term) { IntArray(classes) }[labels[i]]++
        }
        termCount = counts.size
        val candidates = mutableListOf<RankedTerm>()
        for ((term, row) in counts) {
            val frequency = row.sum()
            if (frequency < minDf) continue
            var best = 0
            var score = chiSquare(row[0].toLong(), frequency.toLong(), classSizes[0].toLong(), labels.size.toLong())
            for (c in 1 until classes) {
                val value = chiSquare(row[c].toLong(), frequency.toLong(), classSizes[c].toLong(), labels.size.toLong())
                if (value > score) { best = c; score = value }
            }
            candidates.add(RankedTerm(term, frequency, score, best))
        }
        candidateCount = candidates.size
        val ordered = candidates.sortedWith(compareByDescending<RankedTerm> { it.score }.thenBy { it.term })
        ranking = ordered.take(if (requestedSize > 0) requestedSize else candidates.size)
        terms = ranking.map { it.term }.sorted()
        index = terms.withIndex().associate { it.value to it.index }
        val dfs = ranking.associate { it.term to it.frequency }
        frequencies = IntArray(size) { dfs.getValue(terms[it]) }
    }

    fun encode(sequence: List<String>): IntArray = sequence.mapNotNull { index[it] }.toIntArray()

    companion object {
        private fun chiSquare(a: Long, df: Long, classSize: Long, total: Long): Double {
            val b = df - a
            val c = classSize - a
            val e = total - classSize - b
            val determinant = a * e - b * c
            val numerator = total * determinant * determinant
            val denominator = df * (total - df) * classSize * (total - classSize)
            return if (denominator == 0L) 0.0 else numerator.toDouble() / denominator
        }
    }
}

fun firstOccurrences(sequence: IntArray): IntArray {
    val seen = linkedSetOf<Int>()
    for (term in sequence) seen.add(term)
    return seen.toIntArray()
}
