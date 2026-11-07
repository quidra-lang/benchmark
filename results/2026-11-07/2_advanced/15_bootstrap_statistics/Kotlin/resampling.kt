import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sqrt

object Resampling {
    fun sum(values: LongArray): Long = values.fold(0L) { total, value -> total + value }
    fun sequentialSum(values: DoubleArray): Double = values.fold(0.0) { total, value -> total + value }
    fun mean(values: LongArray): Double = sum(values).toDouble() / (100L * values.size)
    fun doubledMedian(values: LongArray): Long {
        val ordered = values.sortedArray()
        return ordered[(values.size - 1) / 2] + ordered[values.size / 2]
    }
    fun median(values: LongArray): Double = doubledMedian(values) / 200.0
    fun trimmedMean(values: LongArray): Double {
        val ordered = values.sortedArray()
        val trim = values.size / 10
        var total = 0L
        for (i in trim until values.size - trim) total += ordered[i]
        return total.toDouble() / (100L * (values.size - 2 * trim))
    }
    fun deviations(values: LongArray): DoubleArray {
        val center = mean(values)
        return DoubleArray(values.size) { values[it] / 100.0 - center }
    }
    fun sd(values: LongArray): Double {
        var squares = 0.0
        for (deviation in deviations(values)) squares += deviation * deviation
        return sqrt(squares / (values.size - 1))
    }
    fun centralMoments(values: LongArray): DoubleArray {
        var second = 0.0
        var third = 0.0
        var fourth = 0.0
        for (deviation in deviations(values)) {
            second += deviation * deviation
            third += deviation * deviation * deviation
            fourth += deviation * deviation * deviation * deviation
        }
        return doubleArrayOf(second / values.size, third / values.size, fourth / values.size)
    }
    fun mad(values: LongArray): Double {
        val center = doubledMedian(values)
        return doubledMedian(LongArray(values.size) { abs(2 * values[it] - center) }) / 400.0
    }
    fun quantileNumerator(values: LongArray, percent: Int): Long {
        val ordered = values.sortedArray()
        val position = (values.size - 1) * percent
        val index = position / 100
        val fraction = position % 100
        return 100 * ordered[index] + if (fraction == 0) 0L else fraction * (ordered[index + 1] - ordered[index])
    }
    fun winsorized(values: LongArray): LongArray {
        val ordered = values.sortedArray()
        val trim = values.size / 10
        val low = ordered[trim]
        val high = ordered[values.size - trim - 1]
        return LongArray(values.size) { values[it].coerceIn(low, high) }
    }
    fun meanDifference(x: LongArray, y: LongArray): Double =
        (y.size * sum(x) - x.size * sum(y)).toDouble() / (100L * x.size * y.size)
    fun medianRatio(x: LongArray, y: LongArray): Double = doubledMedian(x).toDouble() / doubledMedian(y)
    fun hodgesLehmann(x: LongArray, y: LongArray): Double {
        val differences = LongArray(x.size * y.size)
        var index = 0
        for (first in x) for (second in y) differences[index++] = first - second
        return doubledMedian(differences) / 200.0
    }
    fun pooledSd(x: LongArray, y: LongArray): Double {
        val first = sd(x)
        val second = sd(y)
        val squares = (x.size - 1) * first * first + (y.size - 1) * second * second
        return sqrt(squares / (x.size + y.size - 2))
    }
    fun cohenD(x: LongArray, y: LongArray): Double = meanDifference(x, y) / pooledSd(x, y)
    fun correlation(x: LongArray, y: LongArray): Double {
        val first = deviations(x)
        val second = deviations(y)
        var products = 0.0
        var firstSquares = 0.0
        var secondSquares = 0.0
        for (i in x.indices) products += first[i] * second[i]
        for (value in first) firstSquares += value * value
        for (value in second) secondSquares += value * value
        return products / sqrt(firstSquares * secondSquares)
    }
    fun groupStatistic(index: Int, values: LongArray): Double = when (index) {
        0 -> mean(values)
        1 -> median(values)
        2 -> trimmedMean(values)
        3 -> sd(values)
        else -> error("Unknown statistic")
    }
    fun pairStatistic(index: Int, x: LongArray, y: LongArray): Double = when (index) {
        0 -> meanDifference(x, y)
        1 -> medianRatio(x, y)
        2 -> hodgesLehmann(x, y)
        3 -> cohenD(x, y)
        else -> error("Unknown statistic")
    }
    fun resampleIndices(generator: Minstd, size: Int): IntArray = IntArray(size) { generator.below(size) }
    fun ordinaryIndices(generator: Minstd, size: Int, count: Int): Array<IntArray> = Array(count) { resampleIndices(generator, size) }
    fun balancedIndices(generator: Minstd, size: Int, count: Int): Array<IntArray> {
        val sequence = IntArray(size * count) { it % size }
        generator.shuffle(sequence)
        return Array(count) { sequence.copyOfRange(it * size, (it + 1) * size) }
    }
    fun sample(values: LongArray, indices: IntArray): LongArray = LongArray(indices.size) { values[indices[it]] }
    fun without(values: LongArray, removed: Int): LongArray = values.filterIndexed { index, _ -> index != removed }.toLongArray()
    fun meanAndSe(values: DoubleArray): DoubleArray {
        val average = sequentialSum(values) / values.size
        var squares = 0.0
        for (value in values) { val deviation = value - average; squares += deviation * deviation }
        return doubleArrayOf(average, sqrt(squares / (values.size - 1)))
    }
    fun phi(x: Double): Double {
        if (x < 0) return 1 - phi(-x)
        val eta = 1 / (1 + 0.2316419 * x)
        val psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (1.781477937 + eta * (-1.821255978 + eta * 1.330274429))))
        return 1 - 0.3989422804014327 * exp(-(x * x) / 2) * psi
    }
    fun phiInverse(p: Double): Double {
        if (p > 0.5) return -phiInverse(1 - p)
        val eta = sqrt(-2 * ln(p))
        val numerator = 2.515517 + eta * (0.802853 + eta * 0.010328)
        val denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))
        return -(eta - numerator / denominator)
    }
}
