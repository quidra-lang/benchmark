import kotlin.math.abs
import kotlin.math.sqrt
class Loess(val data: Dataset.Series, val degree: Int, val span: Int, iterations: Int, diagnostics: Boolean) {
    data class Round(val scale: Double, val zeros: Int, val change: Double)
    companion object {
        fun median(values: DoubleArray): Double {
            val sorted = values.sortedArray();
            val n = sorted.size;
            return if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        }
        fun cholesky(a: Array<DoubleArray>): Array<DoubleArray> {
            val n = a.size;
            val l = Array(n) {
                DoubleArray(n)
            };
            for (k in 0 until n) for (j in 0..k) {
                var value = a[k][j];
                for (i in 0 until j) value -= l[k][i] * l[j][i];
                l[k][j] = if (k == j) sqrt(value) else value / l[j][j]
            };
            return l
        }
        fun solve(l: Array<DoubleArray>, right: DoubleArray): DoubleArray {
            val n = l.size;
            val eta = DoubleArray(n);
            val result = DoubleArray(n);
            for (k in 0 until n) {
                var value = right[k];
                for (j in 0 until k) value -= l[k][j] * eta[j];
                eta[k] = value / l[k][k]
            };
            for (k in n - 1 downTo 0) {
                var value = eta[k];
                for (j in k + 1 until n) value -= l[j][k] * result[j];
                result[k] = value / l[k][k]
            };
            return result
        }
    }
    val rho = DoubleArray(data.n) {
        1.0
    };
    val fitted = DoubleArray(data.n);
    val leverage = DoubleArray(data.n);
    val rounds = mutableListOf<Round>();
    var edf = 0.0
    fun estimate(position: Int): Kernels.Result {
        val n = data.n;
        val count = span * n / 100;
        val size = degree + 1;
        val ordered = (0 until n).sortedWith(compareBy<Int> {
            abs(data.positions[it] - position)
        }.thenBy {
            it
        });
        val selected = BooleanArray(n);
        for (i in 0 until count) selected[ordered[i]] = true;
        val extent = abs(data.positions[ordered[count - 1]] - position)
        val a = Array(size) {
            DoubleArray(size)
        };
        val basis = Array(n) {
            DoubleArray(size)
        };
        val right = DoubleArray(size);
        val v = DoubleArray(n);
        val x0 = position / 100.0
        for (j in 0 until n) if (selected[j]) {
            val ratio = abs(data.positions[j] - position).toDouble() / extent;
            val s = 1 - ratio * ratio * ratio;
            val weight = s * s * s * rho[j];
            val d = data.x[j] - x0;
            v[j] = weight;
            basis[j][0] = 1.0;
            basis[j][1] = d;
            if (degree == 2) basis[j][2] = d * d;
            for (k in 0 until size) {
                right[k] += weight * basis[j][k] * data.y[j];
                for (l in 0 until size) a[k][l] += weight * basis[j][k] * basis[j][l]
            }
        }
        val factor = cholesky(a);
        val beta = solve(factor,right);
        val unit = DoubleArray(size);
        unit[0] = 1.0;
        val zeta = solve(factor,unit);
        val weights = DoubleArray(n)
        for (j in 0 until n) if (selected[j]) {
            var total = 0.0;
            for (k in 0 until size) total += zeta[k] * basis[j][k];
            weights[j] = v[j] * total
        }
        return Kernels.Result(beta[0],weights,zeta[0])
    }
    init {
        if (diagnostics) {
            for (i in 0 until data.n) fitted[i] = estimate(data.positions[i]).value;
            repeat(iterations) {
                val errors = DoubleArray(data.n) {
                    data.y[it] - fitted[it]
                };
                val scale = median(DoubleArray(data.n) {
                    abs(errors[it])
                });
                var zeros = 0;
                for (i in 0 until data.n) {
                    val u = errors[i] / (6 * scale);
                    val v = 1 - u * u;
                    rho[i] = if (abs(u) < 1) v * v else 0.0;
                    if (rho[i] == 0.0) zeros++
                };
                val next = DoubleArray(data.n) {
                    estimate(data.positions[it]).value
                };
                var change = 0.0;
                for (i in 0 until data.n) change = maxOf(change,abs(next[i] - fitted[i]));
                next.copyInto(fitted);
                rounds.add(Round(scale,zeros,change))
            };
            for (i in 0 until data.n) {
                leverage[i] = rho[i] * estimate(data.positions[i]).zeta;
                edf += leverage[i]
            }
        }
    }
}
