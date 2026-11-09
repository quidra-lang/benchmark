import java.util.*;
final class Loess {
    record Round(double scale, int zeros, double change) {}
    final Dataset.Series data;
    final int degree, span;
    final double[] rho, fitted, leverage;
    final List<Round> rounds = new ArrayList<>();
    double edf;
    static double median(double[] values) {
        double[] sorted = values.clone();
        Arrays.sort(sorted);
        int n = sorted.length;
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }
    static double[][] cholesky(double[][] a) {
        int n = a.length;
        double[][] l = new double[n][n];
        for (int k = 0; k < n; k++)
            for (int j = 0; j <= k; j++) {
                double value = a[k][j];
                for (int i = 0; i < j; i++)
                    value -= l[k][i] * l[j][i];
                l[k][j] = k == j ? Math.sqrt(value) : value / l[j][j];
            }
        return l;
    }
    static double[] solve(double[][] l, double[] right) {
        int n = l.length;
        double[] eta = new double[n], result = new double[n];
        for (int k = 0; k < n; k++) {
            double value = right[k];
            for (int j = 0; j < k; j++)
                value -= l[k][j] * eta[j];
            eta[k] = value / l[k][k];
        }
        for (int k = n - 1; k >= 0; k--) {
            double value = eta[k];
            for (int j = k + 1; j < n; j++)
                value -= l[j][k] * result[j];
            result[k] = value / l[k][k];
        }
        return result;
    }
    Kernels.Result estimate(int position) {
        int n = data.n, count = span * n / 100, size = degree + 1;
        Integer[] ordered = new Integer[n];
        for (int i = 0; i < n; i++)
            ordered[i] = i;
        Arrays.sort(ordered, Comparator.<Integer>comparingInt(i -> Math.abs(data.positions[i] - position))
                                 .thenComparingInt(i -> i));
        boolean[] selected = new boolean[n];
        for (int i = 0; i < count; i++)
            selected[ordered[i]] = true;
        int extent = Math.abs(data.positions[ordered[count - 1]] - position);
        double[][] a = new double[size][size], basis = new double[n][size];
        double[] right = new double[size], v = new double[n];
        double x0 = position / 100.0;
        for (int j = 0; j < n; j++)
            if (selected[j]) {
                double ratio = (double)Math.abs(data.positions[j] - position) / extent,
                       s = 1 - ratio * ratio * ratio, weight = s * s * s * rho[j], d = data.x[j] - x0;
                v[j] = weight;
                basis[j][0] = 1;
                basis[j][1] = d;
                if (degree == 2)
                    basis[j][2] = d * d;
                for (int k = 0; k < size; k++) {
                    right[k] += weight * basis[j][k] * data.y[j];
                    for (int l = 0; l < size; l++)
                        a[k][l] += weight * basis[j][k] * basis[j][l];
                }
            }
        double[][] l = cholesky(a);
        double[] beta = solve(l, right), unit = new double[size];
        unit[0] = 1;
        double[] zeta = solve(l, unit), weights = new double[n];
        for (int j = 0; j < n; j++)
            if (selected[j]) {
                double total = 0;
                for (int k = 0; k < size; k++)
                    total += zeta[k] * basis[j][k];
                weights[j] = v[j] * total;
            }
        return new Kernels.Result(beta[0], weights, zeta[0]);
    }
    Loess(Dataset.Series data, int degree, int span, int iterations, boolean diagnostics) {
        this.data = data;
        this.degree = degree;
        this.span = span;
        rho = new double[data.n];
        Arrays.fill(rho, 1);
        fitted = new double[data.n];
        leverage = new double[data.n];
        if (!diagnostics)
            return;
        for (int i = 0; i < data.n; i++)
            fitted[i] = estimate(data.positions[i]).value();
        for (int t = 0; t < iterations; t++) {
            double[] absolute = new double[data.n], errors = new double[data.n];
            for (int i = 0; i < data.n; i++) {
                errors[i] = data.y[i] - fitted[i];
                absolute[i] = Math.abs(errors[i]);
            }
            double scale = median(absolute);
            int zeros = 0;
            for (int i = 0; i < data.n; i++) {
                double u = errors[i] / (6 * scale), v = 1 - u * u;
                rho[i] = Math.abs(u) < 1 ? v * v : 0;
                if (rho[i] == 0)
                    zeros++;
            }
            double[] next = new double[data.n];
            double change = 0;
            for (int i = 0; i < data.n; i++) {
                next[i] = estimate(data.positions[i]).value();
                change = Math.max(change, Math.abs(next[i] - fitted[i]));
            }
            System.arraycopy(next, 0, fitted, 0, data.n);
            rounds.add(new Round(scale, zeros, change));
        }
        for (int i = 0; i < data.n; i++) {
            leverage[i] = rho[i] * estimate(data.positions[i]).zeta();
            edf += leverage[i];
        }
    }
}
