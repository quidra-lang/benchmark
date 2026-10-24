import java.util.Locale

fun main() {
    val systems = listOf(arrayOf(doubleArrayOf(2.0,-1.0,3.0,7.0),doubleArrayOf(4.0,1.0,-2.0,3.0),doubleArrayOf(-3.0,5.0,1.0,-4.0)),
        arrayOf(doubleArrayOf(1.0,3.0,-2.0,4.0,6.0),doubleArrayOf(5.0,-2.0,1.0,3.0,-7.0),doubleArrayOf(-2.0,4.0,6.0,-1.0,9.0),doubleArrayOf(3.0,1.0,-4.0,2.0,5.0)))
    for ((system,a) in systems.withIndex()) {
        val n = a.size
        for (k in 0 until n) {
            val pivot = (k until n).maxBy { kotlin.math.abs(a[it][k]) }
            val temporary = a[k]
            a[k] = a[pivot]
            a[pivot] = temporary
            for (i in k + 1 until n) {
                val factor = a[i][k] / a[k][k]
                for (j in k..n) a[i][j] = a[i][j] - factor * a[k][j]
            }
        }
        val x = DoubleArray(n)
        for (i in n - 1 downTo 0) {
            var sum = a[i][n]
            for (j in i + 1 until n) sum = sum - a[i][j] * x[j]
            x[i] = sum / a[i][i]
        }
        println("system ${system + 1}:")
        for (i in 0 until n) println("x%d = %.4f".format(Locale.ROOT, i + 1, x[i]))
    }
}
