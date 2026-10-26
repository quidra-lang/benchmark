import kotlin.math.abs
import kotlin.math.sqrt

data class Massey(val ratings: DoubleArray, val homeAdvantage: Double)
object LinearModels {
    fun cholesky(matrix: Array<DoubleArray>, vector: DoubleArray): DoubleArray {
        val size = vector.size
        val lower = Array(size) { DoubleArray(size) }
        for (i in 0 until size) for (j in 0..i) {
            var total = 0.0
            for (k in 0 until j) total += lower[i][k] * lower[j][k]
            lower[i][j] = if (j < i) (matrix[i][j] - total) / lower[j][j] else sqrt(matrix[i][i] - total)
        }
        val forward = DoubleArray(size)
        for (i in 0 until size) {
            var total = 0.0
            for (k in 0 until i) total += lower[i][k] * forward[k]
            forward[i] = (vector[i] - total) / lower[i][i]
        }
        val solution = DoubleArray(size)
        for (i in size - 1 downTo 0) {
            var total = 0.0
            for (k in i + 1 until size) total += lower[k][i] * solution[k]
            solution[i] = (forward[i] - total) / lower[i][i]
        }
        return solution
    }
    fun gaussian(matrix: Array<DoubleArray>, vector: DoubleArray): DoubleArray {
        val size = vector.size
        for (k in 0 until size) {
            var pivot = k
            for (row in k + 1 until size) if (abs(matrix[row][k]) > abs(matrix[pivot][k])) pivot = row
            val row = matrix[k]
            matrix[k] = matrix[pivot]
            matrix[pivot] = row
            val value = vector[k]
            vector[k] = vector[pivot]
            vector[pivot] = value
            for (i in k + 1 until size) {
                val factor = matrix[i][k] / matrix[k][k]
                for (j in k until size) matrix[i][j] -= factor * matrix[k][j]
                vector[i] -= factor * vector[k]
            }
        }
        val solution = DoubleArray(size)
        for (i in size - 1 downTo 0) {
            var total = 0.0
            for (j in i + 1 until size) total += matrix[i][j] * solution[j]
            solution[i] = (vector[i] - total) / matrix[i][i]
        }
        return solution
    }
    fun colley(count: Int, matches: List<Match>): DoubleArray {
        val matrix = Array(count) { DoubleArray(count) }
        val balance = IntArray(count)
        for (i in 0 until count) matrix[i][i] = 2.0
        for (match in matches) {
            val home = match.home
            val away = match.away
            matrix[home][home]++; matrix[away][away]++; matrix[home][away]--; matrix[away][home]--
            if (match.margin > 0) { balance[home]++; balance[away]-- }
            else if (match.margin < 0) { balance[home]--; balance[away]++ }
        }
        return cholesky(matrix, DoubleArray(count) { 1 + balance[it] / 2.0 })
    }
    fun massey(count: Int, matches: List<Match>): Massey {
        val size = count + 1
        val matrix = Array(size) { DoubleArray(size) }
        val vector = DoubleArray(size)
        for (match in matches) {
            val home = match.home
            val away = match.away
            val margin = match.margin
            matrix[home][home]++; matrix[away][away]++; matrix[home][away]--; matrix[away][home]--
            matrix[home][count]++; matrix[count][home]++; matrix[away][count]--; matrix[count][away]--; matrix[count][count]++
            vector[home] += margin; vector[away] -= margin; vector[count] += margin
        }
        matrix[count - 1].fill(1.0)
        matrix[count - 1][count] = 0.0
        vector[count - 1] = 0.0
        val solution = gaussian(matrix, vector)
        return Massey(solution.copyOf(count), solution[count])
    }
}
