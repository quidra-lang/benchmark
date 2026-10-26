import kotlin.math.abs
import kotlin.math.sqrt

object Distances {
    val types = listOf("euclidean", "manhattan", "correlation")
    data class Statistics(val means: DoubleArray, val deviations: DoubleArray)

    fun sum(values: DoubleArray): Double {
        var total = 0.0
        for (value in values) total += value
        return total
    }

    fun squared(first: DoubleArray, second: DoubleArray): Double {
        var total = 0.0
        for (f in first.indices) {
            val difference = first[f] - second[f]
            total += difference * difference
        }
        return total
    }

    fun statistics(rows: Array<DoubleArray>): Statistics {
        val means = DoubleArray(rows[0].size)
        val deviations = DoubleArray(rows[0].size)
        for (f in means.indices) {
            var total = 0.0
            for (row in rows) total += row[f]
            means[f] = total / rows.size
            var squares = 0.0
            for (row in rows) {
                val difference = row[f] - means[f]
                squares += difference * difference
            }
            deviations[f] = sqrt(squares / (rows.size - 1))
        }
        return Statistics(means, deviations)
    }

    fun standardize(rows: Array<DoubleArray>, statistics: Statistics): Array<DoubleArray> =
        Array(rows.size) { i -> DoubleArray(statistics.means.size) { f -> (rows[i][f] - statistics.means[f]) / statistics.deviations[f] } }

    fun distance(first: DoubleArray, second: DoubleArray, type: String): Double {
        if (type == "euclidean") return sqrt(squared(first, second))
        if (type == "manhattan") {
            var total = 0.0
            for (f in first.indices) total += abs(first[f] - second[f])
            return total
        }
        val firstMean = sum(first) / first.size
        val secondMean = sum(second) / second.size
        var cross = 0.0
        var firstSquares = 0.0
        var secondSquares = 0.0
        for (f in first.indices) {
            val a = first[f] - firstMean
            val b = second[f] - secondMean
            cross += a * b
            firstSquares += a * a
            secondSquares += b * b
        }
        return 1 - cross / sqrt(firstSquares * secondSquares)
    }

    fun matrix(vectors: Array<DoubleArray>, type: String): Array<DoubleArray> {
        val matrix = Array(vectors.size) { DoubleArray(vectors.size) }
        for (i in vectors.indices) for (j in i + 1 until vectors.size) {
            val value = distance(vectors[i], vectors[j], type)
            matrix[i][j] = value
            matrix[j][i] = value
        }
        return matrix
    }
}
