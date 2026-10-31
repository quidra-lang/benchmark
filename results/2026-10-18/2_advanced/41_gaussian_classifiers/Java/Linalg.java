import java.util.*;

final class Linalg {
    static double[][] zeros(int n) {
        return new double[n][n];
    }
    static double dot(double[] a, double[] b) {
        double sum = 0;
        for (int i = 0; i < a.length; i++)
            sum += a[i] * b[i];
        return sum;
    }
    static double[][] cholesky(double[][] a) {
        int n = a.length;
        double[][] l = zeros(n);
        for (int i = 0; i < n; i++)
            for (int j = 0; j <= i; j++) {
                double sum = 0;
                for (int k = 0; k < j; k++)
                    sum += l[i][k] * l[j][k];
                double s = a[i][j] - sum;
                l[i][j] = i == j ? Math.sqrt(s) : s / l[j][j];
            }
        return l;
    }
    static double[] forward(double[][] l, double[] r) {
        double[] z = new double[l.length];
        for (int i = 0; i < l.length; i++) {
            double sum = 0;
            for (int k = 0; k < i; k++)
                sum += l[i][k] * z[k];
            z[i] = (r[i] - sum) / l[i][i];
        }
        return z;
    }
    static double[] backward(double[][] l, double[] u) {
        int n = l.length;
        double[] v = new double[n];
        for (int i = n - 1; i >= 0; i--) {
            double sum = 0;
            for (int k = i + 1; k < n; k++)
                sum += l[k][i] * v[k];
            v[i] = (u[i] - sum) / l[i][i];
        }
        return v;
    }
    static double logDet(double[][] l) {
        double sum = 0;
        for (int i = 0; i < l.length; i++)
            sum += Math.log(l[i][i]);
        return 2 * sum;
    }
    static double quadratic(double[][] l, double[] r) {
        double[] z = forward(l, r);
        return dot(z, z);
    }
    record Eigen(double[] values, double[][] vectors, int sweeps) {}
    static Eigen jacobi(double[][] a) {
        int n = a.length;
        double[][] m = zeros(n), v = zeros(n);
        for (int i = 0; i < n; i++) {
            m[i] = a[i].clone();
            v[i][i] = 1;
        }
        int sweeps = 0;
        while (true) {
            double sum = 0;
            for (int i = 0; i < n - 1; i++)
                for (int j = i + 1; j < n; j++)
                    sum += m[i][j] * m[i][j];
            if (Math.sqrt(sum) < 1e-12 || sweeps == 50)
                break;
            for (int a0 = 0; a0 < n - 1; a0++)
                for (int b0 = a0 + 1; b0 < n; b0++) {
                    if (m[a0][b0] == 0)
                        continue;
                    double theta = (m[b0][b0] - m[a0][a0]) / (2 * m[a0][b0]),
                           t = (theta >= 0 ? 1 : -1) / (Math.abs(theta) + Math.sqrt(theta * theta + 1)),
                           co = 1 / Math.sqrt(t * t + 1), si = t * co;
                    for (int k = 0; k < n; k++) {
                        if (k == a0 || k == b0)
                            continue;
                        double x = m[k][a0], y = m[k][b0];
                        m[k][a0] = m[a0][k] = co * x - si * y;
                        m[k][b0] = m[b0][k] = si * x + co * y;
                    }
                    double w = m[a0][b0];
                    m[a0][a0] -= t * w;
                    m[b0][b0] += t * w;
                    m[a0][b0] = m[b0][a0] = 0;
                    for (int k = 0; k < n; k++) {
                        double x = v[k][a0], y = v[k][b0];
                        v[k][a0] = co * x - si * y;
                        v[k][b0] = si * x + co * y;
                    }
                }
            sweeps++;
        }
        double[] values = new double[n];
        for (int i = 0; i < n; i++)
            values[i] = m[i][i];
        return new Eigen(values, v, sweeps);
    }
    static List<Integer> decreasing(double[] values) {
        List<Integer> indices = new ArrayList<>();
        for (int i = 0; i < values.length; i++)
            indices.add(i);
        indices.sort(
            (a, b) -> values[a] != values[b] ? Double.compare(values[b], values[a]) : Integer.compare(a, b));
        return indices;
    }
}
