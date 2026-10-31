import kotlin.math.sqrt

object Validation {
    fun distanceTable(points: List<DoubleArray>): Array<DoubleArray> {
        val table = Array(points.size) { DoubleArray(points.size) }
        for (i in points.indices) for (j in i + 1 until points.size) {
            val distance = sqrt(KMeans.squaredDistance(points[i], points[j]))
            table[i][j] = distance
            table[j][i] = distance
        }
        return table
    }
    fun silhouettes(table: Array<DoubleArray>, labels: IntArray, sizes: IntArray): DoubleArray {
        val values = DoubleArray(labels.size)
        for (i in labels.indices) {
            val own = labels[i]
            if (sizes[own] == 1) continue
            val total = DoubleArray(sizes.size)
            for (j in labels.indices) if (j != i) total[labels[j]] += table[i][j]
            val inner = total[own] / (sizes[own] - 1)
            var outer = Double.POSITIVE_INFINITY
            for (segment in sizes.indices) if (segment != own) outer = minOf(outer, total[segment] / sizes[segment])
            val largest = maxOf(inner, outer)
            values[i] = if (largest == 0.0) 0.0 else (outer - inner) / largest
        }
        return values
    }
    fun calinskiHarabasz(points: List<DoubleArray>, centers: List<DoubleArray>, sizes: IntArray, within: Double): Double {
        val overall = KMeans.meanPoint(points)
        var between = 0.0
        for (j in sizes.indices) between += sizes[j] * KMeans.squaredDistance(centers[j], overall)
        return (between / (centers.size - 1)) / (within / (points.size - centers.size))
    }
    fun daviesBouldin(points: List<DoubleArray>, labels: IntArray, centers: List<DoubleArray>, sizes: IntArray): Double {
        val spreads = DoubleArray(sizes.size)
        for (i in points.indices) spreads[labels[i]] += sqrt(KMeans.squaredDistance(points[i], centers[labels[i]]))
        for (j in sizes.indices) spreads[j] /= sizes[j]
        var total = 0.0
        for (a in sizes.indices) {
            var worst = Double.NEGATIVE_INFINITY
            for (e in sizes.indices) if (e != a) worst = maxOf(worst, (spreads[a] + spreads[e]) / sqrt(KMeans.squaredDistance(centers[a], centers[e])))
            total += worst
        }
        return total / sizes.size
    }
    fun elbow(k: Int, first: Int, last: Int, within: Double, firstWithin: Double, lastWithin: Double): Double {
        val x = (k - first).toDouble() / (last - first)
        val y = (within - lastWithin) / (firstWithin - lastWithin)
        return ((1 - x) - y) / sqrt(2.0)
    }
    fun hartigan(within: Double, next: Double, count: Int, k: Int) = (within / next - 1) * (count - k - 1)
    fun pairCount(size: Long) = size * (size - 1) / 2
    fun ari(first: IntArray, second: IntArray): Double {
        val joint = mutableMapOf<Long, Int>()
        val firstSizes = mutableMapOf<Int, Int>()
        val secondSizes = mutableMapOf<Int, Int>()
        for (i in first.indices) {
            val key = (first[i].toLong() shl 32) xor (second[i].toLong() and 0xffffffffL)
            joint[key] = joint.getOrDefault(key, 0) + 1
            firstSizes[first[i]] = firstSizes.getOrDefault(first[i], 0) + 1
            secondSizes[second[i]] = secondSizes.getOrDefault(second[i], 0) + 1
        }
        val total = pairCount(first.size.toLong())
        var shared = 0L
        var firstPairs = 0L
        var secondPairs = 0L
        for (size in joint.values) shared += pairCount(size.toLong())
        for (size in firstSizes.values) firstPairs += pairCount(size.toLong())
        for (size in secondSizes.values) secondPairs += pairCount(size.toLong())
        val numerator = 2 * (total * shared - firstPairs * secondPairs)
        val denominator = total * (firstPairs + secondPairs) - 2 * firstPairs * secondPairs
        return if (denominator == 0L) 1.0 else numerator.toDouble() / denominator
    }
}
