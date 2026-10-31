data class Fraction(val numerator: Long, val denominator: Long) : Comparable<Fraction> {
    override fun compareTo(other: Fraction): Int = (numerator * other.denominator).compareTo(other.numerator * denominator)
}

object Impurity {
    fun counts(rows: List<Row>, classes: Int): IntArray = IntArray(classes).also { counts ->
        for (row in rows) counts[row.label]++
    }
    fun squareSum(counts: IntArray): Long = counts.sumOf { it.toLong() * it }
    fun majority(counts: IntArray): Int {
        var best = 0
        for (i in 1 until counts.size) if (counts[i] > counts[best]) best = i
        return best
    }
    fun errors(counts: IntArray): Int = counts.sum() - counts[majority(counts)]
    fun quality(left: IntArray, right: IntArray): Fraction {
        val leftSize = left.sum().toLong()
        val rightSize = right.sum().toLong()
        return Fraction(squareSum(left) * rightSize + squareSum(right) * leftSize, leftSize * rightSize)
    }
    fun improves(value: Fraction, counts: IntArray): Boolean =
        value.numerator * counts.sum() > squareSum(counts) * value.denominator
    fun decrease(counts: IntArray, left: IntArray, right: IntArray): Double {
        val leftValue = squareSum(left).toDouble() / left.sum()
        val rightValue = squareSum(right).toDouble() / right.sum()
        val parent = squareSum(counts).toDouble() / counts.sum()
        return (leftValue + rightValue) - parent
    }
}
