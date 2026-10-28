import kotlin.math.abs
object Kernels {
    data class Result(val value: Double, val weights: DoubleArray, val zeta: Double)
    fun estimate(data: Dataset.Series, position: Int, bandwidth: Int, kernel: String, localLinear: Boolean): Result {
        val n = data.n;
        var used = 0;
        val weights = DoubleArray(n);
        val values = DoubleArray(n);
        val distances = DoubleArray(n);
        val x0 = position / 100.0;
        val h = bandwidth / 100.0;
        var s0 = 0.0;
        var s1 = 0.0;
        var s2 = 0.0;
        var t0 = 0.0;
        var t1 = 0.0
        for (j in 0 until n) if (abs(data.positions[j] - position) < bandwidth) {
            val d = data.x[j] - x0;
            val u = d / h;
            val t = 1 - u * u;
            val k = when (kernel) {
                "epanechnikov" -> 0.75 * t;
                "biweight" -> 0.9375 * t * t;
                else -> 1.09375 * t * t * t
            };
            values[j] = k;
            distances[j] = d;
            used++;
            s0 += k;
            s1 += k * d;
            s2 += k * d * d;
            t0 += k * data.y[j];
            t1 += k * d * data.y[j]
        }
        if (used < if (localLinear) 2 else 1) return Result(Double.NaN,weights,Double.NaN)
        val q = s0 * s2 - s1 * s1
        for (j in 0 until n) if (values[j] != 0.0) weights[j] = if (localLinear) values[j] * (s2 - s1 * distances[j]) / q else values[j] / s0
        return Result(if (localLinear) (s2 * t0 - s1 * t1) / q else t0 / s0,weights,if (localLinear) s2 / q else 1 / s0)
    }
}
