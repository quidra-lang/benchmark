class Spline(val data: Dataset.Series, val lambda: Double, diagnostics: Boolean) {
    data class Fit(val fitted: DoubleArray, val gamma: DoubleArray)
    val h = DoubleArray(data.n - 1) {
        data.x[it + 1] - data.x[it]
    };
    val d = DoubleArray(data.n - 2);
    val l1 = DoubleArray(data.n - 2);
    val l2 = DoubleArray(data.n - 2);
    val fit: Fit;
    var basis: List<Fit> = emptyList();
    var leverage: DoubleArray? = null;
    var edf = 0.0
    init {
        val size = data.n - 2;
        val a = DoubleArray(size);
        val b = DoubleArray(size);
        val c = DoubleArray(size);
        val diagonal = DoubleArray(size);
        val first = DoubleArray(size);
        val second = DoubleArray(size)
        for (i in 0 until size) {
            a[i] = 1 / h[i];
            c[i] = 1 / h[i + 1];
            b[i] = -(a[i] + c[i]);
            diagonal[i] = (h[i] + h[i + 1]) / 3 + lambda * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i])
        }
        for (i in 0 until size - 1) first[i] = h[i + 1] / 6 + lambda * c[i] * (b[i] + b[i + 1]);
        for (i in 0 until size - 2) second[i] = lambda * c[i] * c[i + 1]
        for (i in 0 until size) {
            if (i >= 2) l2[i] = second[i - 2] / d[i - 2];
            if (i >= 1) l1[i] = (first[i - 1] - if (i >= 2) l2[i] * d[i - 2] * l1[i - 1] else 0.0) / d[i - 1];
            var value = diagonal[i];
            if (i >= 1) value -= l1[i] * l1[i] * d[i - 1];
            if (i >= 2) value -= l2[i] * l2[i] * d[i - 2];
            d[i] = value
        }
        fit = fitValues(data.y);
        if (diagnostics) prepare()
    }
    fun fitValues(values: DoubleArray): Fit {
        val n = data.n;
        val size = n - 2;
        val z = DoubleArray(size);
        val gamma = DoubleArray(n);
        val fitted = DoubleArray(n)
        for (i in 0 until size) {
            var value = (values[i + 2] - values[i + 1]) / h[i + 1] - (values[i + 1] - values[i]) / h[i];
            if (i >= 1) value -= l1[i] * z[i - 1];
            if (i >= 2) value -= l2[i] * z[i - 2];
            z[i] = value
        }
        for (i in size - 1 downTo 0) {
            var value = z[i] / d[i];
            if (i + 1 < size) value -= l1[i + 1] * gamma[i + 2];
            if (i + 2 < size) value -= l2[i + 2] * gamma[i + 3];
            gamma[i + 1] = value
        }
        for (i in 0 until n) {
            val omega = when (i) {
                0 -> (gamma[1] - gamma[0]) / h[0];
                n - 1 -> 0 - (gamma[n - 1] - gamma[n - 2]) / h[n - 2];
                else -> (gamma[i + 1] - gamma[i]) / h[i] - (gamma[i] - gamma[i - 1]) / h[i - 1]
            };
            fitted[i] = values[i] - lambda * omega
        };
        return Fit(fitted,gamma)
    }
    fun evaluate(fit: Fit, position: Int): Double {
        val n = data.n;
        var index = 0;
        while (index < n && data.positions[index] < position) index++;
        val g = fit.fitted;
        val gamma = fit.gamma;
        val x0 = position / 100.0
        if (index < n && data.positions[index] == position) return g[index]
        if (index == 0) {
            val tau = (g[1] - g[0]) / h[0] - h[0] * gamma[1] / 6;
            return g[0] - (data.x[0] - x0) * tau
        }
        if (index == n) {
            val tau = (g[n - 1] - g[n - 2]) / h[n - 2] + h[n - 2] * gamma[n - 2] / 6;
            return g[n - 1] + (x0 - data.x[n - 1]) * tau
        }
        val i = index - 1;
        val pl = x0 - data.x[i];
        val pr = data.x[i + 1] - x0;
        return (pl * g[i + 1] + pr * g[i]) / h[i] - pl * pr * ((1 + pl / h[i]) * gamma[i + 1] + (1 + pr / h[i]) * gamma[i]) / 6
    }
    fun prepare() {
        if (basis.isNotEmpty()) return;
        basis = List(data.n) {
            i -> val unit = DoubleArray(data.n);
            unit[i] = 1.0;
            fitValues(unit)
        };
        val diagonal = DoubleArray(data.n);
        for (i in 0 until data.n) {
            diagonal[i] = basis[i].fitted[i];
            edf += diagonal[i]
        };
        leverage = diagonal
    }
    fun estimate(position: Int): Kernels.Result {
        prepare();
        return Kernels.Result(evaluate(fit,position),DoubleArray(data.n) {
            evaluate(basis[it],position)
        },Double.NaN)
    }
}
