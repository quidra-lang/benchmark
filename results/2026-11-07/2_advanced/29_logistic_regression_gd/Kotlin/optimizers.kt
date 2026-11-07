import kotlin.math.sqrt

data class Checkpoint(val iteration: Int, val weights: DoubleArray)
class Minstd(seed: Int) {
    private var state = seed.toLong()
    fun draw(): Int {
        state = 48271 * state % 2147483647;
        return state.toInt()
    }
    fun shuffle(order: IntArray) {
        for (i in order.size downTo 2) {
            val index = draw() % i;
            val old = order[i - 1];
            order[i - 1] = order[index];
            order[index] = old
        }
    }
}
object Optimizers {
    fun cholesky(matrix: Array<DoubleArray>): Array<DoubleArray> {
        val size = matrix.size;
        val lower = Array(size) {
            DoubleArray(size)
        }
        for (j in 0 until size) for (i in j until size) {
            var total = 0.0;
            for (k in 0 until j) total += lower[i][k] * lower[j][k];
            val remainder = matrix[i][j] - total;
            lower[i][j] = if (i == j) sqrt(remainder) else remainder / lower[j][j]
        }
        return lower
    }
    fun solve(lower: Array<DoubleArray>, values: DoubleArray): DoubleArray {
        val size = lower.size;
        val middle = DoubleArray(size);
        val solution = DoubleArray(size)
        for (i in 0 until size) {
            var total = 0.0;
            for (k in 0 until i) total += lower[i][k] * middle[k];
            middle[i] = (values[i] - total) / lower[i][i]
        }
        for (i in size - 1 downTo 0) {
            var total = 0.0;
            for (k in i + 1 until size) total += lower[k][i] * solution[k];
            solution[i] = (middle[i] - total) / lower[i][i]
        }
        return solution
    }
    fun newton(vectors: Array<DoubleArray>, targets: IntArray, lambda: Double): List<Checkpoint> {
        var weights = DoubleArray(vectors[0].size);
        val checkpoints = mutableListOf(Checkpoint(0, weights))
        for (t in 1..10) {
            val step = solve(cholesky(Logistic.hessian(weights, vectors, lambda)), Logistic.gradient(weights, vectors, targets, lambda));
            weights = DoubleArray(weights.size) {
                weights[it] - step[it]
            };
            checkpoints.add(Checkpoint(t, weights))
        }
        return checkpoints
    }
    fun gd(vectors: Array<DoubleArray>, targets: IntArray, lambda: Double, rate: Double, iterations: Int): List<Checkpoint> {
        var weights = DoubleArray(vectors[0].size);
        val checkpoints = mutableListOf(Checkpoint(0, weights))
        for (t in 1..iterations) {
            val gradient = Logistic.gradient(weights, vectors, targets, lambda);
            weights = DoubleArray(weights.size) {
                weights[it] - rate * gradient[it]
            };
            if (t % 100 == 0) checkpoints.add(Checkpoint(t, weights))
        }
        return checkpoints
    }
    fun sgd(vectors: Array<DoubleArray>, targets: IntArray, lambda: Double, rate: Double, batch: Int, epochs: Int, seed: Int): List<Checkpoint> {
        val random = Minstd(seed);
        val order = IntArray(vectors.size) {
            it
        };
        var weights = DoubleArray(vectors[0].size);
        val checkpoints = mutableListOf(Checkpoint(0, weights))
        for (epoch in 1..epochs) {
            random.shuffle(order)
            for (start in order.indices step batch) {
                val count = minOf(batch, order.size - start);
                val x = Array(count) {
                    vectors[order[start + it]]
                };
                val y = IntArray(count) {
                    targets[order[start + it]]
                };
                val gradient = Logistic.gradient(weights, x, y, lambda);
                weights = DoubleArray(weights.size) {
                    weights[it] - rate * gradient[it]
                }
            }
            checkpoints.add(Checkpoint(epoch, weights))
        }
        return checkpoints
    }
}
