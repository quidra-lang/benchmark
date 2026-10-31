import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class Fraction(numerator: Long, denominator: Long) : Comparable<Fraction> {
    val numerator: Long
    val denominator: Long
    init {
        val sign = if (denominator < 0) -1 else 1
        var first = abs(numerator)
        var second = abs(denominator)
        while (second != 0L) { val remainder = first % second; first = second; second = remainder }
        this.numerator = numerator * sign / first
        this.denominator = denominator * sign / first
    }
    val value: Double get() = numerator.toDouble() / denominator
    override fun compareTo(other: Fraction): Int = (numerator * other.denominator).compareTo(other.numerator * denominator)
    override fun toString(): String = "$numerator/$denominator"
}

object Validation {
    fun correlation(first: DoubleArray, second: DoubleArray): Double {
        val firstMean = Distances.sum(first) / first.size
        val secondMean = Distances.sum(second) / second.size
        var cross = 0.0
        var firstSquares = 0.0
        var secondSquares = 0.0
        for (i in first.indices) {
            val a = first[i] - firstMean
            val b = second[i] - secondMean
            cross += a * b
            firstSquares += a * a
            secondSquares += b * b
        }
        return cross / sqrt(firstSquares * secondSquares)
    }

    fun contingency(first: IntArray, second: IntArray, rows: Int, columns: Int): Array<IntArray> {
        val table = Array(rows) { IntArray(columns) }
        for (i in first.indices) table[first[i]][second[i]]++
        return table
    }

    private fun pairCount(value: Long): Long = value * (value - 1) / 2
    fun adjustedRand(table: Array<IntArray>): Fraction {
        var count = 0L
        var same = 0L
        var rowPairs = 0L
        var columnPairs = 0L
        val columns = IntArray(table[0].size)
        for (row in table) {
            var total = 0
            for (column in row.indices) { total += row[column]; same += pairCount(row[column].toLong()); columns[column] += row[column] }
            count += total
            rowPairs += pairCount(total.toLong())
        }
        for (total in columns) columnPairs += pairCount(total.toLong())
        val pairs = pairCount(count)
        val numerator = 2 * (pairs * same - rowPairs * columnPairs)
        val denominator = pairs * (rowPairs + columnPairs) - 2 * rowPairs * columnPairs
        return if (denominator == 0L) Fraction(1, 1) else Fraction(numerator, denominator)
    }

    fun silhouettes(partition: IntArray, groups: Int, delta: Array<DoubleArray>): DoubleArray {
        val sizes = IntArray(groups + 1)
        for (number in partition) sizes[number]++
        val values = DoubleArray(partition.size)
        for (i in partition.indices) {
            val own = partition[i]
            if (sizes[own] == 1) continue
            val sums = DoubleArray(groups + 1)
            for (j in partition.indices) if (j != i) sums[partition[j]] += delta[i][j]
            val inner = sums[own] / (sizes[own] - 1)
            var outer = Double.POSITIVE_INFINITY
            for (g in 1..groups) if (g != own) outer = min(outer, sums[g] / sizes[g])
            values[i] = (outer - inner) / max(inner, outer)
        }
        return values
    }
}
