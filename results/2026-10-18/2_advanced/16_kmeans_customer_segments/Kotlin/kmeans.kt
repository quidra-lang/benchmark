data class Assignment(val labels: IntArray, val errors: DoubleArray)
data class LloydResult(val labels: IntArray, val centers: List<DoubleArray>, val iterations: Int, val converged: Boolean, val reseeds: Int)
object KMeans {
    fun squaredDistance(first: DoubleArray, second: DoubleArray): Double {
        var total = 0.0
        for (f in first.indices) {
            val difference = first[f] - second[f]
            total += difference * difference
        }
        return total
    }
    fun assign(points: List<DoubleArray>, centers: List<DoubleArray>): Assignment {
        val labels = IntArray(points.size)
        val errors = DoubleArray(points.size)
        for (i in points.indices) {
            var best = 0
            var distance = squaredDistance(points[i], centers[0])
            for (j in 1 until centers.size) {
                val trial = squaredDistance(points[i], centers[j])
                if (trial < distance) { best = j; distance = trial }
            }
            labels[i] = best
            errors[i] = distance
        }
        return Assignment(labels, errors)
    }
    fun meanPoint(points: List<DoubleArray>): DoubleArray {
        val total = DoubleArray(points[0].size)
        for (point in points) for (f in total.indices) total[f] += point[f]
        for (f in total.indices) total[f] /= points.size
        return total
    }
    fun sizes(labels: IntArray, k: Int): IntArray {
        val sizes = IntArray(k)
        for (label in labels) sizes[label]++
        return sizes
    }
    fun center(points: List<DoubleArray>, labels: IntArray, cluster: Int): DoubleArray =
        meanPoint(points.indices.filter { labels[it] == cluster }.map { points[it] })
    fun centers(points: List<DoubleArray>, labels: IntArray, k: Int): List<DoubleArray> =
        (0 until k).map { center(points, labels, it) }
    fun refill(labels: IntArray, errors: DoubleArray, k: Int): Int {
        val sizes = sizes(labels, k)
        var reseeds = 0
        for (j in 0 until k) {
            if (sizes[j] > 0) continue
            var chosen = -1
            for (i in labels.indices) if (sizes[labels[i]] >= 2 && (chosen < 0 || errors[i] > errors[chosen])) chosen = i
            sizes[labels[chosen]]--
            sizes[j]++
            labels[chosen] = j
            errors[chosen] = 0.0
            reseeds++
        }
        return reseeds
    }
    fun lloyd(points: List<DoubleArray>, initial: List<DoubleArray>, limit: Int): LloydResult {
        val k = initial.size
        var iterations = 0
        var reseeds = 0
        var assignment = assign(points, initial)
        var converged = false
        while (iterations < limit && !converged) {
            reseeds += refill(assignment.labels, assignment.errors, k)
            val centers = centers(points, assignment.labels, k)
            iterations++
            val next = assign(points, centers)
            converged = next.labels.contentEquals(assignment.labels)
            assignment = next
        }
        reseeds += refill(assignment.labels, assignment.errors, k)
        return LloydResult(assignment.labels, centers(points, assignment.labels, k), iterations, converged, reseeds)
    }
    fun sse(points: List<DoubleArray>, labels: IntArray, centers: List<DoubleArray>): Double {
        var total = 0.0
        for (i in labels.indices) total += squaredDistance(points[i], centers[labels[i]])
        return total
    }
}
