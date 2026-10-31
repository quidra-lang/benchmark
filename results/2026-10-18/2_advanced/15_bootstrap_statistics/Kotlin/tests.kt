import kotlin.math.abs

object Tests {
    fun positionChoices(total: Int, size: Int): List<IntArray> {
        val choices = mutableListOf<IntArray>()
        val choice = IntArray(size) { it }
        while (true) {
            choices += choice.copyOf()
            var i = size - 1
            while (i >= 0 && choice[i] == total - size + i) i--
            if (i < 0) return choices
            choice[i]++
            for (j in i + 1 until size) choice[j] = choice[j - 1] + 1
        }
    }
    fun reducedFraction(numerator: Long, denominator: Long): Pair<Long, Long> {
        var first = abs(numerator)
        var second = denominator
        while (second != 0L) { val next = first % second; first = second; second = next }
        return numerator / first to denominator / first
    }
    fun contrast(firstTotal: Long, firstSize: Int, secondTotal: Long, secondSize: Int): Long = secondSize * firstTotal - firstSize * secondTotal
    fun valueCounts(values: LongArray): Map<Long, Int> {
        val counts = sortedMapOf<Long, Int>()
        for (value in values) counts[value] = counts.getOrDefault(value, 0) + 1
        return counts
    }
    fun doubledRanks(values: LongArray): LongArray {
        val ranks = mutableMapOf<Long, Long>()
        var smaller = 0
        for ((value, count) in valueCounts(values)) { ranks[value] = 2L * smaller + count + 1; smaller += count }
        return LongArray(values.size) { ranks.getValue(values[it]) }
    }
    fun splitList(values: LongArray, sizes: IntArray): List<LongArray> {
        var start = 0
        return sizes.map { size -> values.copyOfRange(start, start + size).also { start += size } }
    }
    fun splitList(values: IntArray, sizes: IntArray): List<IntArray> {
        var start = 0
        return sizes.map { size -> values.copyOfRange(start, start + size).also { start += size } }
    }
    fun sumsOfSquares(samples: List<LongArray>): DoubleArray {
        val count = samples.sumOf { it.size }
        var total = 0L
        for (sample in samples) total += Resampling.sum(sample)
        val grandMean = total.toDouble() / (100L * count)
        var between = 0.0
        var within = 0.0
        for (sample in samples) {
            val groupMean = Resampling.mean(sample)
            val difference = groupMean - grandMean
            between += sample.size * (difference * difference)
            var squares = 0.0
            for (value in sample) { val deviation = value / 100.0 - groupMean; squares += deviation * deviation }
            within += squares
        }
        return doubleArrayOf(between, within)
    }
    fun fStatistic(between: Double, within: Double, groups: Int, total: Int): Double = between / (groups - 1) / (within / (total - groups))
    fun hStatistic(ranks: LongArray, sizes: IntArray, correction: Double): Double {
        val count = sizes.sum()
        var total = 0.0
        for (i in sizes.indices) total += (ranks[i] * ranks[i]).toDouble() / (4L * sizes[i])
        return (12 * total / (count.toLong() * (count + 1)) - 3 * (count + 1)) / correction
    }
}
