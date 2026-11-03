final class Kernels {
    record Result(double value, double[] weights, double zeta) {}
    static Result estimate(Dataset.Series data, int position, int bandwidth, String kernel,
                           boolean localLinear) {
        int n = data.n, used = 0;
        double[] weights = new double[n], values = new double[n], distances = new double[n];
        double x0 = position / 100.0, h = bandwidth / 100.0, s0 = 0, s1 = 0, s2 = 0, t0 = 0, t1 = 0;
        for (int j = 0; j < n; j++)
            if (Math.abs(data.positions[j] - position) < bandwidth) {
                double d = data.x[j] - x0, u = d / h, t = 1 - u * u;
                double k = kernel.equals("epanechnikov") ? 0.75 * t
                           : kernel.equals("biweight")   ? 0.9375 * t * t
                                                         : 1.09375 * t * t * t;
                values[j] = k;
                distances[j] = d;
                used++;
                s0 += k;
                s1 += k * d;
                s2 += k * d * d;
                t0 += k * data.y[j];
                t1 += k * d * data.y[j];
            }
        if (used < (localLinear ? 2 : 1))
            return new Result(Double.NaN, weights, Double.NaN);
        double q = s0 * s2 - s1 * s1;
        for (int j = 0; j < n; j++)
            if (values[j] != 0)
                weights[j] = localLinear ? values[j] * (s2 - s1 * distances[j]) / q : values[j] / s0;
        return new Result(localLinear ? (s2 * t0 - s1 * t1) / q : t0 / s0, weights,
                          localLinear ? s2 / q : 1 / s0);
    }
}
